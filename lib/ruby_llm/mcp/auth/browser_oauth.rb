# frozen_string_literal: true

require "cgi"
require "socket"

module RubyLLM
  module MCP
    module Auth
      # Browser-based OAuth authentication with local callback server
      # Opens user's browser for authorization and handles callback automatically
      class BrowserOAuth
        attr_reader :oauth_provider, :callback_port, :callback_path, :logger, :custom_success_page,
                    :custom_error_page

        # @param oauth_provider [OAuthProvider] OAuth provider instance
        # @param callback_port [Integer] port for local callback server
        # @param callback_path [String] path for callback URL
        # @param logger [Logger] logger instance
        # @param pages [Hash] optional custom pages
        # @option pages [String, Proc] :success_page custom HTML for success page (string or callable)
        # @option pages [String, Proc] :error_page custom HTML for error page (string or callable accepting error_message)
        def initialize(oauth_provider, callback_port: 8080, callback_path: "/callback", logger: nil,
                       pages: {})
          @oauth_provider = oauth_provider
          @callback_port = callback_port
          @callback_path = callback_path
          @logger = logger || MCP.logger
          @custom_success_page = pages[:success_page]
          @custom_error_page = pages[:error_page]

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
              raise Errors::TimeoutError.new(message: "OAuth authorization timed out after #{timeout} seconds")
            end

            if result[:error]
              raise Errors::TransportError.new(message: "OAuth authorization failed: #{result[:error]}")
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
              message: "Cannot start OAuth callback server: port #{@callback_port} is already in use. " \
                       "Please close the application using this port or choose a different callback_port."
            )
          rescue StandardError => e
            raise Errors::TransportError.new(
              message: "Failed to start OAuth callback server on port #{@callback_port}: #{e.message}"
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
          configure_client_socket(client)

          request_line = read_request_line(client)
          return unless request_line

          method_name, path = extract_request_parts(request_line)
          return unless method_name && path

          @logger.debug("Received #{method_name} request: #{path}")
          read_http_headers(client)

          return unless valid_callback_path?(client, path)

          params = parse_callback_params(path)
          oauth_params = extract_oauth_params(params)

          update_result_with_oauth_params(oauth_params, result, mutex, condition)
          send_callback_response(client, result)
        ensure
          client&.close
        end

        def configure_client_socket(client)
          client.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [5, 0].pack("l_2"))
        end

        def read_request_line(client)
          client.gets
        end

        def extract_request_parts(request_line)
          parts = request_line.split
          return nil unless parts.length >= 2

          parts[0..1]
        end

        def read_http_headers(client)
          header_count = 0
          loop do
            break if header_count >= 100

            line = client.gets
            break if line.nil? || line.strip.empty?

            header_count += 1
          end
        end

        def valid_callback_path?(client, path)
          uri_path, = path.split("?", 2)

          return true if uri_path == @callback_path

          send_http_response(client, 404, "text/plain", "Not Found")
          false
        end

        def parse_callback_params(path)
          _, query_string = path.split("?", 2)
          params = parse_query_params(query_string || "")
          @logger.debug("Callback params: #{params.keys.join(', ')}")
          params
        end

        def extract_oauth_params(params)
          {
            code: params["code"],
            state: params["state"],
            error: params["error"],
            error_description: params["error_description"]
          }
        end

        def update_result_with_oauth_params(oauth_params, result, mutex, condition)
          mutex.synchronize do
            if oauth_params[:error]
              result[:error] = oauth_params[:error_description] || oauth_params[:error]
            elsif oauth_params[:code] && oauth_params[:state]
              result[:code] = oauth_params[:code]
              result[:state] = oauth_params[:state]
            else
              result[:error] = "Invalid callback: missing code or state parameter"
            end
            result[:completed] = true
            condition.signal
          end
        end

        def send_callback_response(client, result)
          if result[:error]
            send_http_response(client, 400, "text/html", error_page(result[:error]))
          else
            send_http_response(client, 200, "text/html", success_page)
          end
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
          return @custom_success_page.call if @custom_success_page.respond_to?(:call)
          return @custom_success_page if @custom_success_page.is_a?(String)

          default_success_page
        end

        # Default HTML success page
        # @return [String] HTML content
        def default_success_page
          <<~HTML
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
              <title>RubyLLM MCP — Success</title>
              <link rel="icon" type="image/svg+xml" href="https://www.rubyllm-mcp.com/assets/images/favicon/favicon.svg">
              <link rel="alternate icon" type="image/x-icon" href="https://www.rubyllm-mcp.com/assets/images/favicon/favicon.ico">
              <style>
                :root {
                  --ruby-500: #CC342D;
                  --ruby-600: #B82E28;
                  --green-500: #22C55E;
                  --green-600: #16A34A;

                  --text-900: #111827;
                  --text-600: #4B5563;
                  --card-bg: #f4f3f2;
                  --logo-border: rgba(0, 0, 0, 0.5);
                  --shadow-xl: 0 25px 50px -12px rgba(0,0,0,0.35);
                  --radius-3xl: 1.5rem;
                  color-scheme: light dark;
                }

                /* Page background with layered radial gradients (from your React inline style) */
                html, body { height: 100%; }
                body {
                  margin: 0;
                  display: grid;
                  place-items: center;
                  padding: 1rem;
                  background:
                    radial-gradient(at 20% 30%, #8B0000 0%, transparent 50%),
                    radial-gradient(at 80% 70%, #FFFFFF 0%, transparent 40%),
                    radial-gradient(at 40% 80%, #B22222 0%, transparent 50%),
                    radial-gradient(at 60% 20%, #FFE4E4 0%, transparent 45%),
                    radial-gradient(at 10% 70%, #1a1a1a 0%, transparent 50%),
                    radial-gradient(at 90% 30%, #4a4a4a 0%, transparent 45%),
                    linear-gradient(135deg, #CC342D 0%, #E94B3C 50%, #FF6B6B 100%);
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans", sans-serif;
                }

                /* Card */
                .card {
                  width: 100%;
                  max-width: 32rem;
                  background: var(--card-bg);
                  color: var(--text-900);
                  border-radius: var(--radius-3xl);
                  box-shadow: var(--shadow-xl);
                  text-align: center;
                  padding: 3rem;
                  opacity: 0;
                  transform: scale(0.8);
                  animation: pop-in 500ms ease-out forwards;
                }

                /* MCP logo + border */
                .logo {
                  width: 120px;
                  height: 120px;
                  display: block;
                  margin: 0 auto 1.5rem;
                  border-radius: 1rem;
                  border: 2px solid var(--logo-border);
                  background: transparent;
                }

                /* SVG check animation */
                .checkwrap {
                  display: flex;
                  justify-content: center;
                  margin-bottom: 2rem;
                }
                .checkmark { width: 120px; height: 120px; overflow: visible; }
                .circle {
                  fill: none;
                  stroke: var(--green-600);
                  stroke-width: 4;
                  opacity: 0;
                  stroke-dasharray: 339.292; /* ~2πr for r=54 */
                  stroke-dashoffset: 339.292;
                  animation: draw-circle 800ms ease-in-out forwards;
                }
                .tick {
                  fill: none;
                  stroke: var(--green-600);
                  stroke-width: 6;
                  stroke-linecap: round;
                  stroke-linejoin: round;
                  opacity: 0;
                  stroke-dasharray: 120;
                  stroke-dashoffset: 120;
                  animation: draw-tick 600ms ease-in-out 500ms forwards;
                }
                @media (prefers-color-scheme: dark) {
                  .tick, .circle {
                    stroke: var(--green-600);
                    stroke-width: 6;
                    paint-order: stroke fill;
                    stroke-linecap: round;
                    stroke-linejoin: round;
                    filter: drop-shadow(0 0 2px rgba(255,255,255,0.2));
                  }
                }
                /* Content entrance */
                .content {
                  opacity: 0;
                  transform: translateY(20px);
                  animation: rise-in 500ms ease-out 800ms forwards;
                }
                h1 {
                  margin: 0 0 1rem 0;
                  font-size: 2rem;
                  line-height: 1.2;
                }
                p { margin: 0 0 2rem 0; color: var(--text-600); }

                /* Button */
                .btn {
                  display: inline-block;
                  padding: 0.75rem 2rem;
                  border-radius: 9999px;
                  background: var(--ruby-500);
                  color: #fff;
                  border: none;
                  cursor: pointer;
                  box-shadow: 0 10px 20px rgba(0,0,0,0.15);
                  transition: transform 120ms ease, box-shadow 180ms ease, background-color 180ms ease;
                  will-change: transform;
                  font-weight: 600;
                }
                .btn:hover {
                  background: var(--ruby-600);
                  transform: scale(1.05);
                  box-shadow: 0 14px 28px rgba(0,0,0,0.2);
                }
                .btn:active { transform: scale(0.95); }
                .btn:focus-visible {
                  outline: 3px solid rgba(204,52,45,0.35);
                  outline-offset: 2px;
                }

                /* Animations */
                @keyframes pop-in { to { opacity: 1; transform: scale(1); } }
                @keyframes draw-circle {
                  0% { opacity: 0; stroke-dashoffset: 339.292; }
                  20% { opacity: 1; }
                  100% { opacity: 1; stroke-dashoffset: 0; }
                }
                @keyframes draw-tick {
                  0% { opacity: 0; stroke-dashoffset: 120; }
                  30% { opacity: 1; }
                  100% { opacity: 1; stroke-dashoffset: 0; }
                }
                @keyframes rise-in { to { opacity: 1; transform: translateY(0); } }

                /* Motion-reduction respect */
                @media (prefers-reduced-motion: reduce) {
                  .card, .circle, .tick, .content { animation: none !important; }
                  .card { opacity: 1; transform: none; }
                  .content { opacity: 1; transform: none; }
                }

                /* =========================
                   Dark Mode (automatic)
                   ========================= */
                @media (prefers-color-scheme: dark) {
                  :root {
                    --text-900: #F3F4F6;     /* near-white */
                    --text-600: #D1D5DB;     /* soft gray */
                    --card-bg: #151417;      /* deep neutral to flatter the logo */
                    --logo-border: rgba(255, 255, 255, 0.35);
                    --shadow-xl: 0 25px 50px -12px rgba(0,0,0,0.7);
                    /* brighten the success strokes a touch on dark */
                    --green-600: #22C55E;    /* use brighter green on dark */
                  }

                  body {
                    /* Darker background variant keeping brand feel */
                    background:
                      radial-gradient(at 20% 30%, #560606 0%, transparent 50%),
                      radial-gradient(at 80% 70%, #2a2a2a 0%, transparent 40%),
                      radial-gradient(at 40% 80%, #6d1414 0%, transparent 50%),
                      radial-gradient(at 60% 20%, #3a2a2a 0%, transparent 45%),
                      radial-gradient(at 10% 70%, #0e0e0e 0%, transparent 50%),
                      radial-gradient(at 90% 30%, #1a1a1a 0%, transparent 45%),
                      linear-gradient(135deg, #7e1f1b 0%, #a62b26 50%, #b43b3b 100%);
                  }

                  .btn {
                    box-shadow: 0 10px 20px rgba(0,0,0,0.5);
                  }
                  .btn:hover {
                    box-shadow: 0 14px 28px rgba(0,0,0,0.6);
                  }
                }
              </style>

              <meta name="theme-color" media="(prefers-color-scheme: light)" content="#CC342D">
              <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#151417" />
            </head>
            <body>
              <main class="card" role="dialog" aria-labelledby="title" aria-describedby="desc">
                <img
                  class="logo"
                  src="https://www.rubyllm-mcp.com/assets/images/rubyllm-mcp-logo.svg"
                  alt="RubyLLM MCP Logo"
                  decoding="async"
                  fetchpriority="high"
                />

                <div class="checkwrap">
                  <svg class="checkmark" viewBox="0 0 120 120" aria-hidden="true">
                    <circle class="circle" cx="60" cy="60" r="54"></circle>
                    <path class="tick" d="M 35 60 L 52 77 L 85 44"></path>
                  </svg>
                </div>

                <div class="content">
                  <h1 id="title">Authentication Successful!</h1>
                  <p id="desc">You can close this window and return to your application.</p>
                  <button class="btn" type="button" onclick="window.close()">Close</button>
                </div>
              </main>
            </body>
            </html>
          HTML
        end

        # HTML error page
        # @param error_message [String] error message
        # @return [String] HTML content
        def error_page(error_message)
          if @custom_error_page.respond_to?(:call)
            return @custom_error_page.call(error_message)
          elsif @custom_error_page.is_a?(String)
            return @custom_error_page
          end

          default_error_page(error_message)
        end

        # Default HTML error page
        # @param error_message [String] error message
        # @return [String] HTML content
        def default_error_page(error_message)
          <<~HTML
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
              <title>RubyLLM MCP — Authentication Failed</title>
              <link rel="icon" type="image/svg+xml" href="https://www.rubyllm-mcp.com/assets/images/favicon/favicon.svg">
              <link rel="alternate icon" type="image/x-icon" href="https://www.rubyllm-mcp.com/assets/images/favicon/favicon.ico">
              <style>
                :root {
                  color-scheme: light dark; /* Hint to the browser UI */
                  --ruby-500: #CC342D;
                  --ruby-600: #B82E28;

                  --text-900: #111827;
                  --text-600: #4B5563;
                  --card-bg: #ffffff;
                  --logo-border: rgba(0, 0, 0, 0.5);

                  --shadow-xl: 0 25px 50px -12px rgba(0,0,0,0.35);
                  --radius-3xl: 1.5rem;

                  --error-bg: #ffebee;   /* light mode error panel */
                  --error-border: #f44336;
                }

                /* Page background (matches Success page) */
                html, body { height: 100%; }
                body {
                  margin: 0;
                  display: grid;
                  place-items: center;
                  padding: 1rem;
                  background:
                    radial-gradient(at 20% 30%, #8B0000 0%, transparent 50%),
                    radial-gradient(at 80% 70%, #FFFFFF 0%, transparent 40%),
                    radial-gradient(at 40% 80%, #B22222 0%, transparent 50%),
                    radial-gradient(at 60% 20%, #FFE4E4 0%, transparent 45%),
                    radial-gradient(at 10% 70%, #1a1a1a 0%, transparent 50%),
                    radial-gradient(at 90% 30%, #4a4a4a 0%, transparent 45%),
                    linear-gradient(135deg, #CC342D 0%, #E94B3C 50%, #FF6B6B 100%);
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans", sans-serif;
                }

                /* Card */
                .card {
                  width: 100%;
                  max-width: 32rem;
                  background: var(--card-bg);
                  color: var(--text-900);
                  border-radius: var(--radius-3xl);
                  box-shadow: var(--shadow-xl);
                  text-align: center;
                  padding: 3rem;
                  opacity: 0;
                  transform: scale(0.8);
                  animation: pop-in 500ms ease-out forwards;
                }

                /* MCP logo */
                .logo {
                  width: 120px;
                  height: 120px;
                  display: block;
                  margin: 0 auto 1.5rem;
                  border-radius: 1rem;
                  border: 2px solid var(--logo-border);
                }

                /* Animated error icon (circle + X) */
                .iconwrap {
                  display: flex;
                  justify-content: center;
                  margin-bottom: 2rem;
                }
                .erroricon {
                  width: 120px;
                  height: 120px;
                  overflow: visible;
                }
                .circle {
                  fill: none;
                  stroke: var(--ruby-500);
                  stroke-width: 4;
                  opacity: 0;
                  stroke-dasharray: 339.292; /* 2πr for r=54 */
                  stroke-dashoffset: 339.292;
                  animation: draw-circle 800ms ease-in-out forwards;
                }
                .x1, .x2 {
                  fill: none;
                  stroke: var(--ruby-500);
                  stroke-width: 6;
                  stroke-linecap: round;
                  opacity: 0;
                  stroke-dasharray: 120;
                  stroke-dashoffset: 120;
                }
                .x1 { animation: draw-x 500ms ease-in-out 500ms forwards; }
                .x2 { animation: draw-x 500ms ease-in-out 650ms forwards; }

                /* Content entrance */
                .content {
                  opacity: 0;
                  transform: translateY(20px);
                  animation: rise-in 500ms ease-out 800ms forwards;
                }
                h1 {
                  margin: 0 0 1rem 0;
                  font-size: 2rem;
                  line-height: 1.2;
                }
                p { margin: 0 0 1rem 0; color: var(--text-600); }

                /* Error message box */
                .error-box {
                  color: var(--text-900);
                  line-height: 1.6;
                  background: var(--error-bg);
                  padding: 1rem;
                  border-radius: 0.5rem;
                  border-left: 4px solid var(--error-border);
                  text-align: left;
                  word-wrap: break-word;
                  margin: 1rem 0 2rem 0;
                  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
                  white-space: pre-wrap;
                }

                /* Buttons */
                .actions {
                  display: flex;
                  justify-content: center;
                  gap: 0.75rem;
                  flex-wrap: wrap;
                }
                .btn {
                  display: inline-block;
                  padding: 0.75rem 1.25rem;
                  border-radius: 9999px;
                  background: var(--ruby-500);
                  color: #fff;
                  border: none;
                  cursor: pointer;
                  box-shadow: 0 10px 20px rgba(0,0,0,0.15);
                  transition: transform 120ms ease, box-shadow 180ms ease, background-color 180ms ease;
                  font-weight: 600;
                }
                .btn:hover {
                  background: var(--ruby-600);
                  transform: scale(1.05);
                  box-shadow: 0 14px 28px rgba(0,0,0,0.2);
                }
                .btn:active { transform: scale(0.95); }
                .btn.secondary {
                  background: #374151; /* neutral */
                }
                .btn.secondary:hover { background: #1f2937; }
                .btn:focus-visible {
                  outline: 3px solid rgba(204,52,45,0.35);
                  outline-offset: 2px;
                }

                /* Animations */
                @keyframes pop-in { to { opacity: 1; transform: scale(1); } }
                @keyframes draw-circle {
                  0% { opacity: 0; stroke-dashoffset: 339.292; }
                  20% { opacity: 1; }
                  100% { opacity: 1; stroke-dashoffset: 0; }
                }
                @keyframes draw-x {
                  0% { opacity: 0; stroke-dashoffset: 120; }
                  30% { opacity: 1; }
                  100% { opacity: 1; stroke-dashoffset: 0; }
                }
                @keyframes rise-in { to { opacity: 1; transform: translateY(0); } }

                @media (prefers-reduced-motion: reduce) {
                  .card, .circle, .x1, .x2, .content { animation: none !important; }
                  .card { opacity: 1; transform: none; }
                  .content { opacity: 1; transform: none; }
                }

                /* =========================
                   Dark Mode (automatic)
                   ========================= */
                @media (prefers-color-scheme: dark) {
                  :root {
                    --text-900: #F3F4F6;       /* near-white */
                    --text-600: #D1D5DB;       /* soft gray */
                    --card-bg: #151417;        /* deep neutral */
                    --logo-border: rgba(255, 255, 255, 0.35);
                    --shadow-xl: 0 25px 50px -12px rgba(0,0,0,0.7);

                    /* Tweak error panel for dark mode */
                    --error-bg: #2a0c0c;       /* subtle deep red panel */
                    --error-border: #EF4444;   /* brighter red left bar */
                  }

                  body {
                    /* Brand-respecting darker background */
                    background:
                      radial-gradient(at 20% 30%, #560606 0%, transparent 50%),
                      radial-gradient(at 80% 70%, #2a2a2a 0%, transparent 40%),
                      radial-gradient(at 40% 80%, #6d1414 0%, transparent 50%),
                      radial-gradient(at 60% 20%, #3a2a2a 0%, transparent 45%),
                      radial-gradient(at 10% 70%, #0e0e0e 0%, transparent 50%),
                      radial-gradient(at 90% 30%, #1a1a1a 0%, transparent 45%),
                      linear-gradient(135deg, #7e1f1b 0%, #a62b26 50%, #b43b3b 100%);
                  }

                  .btn {
                    box-shadow: 0 10px 20px rgba(0,0,0,0.5);
                  }
                  .btn:hover {
                    box-shadow: 0 14px 28px rgba(0,0,0,0.6);
                  }
                }
              </style>
            </head>
            <body>
              <main class="card" role="dialog" aria-labelledby="title" aria-describedby="desc">
                <!-- MCP Logo -->
                <img
                  class="logo"
                  src="https://www.rubyllm-mcp.com/assets/images/rubyllm-mcp-logo.svg"
                  alt="RubyLLM MCP Logo"
                  decoding="async"
                  fetchpriority="high"
                />

                <!-- Animated Error Icon -->
                <div class="iconwrap" aria-hidden="true">
                  <svg class="erroricon" viewBox="0 0 120 120">
                    <circle class="circle" cx="60" cy="60" r="54"></circle>
                    <path class="x1" d="M 42 42 L 78 78"></path>
                    <path class="x2" d="M 78 42 L 42 78"></path>
                  </svg>
                </div>

                <!-- Message + details -->
                <div class="content">
                  <h1 id="title">Authentication Failed</h1>
                  <p id="desc">Something went wrong while authenticating. See the details below:</p>

                  <div class="error-box">#{CGI.escapeHTML(error_message)}</div>

                  <div class="actions">
                    <button class="btn" type="button" onclick="window.close()">Close</button>
                  </div>
                </div>
              </main>
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
