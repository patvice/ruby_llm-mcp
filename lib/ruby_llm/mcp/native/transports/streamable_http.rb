# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Transports
        # Configuration options for reconnection behavior
        class ReconnectionOptions
          attr_reader :max_reconnection_delay, :initial_reconnection_delay,
                      :reconnection_delay_grow_factor, :max_retries

          def initialize(
            max_reconnection_delay: 30_000,
            initial_reconnection_delay: 1_000,
            reconnection_delay_grow_factor: 1.5,
            max_retries: 2
          )
            @max_reconnection_delay = max_reconnection_delay
            @initial_reconnection_delay = initial_reconnection_delay
            @reconnection_delay_grow_factor = reconnection_delay_grow_factor
            @max_retries = max_retries
          end
        end

        # Options for starting SSE connections
        class StartSSEOptions
          attr_reader :resumption_token, :on_resumption_token, :replay_message_id

          def initialize(resumption_token: nil, on_resumption_token: nil, replay_message_id: nil)
            @resumption_token = resumption_token
            @on_resumption_token = on_resumption_token
            @replay_message_id = replay_message_id
          end
        end

        # Main StreamableHTTP transport class
        class StreamableHTTP
          include Support::Timeout

          attr_reader :session_id, :protocol_version, :coordinator, :oauth_provider

          def initialize( # rubocop:disable Metrics/ParameterLists
            url:,
            request_timeout:,
            coordinator:,
            headers: {},
            reconnection: {},
            version: :http2,
            oauth_provider: nil,
            rate_limit: nil,
            reconnection_options: nil,
            session_id: nil,
            options: {}
          )
            # Extract options if provided (for backward compatibility)
            extracted_options = options.dup
            headers = extracted_options.delete(:headers) || headers
            version = extracted_options.delete(:version) || version
            oauth_provider = extracted_options.delete(:oauth_provider) || oauth_provider
            reconnection = extracted_options.delete(:reconnection) || reconnection
            reconnection_options = extracted_options.delete(:reconnection_options) || reconnection_options
            rate_limit = extracted_options.delete(:rate_limit) || rate_limit
            session_id = extracted_options.delete(:session_id) || session_id

            @url = URI(url)
            @coordinator = coordinator
            @request_timeout = request_timeout
            @headers = headers || {}
            @session_id = session_id

            @version = version
            @reconnection_options = reconnection_options || ReconnectionOptions.new
            @protocol_version = nil
            @session_id = session_id

            @resource_metadata_url = nil
            @client_id = SecureRandom.uuid

            @reconnection_options = ReconnectionOptions.new(**reconnection)
            @oauth_provider = oauth_provider
            @rate_limiter = Support::RateLimiter.new(**rate_limit) if rate_limit

            @id_counter = 0
            @id_mutex = Mutex.new
            @pending_requests = {}
            @pending_mutex = Mutex.new
            @running = true
            @abort_controller = nil
            @sse_thread = nil
            @sse_mutex = Mutex.new

            # Track if we've attempted auth flow to prevent infinite loops
            @auth_retry_attempted = false

            # Thread-safe collection of all HTTPX clients
            @clients = []
            @clients_mutex = Mutex.new

            @connection = create_connection
          end

          def request(body, add_id: true, wait_for_response: true)
            if @rate_limiter&.exceeded?
              sleep(1) while @rate_limiter&.exceeded?
            end
            @rate_limiter&.add

            # Generate a unique request ID for requests
            if add_id && body.is_a?(Hash) && !body.key?("id")
              @id_mutex.synchronize { @id_counter += 1 }
              body["id"] = @id_counter
            end

            request_id = body.is_a?(Hash) ? body["id"] : nil
            is_initialization = body.is_a?(Hash) && body["method"] == "initialize"

            response_queue = setup_response_queue(request_id, wait_for_response)
            result = send_http_request(body, request_id, is_initialization: is_initialization)
            return result if result.is_a?(RubyLLM::MCP::Result)

            if wait_for_response && request_id
              wait_for_response_with_timeout(request_id.to_s, response_queue)
            end
          end

          def alive?
            @running
          end

          def close
            terminate_session
            cleanup_sse_resources
            cleanup_connection
          end

          def start
            @abort_controller = false
          end

          def set_protocol_version(version)
            @protocol_version = version
          end

          private

          def terminate_session
            return unless @session_id

            begin
              headers = build_common_headers
              response = @connection.delete(@url, headers: headers)

              # Handle HTTPX error responses first
              handle_httpx_error_response!(response, context: { location: "terminating session" })

              # 405 Method Not Allowed is acceptable per spec
              unless [200, 405].include?(response.status)
                reason_phrase = response.respond_to?(:reason_phrase) ? response.reason_phrase : nil
                raise Errors::TransportError.new(
                  code: response.status,
                  message: "Failed to terminate session: #{reason_phrase || response.status}"
                )
              end

              @session_id = nil
            rescue StandardError => e
              raise Errors::TransportError.new(
                message: "Failed to terminate session: #{e.message}",
                code: nil,
                error: e
              )
            end
          end

          def handle_httpx_error_response!(response, context:, allow_eof_for_sse: false)
            return false unless response.is_a?(HTTPX::ErrorResponse)

            error = response.error

            # Special handling for EOFError in SSE contexts
            if allow_eof_for_sse && error.is_a?(EOFError)
              RubyLLM::MCP.logger.info "SSE stream closed: #{response.error.message}"
              return :eof_handled
            end

            if error.is_a?(HTTPX::ReadTimeoutError)
              raise Errors::TimeoutError.new(
                message: "Request timed out after #{@request_timeout / 1000} seconds",
                request_id: context[:request_id]
              )
            end

            error_message = response.error&.message || "Request failed"
            RubyLLM::MCP.logger.error "HTTPX error in #{context[:location]}: #{error_message}"

            raise Errors::TransportError.new(
              code: nil,
              message: "HTTPX Error #{context}: #{error_message}"
            )
          end

          def register_client(client)
            @clients_mutex.synchronize do
              @clients << client
            end
            client
          end

          def unregister_client(client)
            @clients_mutex.synchronize do
              @clients.delete(client)
            end
          end

          def close_client(client)
            client.close if client.respond_to?(:close)
          rescue StandardError => e
            RubyLLM::MCP.logger.debug "Error closing HTTPX client: #{e.message}"
          ensure
            unregister_client(client)
          end

          def active_clients_count
            @clients_mutex.synchronize do
              @clients.size
            end
          end

          def create_connection
            # Use request_timeout for all timeout values (converted from ms to seconds)
            timeout_seconds = @request_timeout / 1000.0
            client = Support::HTTPClient.connection.with(
              timeout: {
                connect_timeout: 10,
                read_timeout: timeout_seconds,
                write_timeout: timeout_seconds,
                operation_timeout: timeout_seconds
              }
            )

            register_client(client)
          end

          def build_common_headers
            headers = @headers.dup

            headers["mcp-session-id"] = @session_id if @session_id
            headers["mcp-protocol-version"] = @protocol_version if @protocol_version
            headers["X-CLIENT-ID"] = @client_id
            headers["Origin"] = @url.to_s

            # Apply OAuth authorization if available
            if @oauth_provider
              RubyLLM::MCP.logger.debug "OAuth provider present, attempting to get token..."
              RubyLLM::MCP.logger.debug "  Server URL: #{@oauth_provider.server_url}"

              token = @oauth_provider.access_token
              if token
                headers["Authorization"] = token.to_header
                RubyLLM::MCP.logger.debug "Applied OAuth authorization header: #{token.to_header}"
              else
                RubyLLM::MCP.logger.warn "OAuth provider present but no valid token available!"
                RubyLLM::MCP.logger.warn "  This means the token is not in storage or has expired"
                RubyLLM::MCP.logger.warn "  Check that authentication completed successfully"
              end
            else
              RubyLLM::MCP.logger.debug "No OAuth provider configured for this transport"
            end

            headers
          end

          def setup_response_queue(request_id, wait_for_response)
            response_queue = Queue.new
            if wait_for_response && request_id
              @pending_mutex.synchronize do
                @pending_requests[request_id.to_s] = response_queue
              end
            end
            response_queue
          end

          def send_http_request(body, request_id, is_initialization: false)
            headers = build_common_headers
            headers["Content-Type"] = "application/json"
            headers["Accept"] = "application/json, text/event-stream"

            json_body = JSON.generate(body)
            RubyLLM::MCP.logger.debug "Sending Request: #{json_body}"

            request_client = nil
            begin
              # Set up connection with streaming callbacks if not initialization
              connection = if is_initialization
                             @connection
                           else
                             request_client = create_connection_with_streaming_callbacks(request_id)
                             request_client
                           end

              response = connection.post(@url, json: body, headers: headers)
              handle_response(response, request_id, body)
            ensure
              @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) } if request_id
              close_client(request_client) if request_client && !is_initialization
            end
          end

          def create_connection_with_streaming_callbacks(request_id)
            buffer = +""

            client = Support::HTTPClient.connection.plugin(:callbacks)
                                        .on_response_body_chunk do |request, _response, chunk|
              next unless @running && !@abort_controller

              RubyLLM::MCP.logger.debug "Received chunk: #{chunk.bytesize} bytes for #{request.uri}"
              buffer << chunk
              process_sse_buffer_events(buffer, request_id&.to_s)
            end
            .with(
              timeout: {
                connect_timeout: @request_timeout / 1000,
                read_timeout: @request_timeout / 1000,
                write_timeout: @request_timeout / 1000,
                operation_timeout: @request_timeout / 1000
              }
            )

            register_client(client)
          end

          def handle_response(response, request_id, original_message)
            # Handle HTTPX error responses first
            handle_httpx_error_response!(response, context: { location: "handling response", request_id: request_id })

            # Extract session ID if present (only for successful responses)
            session_id = response.headers["mcp-session-id"]
            @session_id = session_id if session_id

            case response.status
            when 200
              handle_success_response(response, request_id, original_message)
            when 202
              handle_accepted_response(original_message)
            when 404
              handle_session_expired
            when 401
              handle_authentication_challenge(response, request_id, original_message)
            when 405
              # Method not allowed - acceptable for some endpoints
              nil
            when 400...500
              handle_client_error(response)
            else
              response_body = response.respond_to?(:body) ? response.body.to_s : "Unknown error"
              raise Errors::TransportError.new(
                code: response.status,
                message: "HTTP request failed: #{response.status} - #{response_body}"
              )
            end
          end

          def handle_success_response(response, request_id, _original_message)
            content_type = response.respond_to?(:headers) ? response.headers["content-type"] : nil

            if content_type&.include?("text/event-stream")
              start_sse_stream
              nil
            elsif content_type&.include?("application/json")
              response_body = response.respond_to?(:body) ? response.body.to_s : "{}"
              if response_body == "null" # Fix related to official MCP Ruby SDK implementation
                response_body = "{}"
              end

              json_response = JSON.parse(response_body)
              result = RubyLLM::MCP::Result.new(json_response, session_id: @session_id)

              if request_id
                @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
              end

              result
            else
              raise Errors::TransportError.new(
                code: -1,
                message: "Unexpected content type: #{content_type}"
              )
            end
          rescue StandardError => e
            raise Errors::TransportError.new(
              message: "Invalid JSON response: #{e.message}",
              error: e
            )
          end

          def handle_accepted_response(original_message)
            # 202 Accepted - start SSE stream if this was an initialization
            if original_message.is_a?(Hash) && original_message["method"] == "initialize"
              start_sse_stream
            end
            nil
          end

          def handle_client_error(response)
            status_code = response.respond_to?(:status) ? response.status : "Unknown"

            # Special handling for 403 with OAuth provider
            handle_oauth_authorization_error(response, status_code) if status_code == 403 && @oauth_provider

            # Try to parse and handle structured JSON error
            handle_json_error_response(response, status_code)

            # Fallback: generic error
            response_body = response.respond_to?(:body) ? response.body.to_s : "Unknown error"
            raise Errors::TransportError.new(
              code: status_code,
              message: "HTTP client error: #{status_code} - #{response_body}"
            )
          end

          def handle_oauth_authorization_error(response, status_code)
            response_body = response.respond_to?(:body) ? response.body.to_s : ""
            error_body = JSON.parse(response_body)
            error_message = error_body.dig("error", "message") || "Authorization failed"

            raise Errors::TransportError.new(
              code: status_code,
              message: "Authorization failed (403 Forbidden). #{error_message}. Check token scope and permissions."
            )
          rescue JSON::ParserError
            raise Errors::TransportError.new(
              code: status_code,
              message: "Authorization failed (403 Forbidden). Check token scope and permissions."
            )
          end

          def handle_json_error_response(response, status_code)
            response_body = response.respond_to?(:body) ? response.body.to_s : "Unknown error"
            error_body = JSON.parse(response_body)

            return unless error_body.is_a?(Hash) && error_body["error"]

            error_message = error_body["error"]["message"] || error_body["error"]["code"]

            # Handle empty error messages
            if error_message.to_s.empty?
              raise Errors::TransportError.new(
                code: status_code,
                message: "Empty error (full response: #{response_body})"
              )
            end

            # Handle session-related errors
            if error_message.to_s.downcase.include?("session")
              raise Errors::TransportError.new(
                code: response.status,
                message: "Server error: #{error_message} (Current session ID: #{@session_id || 'none'})"
              )
            end

            # Generic JSON error
            raise Errors::TransportError.new(
              code: response.status,
              message: "Server error: #{error_message}"
            )
          rescue JSON::ParserError
            # Fall through to generic error in caller
            nil
          end

          def handle_session_expired
            @session_id = nil
            raise Errors::SessionExpiredError.new(
              message: "Session expired, re-initialization required"
            )
          end

          def extract_resource_metadata_url(response)
            # Extract resource metadata URL from response headers if present
            # Guard against error responses that don't have headers
            return nil unless response.respond_to?(:headers)

            metadata_url = response.headers["mcp-resource-metadata-url"]
            if metadata_url
              @resource_metadata_url = metadata_url
              RubyLLM::MCP.logger.debug("Extracted resource metadata URL: #{metadata_url}")
            end
            metadata_url ? URI(metadata_url) : nil
          end

          def handle_authentication_challenge(response, request_id, original_message)
            check_retry_guard!
            check_oauth_provider_configured!

            RubyLLM::MCP.logger.info("Received 401 Unauthorized, attempting automatic authentication")

            www_authenticate = response.headers["www-authenticate"]
            resource_metadata_url = extract_resource_metadata_url(response)

            attempt_authentication_retry(www_authenticate, resource_metadata_url, request_id, original_message)
          end

          def check_retry_guard!
            return unless @auth_retry_attempted

            RubyLLM::MCP.logger.warn("Authentication retry already attempted, raising error")
            @auth_retry_attempted = false
            raise Errors::AuthenticationRequiredError.new(
              message: "OAuth authentication required (401 Unauthorized) - retry failed"
            )
          end

          def check_oauth_provider_configured!
            return if @oauth_provider

            raise Errors::AuthenticationRequiredError.new(
              message: "OAuth authentication required (401 Unauthorized) but no OAuth provider configured"
            )
          end

          def attempt_authentication_retry(www_authenticate, resource_metadata_url, request_id, original_message)
            @auth_retry_attempted = true

            success = @oauth_provider.handle_authentication_challenge(
              www_authenticate: www_authenticate,
              resource_metadata_url: resource_metadata_url&.to_s,
              requested_scope: nil
            )

            if success
              RubyLLM::MCP.logger.info("Authentication challenge handled successfully, retrying request")
              result = send_http_request(original_message, request_id, is_initialization: false)
              @auth_retry_attempted = false
              return result
            end

            @auth_retry_attempted = false
            raise Errors::AuthenticationRequiredError.new(
              message: "OAuth authentication required (401 Unauthorized)"
            )
          rescue Errors::AuthenticationRequiredError => e
            @auth_retry_attempted = false
            raise e
          rescue StandardError => e
            @auth_retry_attempted = false
            RubyLLM::MCP.logger.error("Authentication challenge handling failed: #{e.message}")
            raise Errors::AuthenticationRequiredError.new(
              message: "OAuth authentication failed: #{e.message}"
            )
          end

          def start_sse_stream(options = StartSSEOptions.new)
            return unless @running && !@abort_controller

            @sse_mutex.synchronize do
              return if @sse_thread&.alive?

              @sse_thread = Thread.new do
                start_sse(options)
              end
            end
          end

          def start_sse(options) # rubocop:disable Metrics/MethodLength
            attempt_count = 0

            begin
              headers = build_common_headers
              headers["Accept"] = "text/event-stream"

              if options.resumption_token
                headers["Last-Event-ID"] = options.resumption_token
              end

              # Set up SSE streaming connection with callbacks
              connection = create_connection_with_sse_callbacks(options, headers)
              response = connection.get(@url)

              # Handle HTTPX error responses first
              error_result = handle_httpx_error_response!(response, context: { location: "SSE connection" },
                                                                    allow_eof_for_sse: true)
              return if error_result == :eof_handled

              case response.status
              when 200
                # SSE stream established successfully
                RubyLLM::MCP.logger.debug "SSE stream established"
                # Response will be processed through callbacks
              when 405, 401
                # Server doesn't support SSE - this is acceptable
                RubyLLM::MCP.logger.info "Server does not support SSE streaming"
                nil
              when 409
                # Conflict - SSE connection already exists for this session
                # This is expected when reusing sessions and is acceptable
                RubyLLM::MCP.logger.debug "SSE stream already exists for this session"
                nil
              else
                reason_phrase = response.respond_to?(:reason_phrase) ? response.reason_phrase : nil
                raise Errors::TransportError.new(
                  code: response.status,
                  message: "Failed to open SSE stream: #{reason_phrase || response.status}"
                )
              end
            rescue StandardError => e
              RubyLLM::MCP.logger.error "SSE stream error: #{e.message}"
              # Attempt reconnection with exponential backoff

              if @running && !@abort_controller && attempt_count < @reconnection_options.max_retries
                delay = calculate_reconnection_delay(attempt_count)
                RubyLLM::MCP.logger.info "Reconnecting SSE stream in #{delay}ms..."

                sleep(delay / 1000.0)
                attempt_count += 1
                retry
              end

              raise e
            end
          end

          def create_connection_with_sse_callbacks(options, headers)
            client = HTTPX.plugin(:callbacks)
            client = add_on_response_body_chunk_callback(client, options)

            # Use request_timeout for all timeout values (converted from ms to seconds)
            timeout_seconds = @request_timeout / 1000.0
            client = client.with(
              timeout: {
                connect_timeout: 10,
                read_timeout: timeout_seconds,
                write_timeout: timeout_seconds,
                operation_timeout: timeout_seconds
              },
              headers: headers
            )

            if @version == :http1
              client = client.with(
                ssl: { alpn_protocols: ["http/1.1"] }
              )
            end

            register_client(client)
          end

          def add_on_response_body_chunk_callback(client, options)
            buffer = +""
            client.on_response_body_chunk do |request, response, chunk|
              # Only process chunks for text/event-stream and if still running
              next unless @running && !@abort_controller

              if chunk.include?("event: stop")
                RubyLLM::MCP.logger.debug "Closing SSE stream"
                request.close
              end

              content_type = response.headers["content-type"]
              if content_type&.include?("text/event-stream")
                buffer << chunk.to_s

                while (event_data = extract_sse_event(buffer))
                  raw_event, remaining_buffer = event_data
                  buffer.replace(remaining_buffer)

                  next unless raw_event && raw_event[:data]

                  if raw_event[:id]
                    options.on_resumption_token&.call(raw_event[:id])
                  end

                  process_sse_event(raw_event, options.replay_message_id)
                end
              end
            end
          end

          def calculate_reconnection_delay(attempt)
            initial = @reconnection_options.initial_reconnection_delay
            factor = @reconnection_options.reconnection_delay_grow_factor
            max_delay = @reconnection_options.max_reconnection_delay

            [initial * (factor**attempt), max_delay].min
          end

          def process_sse_buffer_events(buffer, _request_id)
            return unless @running && !@abort_controller

            while (event_data = extract_sse_event(buffer))
              raw_event, remaining_buffer = event_data
              buffer.replace(remaining_buffer)

              process_sse_event(raw_event, nil) if raw_event && raw_event[:data]
            end
          end

          def extract_sse_event(buffer)
            # Support both Unix (\n\n) and Windows (\r\n\r\n) line endings
            separator = if buffer.include?("\r\n\r\n")
                          "\r\n\r\n"
                        elsif buffer.include?("\n\n")
                          "\n\n"
                        else
                          return nil
                        end

            raw, rest = buffer.split(separator, 2)
            [parse_sse_event(raw), rest || ""]
          end

          def parse_sse_event(raw)
            event = {}
            raw.each_line do |line|
              line = line.strip
              case line
              when /^data:\s*(.*)/
                (event[:data] ||= []) << ::Regexp.last_match(1)
              when /^event:\s*(.*)/
                event[:event] = ::Regexp.last_match(1)
              when /^id:\s*(.*)/
                event[:id] = ::Regexp.last_match(1)
              end
            end
            event[:data] = event[:data]&.join("\n")
            event
          end

          def process_sse_event(raw_event, replay_message_id)
            return unless raw_event[:data]
            return unless @running && !@abort_controller

            begin
              event_data = JSON.parse(raw_event[:data])

              # Handle replay message ID if specified
              if replay_message_id && event_data.is_a?(Hash) && event_data["id"]
                event_data["id"] = replay_message_id
              end

              result = RubyLLM::MCP::Result.new(event_data, session_id: @session_id)
              RubyLLM::MCP.logger.debug "SSE Result Received: #{result.inspect}"

              result = @coordinator.process_result(result)
              return if result.nil?

              request_id = result.id&.to_s
              if request_id
                @pending_mutex.synchronize do
                  response_queue = @pending_requests.delete(request_id)
                  response_queue&.push(result)
                end
              end
            rescue JSON::ParserError => e
              RubyLLM::MCP.logger.warn "Failed to parse SSE event data: #{raw_event[:data]} - #{e.message}"
            rescue Errors::UnknownRequest => e
              RubyLLM::MCP.logger.warn "Unknown request from MCP server: #{e.message}"
            rescue StandardError => e
              RubyLLM::MCP.logger.error "Error processing SSE event: #{e.message}"
              raise Errors::TransportError.new(
                message: "Error processing SSE event: #{e.message}",
                error: e
              )
            end
          end

          def wait_for_response_with_timeout(request_id, response_queue)
            with_timeout(@request_timeout / 1000, request_id: request_id) do
              response_queue.pop
            end
          rescue RubyLLM::MCP::Errors::TimeoutError => e
            log_message = "StreamableHTTP request timeout (ID: #{request_id}) after #{@request_timeout / 1000} seconds"
            RubyLLM::MCP.logger.error(log_message)
            @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
            raise e
          end

          def cleanup_sse_resources
            @running = false
            @abort_controller = true

            @sse_mutex.synchronize do
              if @sse_thread&.alive?
                @sse_thread.kill
                @sse_thread.join(5) # Wait up to 5 seconds for thread to finish
                @sse_thread = nil
              end
            end

            # Clear any pending requests
            @pending_mutex.synchronize do
              @pending_requests.each_value do |queue|
                queue.close if queue.respond_to?(:close)
              rescue StandardError
                # Ignore errors when closing queues
              end
              @pending_requests.clear
            end
          end

          def cleanup_connection
            clients_to_close = []

            @clients_mutex.synchronize do
              clients_to_close = @clients.dup
              @clients.clear
            end

            clients_to_close.each do |client|
              client.close if client.respond_to?(:close)
            rescue StandardError => e
              RubyLLM::MCP.logger.debug "Error closing HTTPX client: #{e.message}"
            end

            @connection = nil
          end
        end
      end
    end
  end
end
