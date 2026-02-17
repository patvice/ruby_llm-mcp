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
          attr_accessor :resumption_token
          attr_reader :on_resumption_token, :replay_message_id

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

          def initialize( # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
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
            sse_timeout: nil,
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
            sse_timeout = extracted_options.delete(:sse_timeout) || sse_timeout

            @url = URI(url)
            @coordinator = coordinator
            @request_timeout = request_timeout
            @sse_timeout = sse_timeout
            @headers = headers || {}
            @session_id = session_id
            @sse_fallback_supported = true

            @version = version
            @protocol_version = nil

            @client_id = SecureRandom.uuid

            # Reconnection options precedence: explicit > hash > defaults
            @reconnection_options = if reconnection_options
                                      reconnection_options
                                    elsif reconnection && !reconnection.empty?
                                      ReconnectionOptions.new(**reconnection)
                                    else
                                      ReconnectionOptions.new
                                    end

            @oauth_provider = oauth_provider
            @rate_limiter = Support::RateLimiter.new(**rate_limit) if rate_limit

            @id_counter = 0
            @id_mutex = Mutex.new
            @pending_requests = {}
            @pending_mutex = Mutex.new
            @running = true
            @sse_stopped = false
            @state_mutex = Mutex.new
            @sse_thread = nil
            @sse_mutex = Mutex.new
            @last_sse_event_id = nil

            # Track if we've attempted auth flow to prevent infinite loops
            @auth_retry_attempted = false

            # Thread-safe collection of all HTTPX clients
            @clients = []
            @clients_mutex = Mutex.new

            @connection = create_connection
          end

          def request(body, wait_for_response: true)
            if @rate_limiter&.exceeded?
              sleep(1) while @rate_limiter&.exceeded?
            end
            @rate_limiter&.add

            # Extract the request ID from the body (if present)
            request_id = body.is_a?(Hash) ? (body["id"] || body[:id]) : nil
            is_initialization = body.is_a?(Hash) && (body["method"] == "initialize" || body[:method] == :initialize)

            response_queue = setup_response_queue(request_id, wait_for_response)
            result = send_http_request(body, request_id, is_initialization: is_initialization)
            return result if result.is_a?(RubyLLM::MCP::Result)

            if wait_for_response && request_id
              wait_for_response_with_timeout(request_id.to_s, response_queue)
            end
          end

          def alive?
            running?
          end

          def close
            terminate_session
            cleanup_sse_resources
            cleanup_connection
          end

          def start
            @state_mutex.synchronize do
              @sse_stopped = false
            end
          end

          def set_protocol_version(version)
            @protocol_version = version
          end

          def on_message(&block)
            @on_message_callback = block
          end

          def on_error(&block)
            @on_error_callback = block
          end

          def on_close(&block)
            @on_close_callback = block
          end

          private

          def running?
            @state_mutex.synchronize { @running && !@sse_stopped }
          end

          def abort!
            @state_mutex.synchronize do
              @running = false
              @sse_stopped = true
            end
          end

          def terminate_session
            return unless @session_id

            begin
              headers = build_common_headers
              response = @connection.delete(@url, headers: headers)

              handle_httpx_error_response!(response, context: { location: "terminating session" })

              unless [200, 204, 404, 405].include?(response.status)
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
            client = client.on_response_body_chunk do |request, _response, chunk|
              next unless running?

              RubyLLM::MCP.logger.debug "Received chunk: #{chunk.bytesize} bytes for #{request.uri}"
              buffer << chunk
              process_sse_buffer_events(buffer, request_id&.to_s)
            end
            client = client.with(
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
            handle_httpx_error_response!(response, context: { location: "handling response", request_id: request_id })

            session_id = response.headers["mcp-session-id"]
            @session_id = session_id if session_id

            case response.status
            when 200, 201
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
              start_sse_stream if sse_fallback_available?
              nil
            elsif content_type&.include?("application/json")
              response_body = response.respond_to?(:body) ? response.body.to_s : "{}"
              if response_body == "null" # Fix related to official MCP Ruby SDK implementation
                response_body = "{}"
              end

              json_response = parse_and_validate_http_response(response_body)
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
            if original_message.is_a?(Hash) && original_message["method"] == "initialize" && sse_fallback_available?
              start_sse_stream
            end
            nil
          end

          def handle_client_error(response)
            status_code = response.respond_to?(:status) ? response.status : "Unknown"

            handle_oauth_authorization_error(response, status_code) if status_code == 403 && @oauth_provider

            handle_json_error_response(response, status_code)

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

            if error_message.to_s.empty?
              raise Errors::TransportError.new(
                code: status_code,
                message: "Empty error (full response: #{response_body})"
              )
            end

            if error_message.to_s.downcase.include?("session")
              raise Errors::TransportError.new(
                code: response.status,
                message: "Server error: #{error_message} (Current session ID: #{@session_id || 'none'})"
              )
            end

            raise Errors::TransportError.new(
              code: response.status,
              message: "Server error: #{error_message}"
            )
          rescue JSON::ParserError
            nil
          end

          def handle_session_expired
            @session_id = nil
            raise Errors::SessionExpiredError.new(
              message: "Session expired, re-initialization required"
            )
          end

          def extract_resource_metadata_url(response)
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
            return unless running?
            return unless sse_fallback_available?

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

              connection = create_connection_with_sse_callbacks(options, headers)
              response = connection.get(@url)

              error_result = handle_httpx_error_response!(response, context: { location: "SSE connection" },
                                                                    allow_eof_for_sse: true)
              return if error_result == :eof_handled

              case response.status
              when 200
                RubyLLM::MCP.logger.debug "SSE stream established"
              when 405
                RubyLLM::MCP.logger.info "Server does not support SSE streaming"
                disable_sse_fallback!
                nil
              when 401
                RubyLLM::MCP.logger.info "SSE stream unauthorized (401); keeping fallback enabled"
                nil
              when 409
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
              if running? && attempt_count < @reconnection_options.max_retries
                delay = calculate_reconnection_delay(attempt_count)
                RubyLLM::MCP.logger.info "Reconnecting SSE stream in #{delay}ms..."

                sleep(delay / 1000.0)
                attempt_count += 1

                # Create new options with the last event ID for resumption
                options = StartSSEOptions.new(
                  resumption_token: @last_sse_event_id,
                  on_resumption_token: options.on_resumption_token,
                  replay_message_id: options.replay_message_id
                )

                retry
              end

              raise e
            end
          end

          def disable_sse_fallback!
            @state_mutex.synchronize do
              @sse_fallback_supported = false
            end
          end

          def sse_fallback_available?
            @state_mutex.synchronize do
              @sse_fallback_supported
            end
          end

          def create_connection_with_sse_callbacks(options, headers)
            client = HTTPX.plugin(:callbacks)
            client = add_on_response_body_chunk_callback(client, options)

            sse_timeout_seconds = if @sse_timeout
                                    @sse_timeout / 1000.0
                                  else
                                    # Default to 1 hour for SSE if not specified
                                    3600
                                  end

            client = client.with(
              timeout: {
                connect_timeout: 10,
                read_timeout: sse_timeout_seconds,
                write_timeout: sse_timeout_seconds,
                operation_timeout: sse_timeout_seconds
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
              next unless running?

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
                    @last_sse_event_id = raw_event[:id]
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

          def process_sse_buffer_events(buffer, request_id)
            return unless running?

            while (event_data = extract_sse_event(buffer))
              raw_event, remaining_buffer = event_data
              buffer.replace(remaining_buffer)

              if raw_event && raw_event[:data]
                RubyLLM::MCP.logger.debug "Processing SSE buffer event for request #{request_id}" if request_id
                process_sse_event(raw_event, nil)
              end
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

          def process_sse_event(raw_event, replay_message_id) # rubocop:disable Metrics/MethodLength
            return unless raw_event[:data]
            return unless running?

            event_data = nil
            begin
              event_data = parse_and_validate_sse_event(raw_event[:data])
              return unless event_data

              event_type = raw_event[:event] || "message"
              event_id = raw_event[:id]
              RubyLLM::MCP.logger.debug "Processing SSE event: type=#{event_type}, id=#{event_id || 'none'}"

              if replay_message_id && event_data.is_a?(Hash) && event_data["id"]
                event_data["id"] = replay_message_id
              end

              result = RubyLLM::MCP::Result.new(event_data, session_id: @session_id)
              RubyLLM::MCP.logger.debug "SSE Result Received: #{result.inspect}"

              @on_message_callback&.call(result)

              result = @coordinator.process_result(result)
              return if result.nil?

              request_id = result.id&.to_s
              if request_id
                @pending_mutex.synchronize do
                  response_queue = @pending_requests.delete(request_id)
                  if response_queue
                    RubyLLM::MCP.logger.debug "Matched SSE event to pending request: #{request_id}"
                    response_queue.push(result)
                  else
                    RubyLLM::MCP.logger.debug "No pending request found for SSE event: #{request_id}"
                  end
                end
              end
            rescue JSON::ParserError => e
              RubyLLM::MCP.logger.warn "Failed to parse SSE event data: #{raw_event[:data]} - #{e.message}"
              @on_error_callback&.call(e)
            rescue Errors::UnknownRequest => e
              RubyLLM::MCP.logger.warn "Unknown request from MCP server: #{e.message}"
              @on_error_callback&.call(e)
            rescue StandardError => e
              RubyLLM::MCP.logger.error "Error processing SSE event: #{e.message}"
              @on_error_callback&.call(e)

              request_id = event_data.is_a?(Hash) ? event_data["id"]&.to_s : nil
              if request_id
                transport_error = Errors::TransportError.new(
                  message: "Error processing SSE event: #{e.message}",
                  error: e
                )
                @pending_mutex.synchronize do
                  response_queue = @pending_requests.delete(request_id)
                  response_queue&.push(transport_error)
                end
              end
            end
          end

          def parse_and_validate_sse_event(data)
            event_data = JSON.parse(data)

            # Validate JSON-RPC envelope
            validator = Native::JsonRpc::EnvelopeValidator.new(event_data)
            unless validator.valid?
              RubyLLM::MCP.logger.error(
                "Invalid JSON-RPC envelope in SSE event: #{validator.error_message}\nRaw: #{data}"
              )
              return nil
            end

            event_data
          end

          def parse_and_validate_http_response(response_body)
            json_response = JSON.parse(response_body)

            # Validate JSON-RPC envelope
            validator = Native::JsonRpc::EnvelopeValidator.new(json_response)
            unless validator.valid?
              error_msg = "Invalid JSON-RPC envelope: #{validator.error_message}"
              RubyLLM::MCP.logger.error("#{error_msg}\nRaw: #{response_body}")
              raise Errors::TransportError.new(
                message: error_msg,
                code: Native::JsonRpc::ErrorCodes::INVALID_REQUEST
              )
            end

            json_response
          rescue JSON::ParserError => e
            error_msg = "JSON parse error: #{e.message}"
            RubyLLM::MCP.logger.error("#{error_msg}\nRaw: #{response_body}")
            raise Errors::TransportError.new(
              message: error_msg,
              code: Native::JsonRpc::ErrorCodes::PARSE_ERROR,
              error: e
            )
          end

          def wait_for_response_with_timeout(request_id, response_queue)
            result = with_timeout(@request_timeout / 1000, request_id: request_id) do
              response_queue.pop
            end

            # Check if we received a shutdown error sentinel
            if result.is_a?(Errors::TransportError)
              raise result
            end

            result
          rescue RubyLLM::MCP::Errors::TimeoutError => e
            log_message = "StreamableHTTP request timeout (ID: #{request_id}) after #{@request_timeout / 1000} seconds"
            RubyLLM::MCP.logger.error(log_message)
            @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
            raise e
          end

          def cleanup_sse_resources
            abort!

            # Call on_close hook if registered
            @on_close_callback&.call

            # Close all HTTPX clients to signal SSE thread to exit
            close_all_clients

            @sse_mutex.synchronize do
              if @sse_thread&.alive?
                unless @sse_thread.join(5)
                  RubyLLM::MCP.logger.warn "SSE thread did not exit cleanly, forcing termination"
                  @sse_thread.kill
                  @sse_thread.join(1)
                end
                @sse_thread = nil
              end
            end

            drain_pending_requests_with_error
          end

          def close_all_clients
            clients_to_close = []

            @clients_mutex.synchronize do
              clients_to_close = @clients.dup
            end

            clients_to_close.each do |client|
              client.close if client.respond_to?(:close)
            rescue StandardError => e
              RubyLLM::MCP.logger.debug "Error closing HTTPX client: #{e.message}"
            end
          end

          def cleanup_connection
            close_all_clients

            @clients_mutex.synchronize do
              @clients.clear
            end

            @connection = nil
          end

          def drain_pending_requests_with_error
            shutdown_error = Errors::TransportError.new(
              message: "Transport is shutting down",
              code: nil
            )

            @pending_mutex.synchronize do
              @pending_requests.each_value do |queue|
                queue.push(shutdown_error)
              rescue StandardError => e
                RubyLLM::MCP.logger.debug "Error pushing shutdown error to queue: #{e.message}"
              end
              @pending_requests.clear
            end
          end
        end
      end
    end
  end
end
