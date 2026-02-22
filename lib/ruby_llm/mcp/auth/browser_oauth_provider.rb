# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # Browser-based OAuth authentication provider
      # Provides complete OAuth 2.1 flow with automatic browser opening and local callback server
      # Compatible API with OAuthProvider for seamless interchange
      class BrowserOAuthProvider
        # Serializes logger calls so test doubles and non-thread-safe loggers remain safe
        # when callback and main threads log at the same time.
        class SynchronizedLogger
          def initialize(logger)
            @logger = logger
            @mutex = Mutex.new
          end

          def debug(...)
            synchronized_log(:debug, ...)
          end

          def info(...)
            synchronized_log(:info, ...)
          end

          def warn(...)
            synchronized_log(:warn, ...)
          end

          def error(...)
            synchronized_log(:error, ...)
          end

          private

          def synchronized_log(level, ...)
            @mutex.synchronize do
              return unless @logger.respond_to?(level)

              @logger.public_send(level, ...)
            end
          end
        end

        attr_reader :oauth_provider, :callback_port, :callback_path, :logger
        attr_accessor :server_url, :redirect_uri, :scope, :storage

        # Expose custom pages for testing/inspection
        def custom_success_page
          @pages.instance_variable_get(:@custom_success_page)
        end

        def custom_error_page
          @pages.instance_variable_get(:@custom_error_page)
        end

        # @param server_url [String] OAuth server URL (alternative to oauth_provider)
        # @param oauth_provider [OAuthProvider] OAuth provider instance (alternative to server_url)
        # @param callback_port [Integer] port for local callback server
        # @param callback_path [String] path for callback URL
        # @param logger [Logger] logger instance
        # @param storage [Object] token storage instance
        # @param redirect_uri [String] OAuth redirect URI
        # @param scope [String] OAuth scopes
        def initialize(server_url: nil, oauth_provider: nil, callback_port: 8080, callback_path: "/callback", # rubocop:disable Metrics/ParameterLists
                       logger: nil, storage: nil, redirect_uri: nil, scope: nil)
          @logger = logger || MCP.logger
          @synchronized_logger = SynchronizedLogger.new(@logger)
          @callback_port = callback_port
          @callback_path = callback_path

          # Set redirect_uri before creating oauth_provider
          redirect_uri ||= "http://localhost:#{callback_port}#{callback_path}"

          # Either accept an existing oauth_provider or create one
          if oauth_provider
            @oauth_provider = oauth_provider
            # Sync attributes from the provided oauth_provider
            @server_url = oauth_provider.server_url
            @redirect_uri = oauth_provider.redirect_uri
            @scope = oauth_provider.scope
            @storage = oauth_provider.storage
          elsif server_url
            @server_url = server_url
            @redirect_uri = redirect_uri
            @scope = scope
            @storage = storage || MemoryStorage.new
            # Create a new oauth_provider
            @oauth_provider = OAuthProvider.new(
              server_url: server_url,
              redirect_uri: redirect_uri,
              scope: scope,
              logger: @synchronized_logger,
              storage: @storage
            )
          else
            raise ArgumentError, "Either server_url or oauth_provider must be provided"
          end

          # Ensure OAuth provider redirect_uri matches our callback server
          validate_and_sync_redirect_uri!

          # Initialize browser helpers
          @http_server = Browser::HttpServer.new(port: @callback_port, logger: @synchronized_logger)
          @callback_handler = Browser::CallbackHandler.new(callback_path: @callback_path, logger: @synchronized_logger)
          @pages = Browser::Pages.new(
            custom_success_page: MCP.config.oauth.browser_success_page,
            custom_error_page: MCP.config.oauth.browser_error_page
          )
          @opener = Browser::Opener.new(logger: @synchronized_logger)
        end

        # Perform complete OAuth authentication flow with browser
        # Compatible with OAuthProvider's authentication pattern
        # @param timeout [Integer] seconds to wait for authorization
        # @param auto_open_browser [Boolean] automatically open browser
        # @return [Token] access token
        def authenticate(timeout: 300, auto_open_browser: true)
          # 1. Start authorization flow and get URL
          auth_url = @oauth_provider.start_authorization_flow
          @synchronized_logger.debug("Authorization URL: #{auth_url}")

          # 2. Create result container for thread coordination
          result = { code: nil, state: nil, error: nil, completed: false }
          mutex = Mutex.new
          condition = ConditionVariable.new

          # 3. Start local callback server
          server = start_callback_server(result, mutex, condition)

          begin
            # 4. Open browser to authorization URL
            if auto_open_browser
              @opener.open_browser(auth_url)
              @synchronized_logger.info("\nOpening browser for authorization...")
              @synchronized_logger.info("If browser doesn't open automatically, visit this URL:")
            else
              @synchronized_logger.info("\nPlease visit this URL to authorize:")
            end
            @synchronized_logger.info(auth_url)
            @synchronized_logger.info("\nWaiting for authorization...")

            # 5. Wait for callback with timeout
            mutex.synchronize do
              condition.wait(mutex, timeout) unless result[:completed]
            end

            snapshot = mutex.synchronize { result.dup }

            unless snapshot[:completed]
              raise Errors::TimeoutError.new(message: "OAuth authorization timed out after #{timeout} seconds")
            end

            if snapshot[:error]
              raise Errors::TransportError.new(message: "OAuth authorization failed: #{snapshot[:error]}")
            end

            # Stop callback server before token exchange to avoid cross-thread races
            # (observed under JRuby when background callback logging overlaps main-thread mocks).
            server&.shutdown
            server = nil

            # 6. Complete OAuth flow
            @synchronized_logger.debug("Completing OAuth authorization flow")
            token = @oauth_provider.complete_authorization_flow(snapshot[:code], snapshot[:state])

            @synchronized_logger.info("\nAuthentication successful!")
            token
          ensure
            # Always shutdown the server
            server&.shutdown
          end
        end

        # Get current access token (for compatibility with OAuthProvider)
        # @return [Token, nil] valid access token or nil
        def access_token
          @oauth_provider.access_token
        end

        # Apply authorization header to HTTP request (for compatibility with OAuthProvider)
        # @param request [HTTPX::Request] HTTP request object
        def apply_authorization(request)
          @oauth_provider.apply_authorization(request)
        end

        # Start authorization flow (for compatibility with OAuthProvider)
        # @return [String] authorization URL
        def start_authorization_flow
          @oauth_provider.start_authorization_flow
        end

        # Complete authorization flow (for compatibility with OAuthProvider)
        # @param code [String] authorization code
        # @param state [String] state parameter
        # @return [Token] access token
        def complete_authorization_flow(code, state)
          @oauth_provider.complete_authorization_flow(code, state)
        end

        # Handle authentication challenge with browser-based auth
        # @param www_authenticate [String, nil] WWW-Authenticate header value
        # @param resource_metadata [String, nil] Resource metadata URL from response/challenge
        # @param resource_metadata_url [String, nil] Legacy alias for resource_metadata
        # @param requested_scope [String, nil] Scope from WWW-Authenticate challenge
        # @return [Boolean] true if authentication was completed successfully
        def handle_authentication_challenge(www_authenticate: nil, resource_metadata: nil, resource_metadata_url: nil,
                                            requested_scope: nil)
          @synchronized_logger.debug("BrowserOAuthProvider handling authentication challenge")

          # Try standard provider's automatic handling first (token refresh, client credentials)
          begin
            return @oauth_provider.handle_authentication_challenge(
              www_authenticate: www_authenticate,
              resource_metadata: resource_metadata,
              resource_metadata_url: resource_metadata_url,
              requested_scope: requested_scope
            )
          rescue Errors::AuthenticationRequiredError
            # Standard provider couldn't handle it - need interactive auth
            @synchronized_logger.info("Automatic authentication failed, starting browser-based OAuth flow")
          end

          # Perform full browser-based authentication
          authenticate(auto_open_browser: true)
          true
        end

        # Parse WWW-Authenticate header (delegate to oauth_provider)
        # @param header [String] WWW-Authenticate header value
        # @return [Hash] parsed challenge information
        def parse_www_authenticate(header)
          @oauth_provider.parse_www_authenticate(header)
        end

        private

        # Validate and synchronize redirect_uri between this provider and oauth_provider
        def validate_and_sync_redirect_uri!
          expected_redirect_uri = "http://localhost:#{@callback_port}#{@callback_path}"

          if @oauth_provider.redirect_uri != expected_redirect_uri
            @synchronized_logger.warn("OAuth provider redirect_uri (#{@oauth_provider.redirect_uri}) " \
                                      "doesn't match callback server (#{expected_redirect_uri}). " \
                                      "Updating redirect_uri.")
            @oauth_provider.redirect_uri = expected_redirect_uri
            @redirect_uri = expected_redirect_uri
          end
        end

        # Start local HTTP callback server
        # @param result [Hash] result container for callback data
        # @param mutex [Mutex] synchronization mutex
        # @param condition [ConditionVariable] wait condition
        # @return [Browser::CallbackServer] server wrapper
        def start_callback_server(result, mutex, condition)
          server = @http_server.start_server
          @synchronized_logger.debug("Started callback server on http://127.0.0.1:#{@callback_port}#{@callback_path}")

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
                @synchronized_logger.error("Error handling callback request: #{e.message}")
              end
            end
          end

          # Return wrapper with shutdown method
          Browser::CallbackServer.new(server, thread, -> { running = false })
        end

        # Handle incoming HTTP request on callback server
        # @param client [TCPSocket] client socket
        # @param result [Hash] result container
        # @param mutex [Mutex] synchronization mutex
        # @param condition [ConditionVariable] wait condition
        def handle_http_request(client, result, mutex, condition)
          @http_server.configure_client_socket(client)

          request_line = @http_server.read_request_line(client)
          return unless request_line

          method_name, path = @http_server.extract_request_parts(request_line)
          return unless method_name && path

          @synchronized_logger.debug("Received #{method_name} request: #{path}")
          @http_server.read_http_headers(client)

          # Validate callback path
          unless @callback_handler.valid_callback_path?(path)
            @http_server.send_http_response(client, 404, "text/plain", "Not Found")
            return
          end

          # Parse and extract OAuth parameters
          params = @callback_handler.parse_callback_params(path, @http_server)
          oauth_params = @callback_handler.extract_oauth_params(params)

          # Update result with OAuth parameters
          @callback_handler.update_result_with_oauth_params(oauth_params, result, mutex, condition)

          # Send response
          if result[:error]
            @http_server.send_http_response(client, 400, "text/html", @pages.error_page(result[:error]))
          else
            @http_server.send_http_response(client, 200, "text/html", @pages.success_page)
          end
        ensure
          client&.close
        end
      end
    end
  end
end
