# frozen_string_literal: true

require "cgi"
require "socket"
require_relative "oauth_provider"

module RubyLLM
  module MCP
    module Auth
      # Browser-based OAuth authentication with local callback server
      # Opens user's browser for authorization and handles callback automatically
      class BrowserOAuth
        attr_reader :oauth_provider, :callback_port, :callback_path, :logger

        def initialize(oauth_provider, callback_port: 8080, callback_path: "/callback", logger: nil)
          @oauth_provider = oauth_provider
          @callback_port = callback_port
          @callback_path = callback_path
          @logger = logger || MCP.logger

          # Ensure OAuth provider redirect_uri matches our callback server
          expected_redirect_uri = "http://localhost:#{callback_port}#{callback_path}"
          return unless oauth_provider.redirect_uri != expected_redirect_uri

          @logger.warn("OAuth provider redirect_uri (#{oauth_provider.redirect_uri}) " \
                       "doesn't match callback server (#{expected_redirect_uri}). " \
                       "Updating redirect_uri.")
          oauth_provider.redirect_uri = expected_redirect_uri
        end

        # Perform complete OAuth authentication flow
        # @param timeout [Integer] seconds to wait for authorization
        # @param auto_open_browser [Boolean] automatically open browser
        # @return [Token] access token
        def authenticate(timeout: 300, auto_open_browser: true)
          # 1. Start authorization flow and get URL
          auth_url = @oauth_provider.start_authorization_flow
          @logger.debug("Authorization URL: #{auth_url}")

          # 2. Create result container for thread coordination
          result = { code: nil, state: nil, error: nil, completed: false }
          mutex = Mutex.new
          condition = ConditionVariable.new

          # 3. Start local callback server
          server = start_callback_server(result, mutex, condition)

          begin
            # 4. Open browser to authorization URL
            if auto_open_browser
              open_browser(auth_url)
              @logger.info("\nOpening browser for authorization...")
              @logger.info("If browser doesn't open automatically, visit this URL:")
            else
              @logger.info("\nPlease visit this URL to authorize:")
            end
            @logger.info(auth_url)
            @logger.info("\nWaiting for authorization...")

            # 5. Wait for callback with timeout
            mutex.synchronize do
              condition.wait(mutex, timeout) unless result[:completed]
            end

            unless result[:completed]
              raise Errors::TimeoutError.new("OAuth authorization timed out after #{timeout} seconds", nil)
            end

            if result[:error]
              raise Errors::TransportError.new("OAuth authorization failed: #{result[:error]}", nil, nil)
            end

            # 6. Complete OAuth flow
            @logger.debug("Completing OAuth authorization flow")
            token = @oauth_provider.complete_authorization_flow(result[:code], result[:state])

            @logger.info("\nAuthentication successful!")
            token
          ensure
            # Always shutdown the server
            server&.shutdown
          end
        end

        private

        # Start local HTTP callback server
        # @param result [Hash] result container for callback data
        # @param mutex [Mutex] synchronization mutex
        # @param condition [ConditionVariable] wait condition
        # @return [CallbackServer] server wrapper
        def start_callback_server(result, mutex, condition)
          begin
            server = TCPServer.new("127.0.0.1", @callback_port)
            @logger.debug("Started callback server on http://127.0.0.1:#{@callback_port}#{@callback_path}")
          rescue Errno::EADDRINUSE
            raise Errors::TransportError.new(
              "Cannot start OAuth callback server: port #{@callback_port} is already in use. " \
              "Please close the application using this port or choose a different callback_port.",
              nil, nil
            )
          rescue StandardError => e
            raise Errors::TransportError.new(
              "Failed to start OAuth callback server on port #{@callback_port}: #{e.message}",
              nil, nil
            )
          end

          running = true

          # Start server in background thread
          thread = Thread.new do
            while running
              begin
                # Use wait_readable with timeout to allow checking running flag
                next unless server.wait_readable(0.5)

                client = server.accept
                handle_http_request(client, result, mutex, condition)
              rescue IOError, Errno::EBADF
                # Server was closed, exit loop
                break
              rescue StandardError => e
                @logger.error("Error handling callback request: #{e.message}")
              end
            end
          end

          # Return an object with shutdown method
          CallbackServer.new(server, thread, -> { running = false })
        end

        # Handle incoming HTTP request on callback server
        # @param client [TCPSocket] client socket
        # @param result [Hash] result container
        # @param mutex [Mutex] synchronization mutex
        # @param condition [ConditionVariable] wait condition
        def handle_http_request(client, result, mutex, condition)
          # Set read timeout
          client.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [5, 0].pack("l_2"))

          # Read request line
          request_line = client.gets
          return unless request_line

          parts = request_line.split
          return unless parts.length >= 2

          method, path = parts[0..1]
          @logger.debug("Received #{method} request: #{path}")

          # Read headers (with limit to prevent memory exhaustion)
          header_count = 0
          loop do
            break if header_count >= 100 # Limit header count

            line = client.gets
            break if line.nil? || line.strip.empty?

            header_count += 1
          end

          # Parse path and query parameters
          uri_path, query_string = path.split("?", 2)

          # Only handle our callback path
          unless uri_path == @callback_path
            send_http_response(client, 404, "text/plain", "Not Found")
            return
          end

          # Parse query parameters
          params = parse_query_params(query_string || "")
          @logger.debug("Callback params: #{params.keys.join(', ')}")

          # Extract OAuth parameters
          code = params["code"]
          state = params["state"]
          error = params["error"]
          error_description = params["error_description"]

          # Update result and signal waiting thread
          mutex.synchronize do
            if error
              result[:error] = error_description || error
            elsif code && state
              result[:code] = code
              result[:state] = state
            else
              result[:error] = "Invalid callback: missing code or state parameter"
            end
            result[:completed] = true

            condition.signal # Wake up waiting thread
          end

          # Send response to browser
          if result[:error]
            send_http_response(client, 400, "text/html", error_page(result[:error]))
          else
            send_http_response(client, 200, "text/html", success_page)
          end
        ensure
          client&.close
        end

        # Parse URL query parameters
        # @param query_string [String] query string
        # @return [Hash] parsed parameters
        def parse_query_params(query_string)
          params = {}
          query_string.split("&").each do |param|
            next if param.empty?

            key, value = param.split("=", 2)
            params[CGI.unescape(key)] = CGI.unescape(value || "")
          end
          params
        end

        # Send HTTP response to client
        # @param client [TCPSocket] client socket
        # @param status [Integer] HTTP status code
        # @param content_type [String] content type
        # @param body [String] response body
        def send_http_response(client, status, content_type, body)
          status_text = if status == 200
                          "OK"
                        else
                          (status == 400 ? "Bad Request" : "Not Found")
                        end

          response = "HTTP/1.1 #{status} #{status_text}\r\n"
          response += "Content-Type: #{content_type}\r\n"
          response += "Content-Length: #{body.bytesize}\r\n"
          response += "Connection: close\r\n"
          response += "\r\n"
          response += body

          client.write(response)
        rescue IOError, Errno::EPIPE => e
          @logger.debug("Error sending response: #{e.message}")
        end

        # Open browser to URL
        # @param url [String] URL to open
        # @return [Boolean] true if successful
        def open_browser(url)
          case RbConfig::CONFIG["host_os"]
          when /darwin/
            system("open", url)
          when /linux|bsd/
            system("xdg-open", url)
          when /mswin|mingw|cygwin/
            system("start", url)
          else
            @logger.warn("Unknown operating system, cannot open browser automatically")
            false
          end
        rescue StandardError => e
          @logger.warn("Failed to open browser: #{e.message}")
          false
        end

        # HTML success page
        # @return [String] HTML content
        def success_page
          <<~HTML
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Authentication Successful</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                  display: flex;
                  justify-content: center;
                  align-items: center;
                  min-height: 100vh;
                  margin: 0;
                  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                }
                .container {
                  background: white;
                  padding: 3rem;
                  border-radius: 1rem;
                  box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                  text-align: center;
                  max-width: 400px;
                }
                .checkmark {
                  width: 80px;
                  height: 80px;
                  border-radius: 50%;
                  display: block;
                  stroke-width: 4;
                  stroke: #4CAF50;
                  stroke-miterlimit: 10;
                  margin: 0 auto 1.5rem;
                  box-shadow: inset 0 0 0 #4CAF50;
                  animation: fill 0.4s ease-in-out 0.4s forwards, scale 0.3s ease-in-out 0.9s both;
                }
                .checkmark__circle {
                  stroke-dasharray: 166;
                  stroke-dashoffset: 166;
                  stroke-width: 4;
                  stroke-miterlimit: 10;
                  stroke: #4CAF50;
                  fill: none;
                  animation: stroke 0.6s cubic-bezier(0.65, 0, 0.45, 1) forwards;
                }
                .checkmark__check {
                  transform-origin: 50% 50%;
                  stroke-dasharray: 48;
                  stroke-dashoffset: 48;
                  animation: stroke 0.3s cubic-bezier(0.65, 0, 0.45, 1) 0.8s forwards;
                }
                @keyframes stroke {
                  100% { stroke-dashoffset: 0; }
                }
                @keyframes fill {
                  100% { box-shadow: inset 0 0 0 30px #4CAF50; }
                }
                h1 {
                  color: #333;
                  margin-bottom: 0.5rem;
                }
                p {
                  color: #666;
                  line-height: 1.6;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <svg class="checkmark" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 52 52">
                  <circle class="checkmark__circle" cx="26" cy="26" r="25" fill="none"/>
                  <path class="checkmark__check" fill="none" d="M14.1 27.2l7.1 7.2 16.7-16.8"/>
                </svg>
                <h1>Authentication Successful!</h1>
                <p>You can close this window and return to your application.</p>
              </div>
            </body>
            </html>
          HTML
        end

        # HTML error page
        # @param error_message [String] error message
        # @return [String] HTML content
        def error_page(error_message)
          <<~HTML
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Authentication Failed</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                  display: flex;
                  justify-content: center;
                  align-items: center;
                  min-height: 100vh;
                  margin: 0;
                  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                }
                .container {
                  background: white;
                  padding: 3rem;
                  border-radius: 1rem;
                  box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                  text-align: center;
                  max-width: 400px;
                }
                .error-icon {
                  width: 80px;
                  height: 80px;
                  border-radius: 50%;
                  background: #f44336;
                  display: flex;
                  justify-content: center;
                  align-items: center;
                  margin: 0 auto 1.5rem;
                  color: white;
                  font-size: 3rem;
                  font-weight: bold;
                }
                h1 {
                  color: #333;
                  margin-bottom: 1rem;
                }
                .error-message {
                  color: #666;
                  line-height: 1.6;
                  background: #ffebee;
                  padding: 1rem;
                  border-radius: 0.5rem;
                  border-left: 4px solid #f44336;
                  text-align: left;
                  word-wrap: break-word;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <div class="error-icon">✕</div>
                <h1>Authentication Failed</h1>
                <div class="error-message">#{CGI.escapeHTML(error_message)}</div>
              </div>
            </body>
            </html>
          HTML
        end

        # Callback server wrapper for clean shutdown
        class CallbackServer
          def initialize(server, thread, stop_proc)
            @server = server
            @thread = thread
            @stop_proc = stop_proc
          end

          def shutdown
            @stop_proc.call
            @server.close unless @server.closed?
            @thread.join(5) # Wait max 5 seconds for thread to finish
          rescue StandardError
            # Ignore shutdown errors
            nil
          end
        end
      end
    end
  end
end
