# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Transports
        class SSE
          include Support::Timeout

          attr_reader :headers, :id, :coordinator

          def initialize(url:, coordinator:, request_timeout:, version: :http2, headers: {})
            @event_url = url
            @messages_url = nil
            @coordinator = coordinator
            @request_timeout = request_timeout
            @version = version

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

          def request(body, add_id: true, wait_for_response: true) # rubocop:disable Metrics/MethodLength
            request_id = nil

            if add_id
              @id_mutex.synchronize { @id_counter += 1 }
              request_id = @id_counter
              body["id"] = request_id
            elsif body.is_a?(Hash)
              request_id = body["id"] || body[:id]
            end

            if wait_for_response && request_id.nil?
              raise ArgumentError, "Request ID must be provided when wait_for_response is true and add_id is false"
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

            # Wait for the thread to finish
            @sse_thread&.join(1)
            @sse_thread = nil

            # Fail all pending requests
            fail_pending_requests!(
              Errors::TransportError.new(
                message: "SSE transport closed",
                code: nil
              )
            )

            # Reset state
            @messages_url = nil
          end

          def set_protocol_version(version)
            @protocol_version = version
          end

          private

          def send_request(body, request_id)
            http_client = Support::HTTPClient.connection.with(timeout: { request_timeout: @request_timeout / 1000 },
                                                              headers: @headers)
            response = http_client.post(@messages_url, body: JSON.generate(body))
            handle_httpx_error_response!(response,
                                         context: { location: "message endpoint request", request_id: request_id })

            unless [200, 202].include?(response.status)
              message = "Failed to have a successful request to #{@messages_url}: #{response.status} - #{response.body}"
              RubyLLM::MCP.logger.error(message)
              raise Errors::TransportError.new(
                message: message,
                code: response.status
              )
            end
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

              begin
                with_timeout(@request_timeout / 1000) do
                  endpoint = response_queue.pop
                  set_message_endpoint(endpoint)
                end
              rescue Errors::TimeoutError => e
                # Clean up the pending request on timeout
                @pending_mutex.synchronize do
                  @pending_requests.delete("endpoint")
                end
                RubyLLM::MCP.logger.error "Timeout waiting for endpoint event: #{e.message}"
                raise e
              rescue StandardError => e
                # Clean up the pending request on any error
                @pending_mutex.synchronize do
                  @pending_requests.delete("endpoint")
                end
                raise e
              end
            end
          end

          def set_message_endpoint(endpoint)
            # Handle both string endpoints and JSON payloads
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

            error_body = read_error_body(response)
            error_message = "HTTP #{response.status} error from SSE endpoint: #{error_body}"
            RubyLLM::MCP.logger.error error_message

            handle_client_error!(error_message, response.status) if response.status < 500

            raise StandardError, error_message
          end

          def handle_client_error!(error_message, status_code)
            transport_error = Errors::TransportError.new(
              message: error_message,
              code: status_code
            )

            # Close the transport (which will fail pending requests)
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
            # Try to read the error body from the response
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

            error_message = "#{message}: #{error.message}"
            RubyLLM::MCP.logger.error "#{error_message}. Closing SSE transport."

            # Create a transport error to fail pending requests
            transport_error = Errors::TransportError.new(
              message: error_message,
              code: nil
            )

            # Close the transport (which will fail pending requests)
            close

            # Notify coordinator if needed
            @coordinator&.handle_error(transport_error)
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
            # Return if we believe that are getting a partial event
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

            # Try to parse as JSON first, fall back to string
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
            event = begin
              JSON.parse(raw_event[:data])
            rescue JSON::ParserError => e
              # We can sometimes get partial events, so we will ignore them
              if @messages_url
                RubyLLM::MCP.logger.debug "Failed to parse SSE event data: #{raw_event[:data]} - #{e.message}"
              end
              nil
            end
            return if event.nil?

            request_id = event["id"]&.to_s
            result = RubyLLM::MCP::Result.new(event)

            result = @coordinator.process_result(result)
            return if result.nil?

            @pending_mutex.synchronize do
              # You can receive duplicate events for the same request id, and we will ignore those
              if result.matching_id?(request_id) && @pending_requests.key?(request_id)
                response_queue = @pending_requests.delete(request_id)
                response_queue&.push(result)
              end
            end
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
