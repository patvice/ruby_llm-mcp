# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Transports
        class SSE
          include Support::Timeout

          attr_reader :headers, :id, :coordinator

          def initialize(url:, coordinator:, request_timeout:, options: {})
            @event_url = url
            @messages_url = nil
            @coordinator = coordinator
            @request_timeout = request_timeout

            # Extract options
            extracted_options = options.dup
            @version = extracted_options.delete(:version) || :http2
            headers = extracted_options.delete(:headers) || {}
            oauth_provider = extracted_options.delete(:oauth_provider)

            uri = URI.parse(url)
            @root_url = "#{uri.scheme}://#{uri.host}"
            @root_url += ":#{uri.port}" if uri.port != uri.default_port

            @client_id = SecureRandom.uuid
            @headers = headers.merge({
                                       "Accept" => "text/event-stream",
                                       "Content-Type" => "application/json",
                                       "Cache-Control" => "no-cache",
                                       "X-CLIENT-ID" => @client_id
                                     })

            @oauth_provider = oauth_provider
            @resource_metadata_url = nil
            @auth_retry_attempted = false

            @id_counter = 0
            @id_mutex = Mutex.new
            @pending_requests = {}
            @pending_mutex = Mutex.new
            @connection_mutex = Mutex.new
            @state_mutex = Mutex.new
            @running = false
            @sse_thread = nil
            @sse_response = nil

            RubyLLM::MCP.logger.info "Initializing SSE transport to #{@event_url} with client ID #{@client_id}"
          end

          def request(body, wait_for_response: true) # rubocop:disable Metrics/MethodLength
            request_id = body.is_a?(Hash) ? (body["id"] || body[:id]) : nil

            if wait_for_response && request_id.nil?
              raise ArgumentError, "Request ID must be provided in message body when wait_for_response is true"
            end

            response_queue = nil
            if wait_for_response
              response_queue = Queue.new
              @pending_mutex.synchronize do
                @pending_requests[request_id.to_s] = response_queue
              end
            end

            begin
              send_request(body, request_id)
            rescue Errors::TransportError, Errors::TimeoutError => e
              if wait_for_response && request_id
                @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
              end
              RubyLLM::MCP.logger.error "Request error (ID: #{request_id}): #{e.message}"
              raise e
            end

            return unless wait_for_response

            result = nil
            begin
              result = with_timeout(@request_timeout / 1000, request_id: request_id) do
                response_queue.pop
              end
            rescue Errors::TimeoutError => e
              if request_id
                @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
              end
              RubyLLM::MCP.logger.error "SSE request timeout (ID: #{request_id}) \
                after #{@request_timeout / 1000} seconds."
              raise e
            end

            raise result if result.is_a?(Errors::TransportError)

            result
          end

          def alive?
            running?
          end

          def running?
            @state_mutex.synchronize { @running }
          end

          def start
            @state_mutex.synchronize do
              return if @running

              @running = true
            end

            start_sse_listener
          end

          def close
            should_close = @state_mutex.synchronize do
              return unless @running

              @running = false
              true
            end

            return unless should_close

            RubyLLM::MCP.logger.info "Closing SSE transport connection"

            # Close the SSE response stream if it exists
            begin
              @sse_response&.body&.close
            rescue StandardError => e
              RubyLLM::MCP.logger.debug "Error closing SSE response: #{e.message}"
            end

            # Wait for the thread to finish (but don't join from within itself)
            if @sse_thread && Thread.current != @sse_thread
              @sse_thread.join(1)
            end
            @sse_thread = nil

            fail_pending_requests!(
              Errors::TransportError.new(
                message: "SSE transport closed",
                code: nil
              )
            )

            @messages_url = nil
          end

          def set_protocol_version(version)
            @protocol_version = version
          end

          private

          def send_request(body, request_id)
            headers = build_request_headers
            http_client = Support::HTTPClient.connection.with(timeout: { request_timeout: @request_timeout / 1000 },
                                                              headers: headers)
            response = http_client.post(@messages_url, body: JSON.generate(body))
            handle_httpx_error_response!(response,
                                         context: { location: "message endpoint request", request_id: request_id })

            case response.status
            when 200, 202
              # Success
              nil
            when 401
              handle_authentication_challenge(response, body, request_id)
            else
              message = "Failed to have a successful request to #{@messages_url}: #{response.status} - #{response.body}"
              RubyLLM::MCP.logger.error(message)
              raise Errors::TransportError.new(
                message: message,
                code: response.status
              )
            end
          end

          def build_request_headers
            headers = @headers.dup

            # Apply OAuth authorization if available
            if @oauth_provider
              RubyLLM::MCP.logger.debug "OAuth provider present, attempting to get token..."
              token = @oauth_provider.access_token
              if token
                headers["Authorization"] = token.to_header
                RubyLLM::MCP.logger.debug "Applied OAuth authorization header"
              else
                RubyLLM::MCP.logger.warn "OAuth provider present but no valid token available!"
              end
            end

            headers
          end

          def handle_authentication_challenge(response, original_body, request_id)
            check_retry_guard!
            check_oauth_provider_configured!

            RubyLLM::MCP.logger.info("Received 401 Unauthorized, attempting automatic authentication")

            www_authenticate = response.headers["www-authenticate"]
            resource_metadata_url = response.headers["mcp-resource-metadata-url"]
            @resource_metadata_url = resource_metadata_url if resource_metadata_url

            attempt_authentication_retry(www_authenticate, resource_metadata_url, original_body, request_id)
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

          def attempt_authentication_retry(www_authenticate, resource_metadata_url, original_body, request_id)
            @auth_retry_attempted = true

            success = @oauth_provider.handle_authentication_challenge(
              www_authenticate: www_authenticate,
              resource_metadata_url: resource_metadata_url,
              requested_scope: nil
            )

            if success
              RubyLLM::MCP.logger.info("Authentication challenge handled successfully, retrying request")
              send_request(original_body, request_id)
              @auth_retry_attempted = false
              return
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

          def start_sse_listener
            @connection_mutex.synchronize do # rubocop:disable Metrics/BlockLength
              return if sse_thread_running?

              RubyLLM::MCP.logger.info "Starting SSE listener thread"

              response_queue = Queue.new
              @pending_mutex.synchronize do
                @pending_requests["endpoint"] = response_queue
              end

              @sse_thread = Thread.new do
                listen_for_events
              end
              @sse_thread.abort_on_exception = true

              begin
                with_timeout(@request_timeout / 1000) do
                  endpoint = response_queue.pop
                  raise endpoint if endpoint.is_a?(StandardError)

                  set_message_endpoint(endpoint)
                end
              rescue Errors::TimeoutError => e
                @pending_mutex.synchronize do
                  @pending_requests.delete("endpoint")
                end
                RubyLLM::MCP.logger.error "Timeout waiting for endpoint event: #{e.message}"
                raise e
              rescue StandardError => e
                @pending_mutex.synchronize do
                  @pending_requests.delete("endpoint")
                end
                raise e
              end
            end
          end

          def set_message_endpoint(endpoint)
            endpoint_url = if endpoint.is_a?(String)
                             endpoint
                           elsif endpoint.is_a?(Hash)
                             # Support richer endpoint metadata (e.g., { "url": "...", "last_event_id": "..." })
                             endpoint["url"] || endpoint[:url]
                           else
                             endpoint.to_s
                           end

            unless endpoint_url && !endpoint_url.empty?
              raise Errors::TransportError.new(
                message: "Invalid endpoint event: missing URL",
                code: nil
              )
            end

            uri = URI.parse(endpoint_url)

            @messages_url = if uri.host.nil?
                              "#{@root_url}#{endpoint_url}"
                            else
                              endpoint_url
                            end

            RubyLLM::MCP.logger.info "SSE message endpoint set to: #{@messages_url}"
          rescue URI::InvalidURIError => e
            raise Errors::TransportError.new(
              message: "Invalid endpoint URL: #{e.message}",
              code: nil
            )
          end

          def sse_thread_running?
            @sse_thread&.alive?
          end

          def listen_for_events
            stream_events_from_server while running?
          rescue StandardError => e
            handle_connection_error("SSE connection error", e)
          end

          def stream_events_from_server
            sse_client = create_sse_client
            @sse_response = sse_client.get(@event_url, stream: true)
            validate_sse_response!(@sse_response)
            process_event_stream(@sse_response)
          end

          def create_sse_client
            sse_client = HTTPX.plugin(:stream).with(headers: @headers)
            return sse_client unless @version == :http1

            sse_client.with(ssl: { alpn_protocols: ["http/1.1"] })
          end

          def validate_sse_response!(response)
            return unless response.status >= 400

            # Handle 401 specially for OAuth
            if response.status == 401
              handle_sse_authentication_challenge(response)
              return
            end

            error_body = read_error_body(response)
            error_message = "HTTP #{response.status} error from SSE endpoint: #{error_body}"
            RubyLLM::MCP.logger.error error_message

            handle_client_error!(error_message, response.status) if response.status < 500

            raise StandardError, error_message
          end

          def handle_sse_authentication_challenge(response)
            unless @oauth_provider
              raise Errors::AuthenticationRequiredError.new(
                message: "OAuth authentication required for SSE stream but no OAuth provider configured"
              )
            end

            RubyLLM::MCP.logger.info("SSE stream received 401, attempting authentication")

            www_authenticate = response.headers["www-authenticate"]
            resource_metadata_url = response.headers["mcp-resource-metadata-url"]

            begin
              success = @oauth_provider.handle_authentication_challenge(
                www_authenticate: www_authenticate,
                resource_metadata_url: resource_metadata_url,
                requested_scope: nil
              )

              if success
                RubyLLM::MCP.logger.info("Authentication successful, SSE stream will reconnect")
                # The caller will retry the SSE connection
                return
              end
            rescue Errors::AuthenticationRequiredError
              raise
            rescue StandardError => e
              RubyLLM::MCP.logger.error("SSE authentication failed: #{e.message}")
            end

            raise Errors::AuthenticationRequiredError.new(
              message: "OAuth authentication required for SSE stream"
            )
          end

          def handle_client_error!(error_message, status_code)
            transport_error = Errors::TransportError.new(
              message: error_message,
              code: status_code
            )
            close

            raise transport_error
          end

          def fail_pending_requests!(error)
            @pending_mutex.synchronize do
              @pending_requests.each_value do |queue|
                queue.push(error)
              end
              @pending_requests.clear
            end
          end

          def process_event_stream(response)
            event_buffer = []
            response.each_line do |event_line|
              break unless handle_event_line?(event_line, event_buffer, response)
            end
          end

          def handle_event_line?(event_line, event_buffer, response)
            unless running?
              response.body.close
              return false
            end

            line = event_line.strip

            if line.empty?
              process_buffered_event(event_buffer)
            else
              event_buffer << line
            end

            true
          end

          def process_buffered_event(event_buffer)
            return unless event_buffer.any?

            events = parse_event(event_buffer.join("\n"))
            events.each { |event| process_event(event) }
            event_buffer.clear
          end

          def read_error_body(response)
            body = ""
            begin
              response.each do |chunk|
                body << chunk
              end
            rescue StandardError
              # If we can't read the body, just use what we have
            end
            body.strip.empty? ? "No error details provided" : body.strip
          end

          def handle_connection_error(message, error)
            return unless running?
            # Ignore errors from a previous listener thread after restart.
            return if Thread.current != @sse_thread

            error_message = "#{message}: #{error.message}"
            RubyLLM::MCP.logger.error "#{error_message}. Closing SSE transport."

            close
          end

          def handle_httpx_error_response!(response, context:)
            return false unless response.is_a?(HTTPX::ErrorResponse)

            error = response.error

            if error.is_a?(HTTPX::ReadTimeoutError)
              raise Errors::TimeoutError.new(
                message: "Request timed out after #{@request_timeout / 1000} seconds"
              )
            end

            error_message = response.error&.message || "Request failed"

            raise Errors::TransportError.new(
              code: nil,
              message: "Request Error #{context}: #{error_message}"
            )
          end

          def process_event(raw_event)
            return if raw_event[:data].nil?

            if raw_event[:event] == "endpoint"
              process_endpoint_event(raw_event)
            else
              process_message_event(raw_event)
            end
          end

          def process_endpoint_event(raw_event)
            request_id = "endpoint"
            event_data = raw_event[:data]
            return if event_data.nil?

            endpoint = begin
              JSON.parse(event_data)
            rescue JSON::ParserError
              event_data
            end

            RubyLLM::MCP.logger.debug "Received endpoint event: #{endpoint.inspect}"

            @pending_mutex.synchronize do
              response_queue = @pending_requests.delete(request_id)
              response_queue&.push(endpoint)
            end
          end

          def process_message_event(raw_event)
            event = parse_and_validate_event(raw_event[:data])
            return if event.nil?

            request_id = event["id"]&.to_s
            result = RubyLLM::MCP::Result.new(event)

            result = @coordinator.process_result(result)
            return if result.nil?

            return if request_id.nil?

            response_queue = nil
            matching_result = false

            @pending_mutex.synchronize do
              if @pending_requests.key?(request_id)
                matching_result = if result.is_a?(RubyLLM::MCP::Result)
                                    result.matching_id?(request_id)
                                  else
                                    true
                                  end

                response_queue = @pending_requests.delete(request_id) if matching_result
              else
                matching_result = false
              end
            end

            response_queue&.push(result) if matching_result
          end

          def parse_and_validate_event(data)
            event = JSON.parse(data)

            # Validate JSON-RPC envelope
            validator = Native::JsonRpc::EnvelopeValidator.new(event)
            unless validator.valid?
              RubyLLM::MCP.logger.error(
                "Invalid JSON-RPC envelope in SSE event: #{validator.error_message}\nRaw: #{data}"
              )
              # SSE is unidirectional from server to client, so we can't send error responses back
              return nil
            end

            event
          rescue JSON::ParserError => e
            # Partial endpoint events can arrive while establishing the stream; log once we know the URL.
            if @messages_url
              RubyLLM::MCP.logger.debug "Failed to parse SSE event data: #{data} - #{e.message}"
            end
            nil
          end

          def parse_event(raw)
            event_blocks = raw.split(/\n\s*\n/)

            events = event_blocks.map do |event_block|
              event = {}
              event_block.each_line do |line|
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

            events.reject { |event| event.empty? || event[:data].nil? }
          end
        end
      end
    end
  end
end
