# frozen_string_literal: true

require "json"
require "uri"
require "faraday"
require "timeout"
require "securerandom"

module RubyLLM
  module MCP
    module Transport
      class Streamable
        attr_reader :headers, :id, :session_id, :coordinator

        def initialize(url, request_timeout:, coordinator:, headers: {})
          @url = url
          @coordinator = coordinator
          @request_timeout = request_timeout
          @client_id = SecureRandom.uuid
          @session_id = nil
          @protocol_version = nil # Will be set after initialization
          @base_headers = headers.merge({
                                          "Content-Type" => "application/json",
                                          "Accept" => "application/json, text/event-stream",
                                          "Connection" => "keep-alive",
                                          "X-CLIENT-ID" => @client_id
                                        })

          @id_counter = 0
          @id_mutex = Mutex.new
          @pending_requests = {}
          @pending_mutex = Mutex.new
          @running = true
          @last_event_ids = {}

          # Initialize HTTP connection
          @connection = create_connection
        end

        def request(body, add_id: true, wait_for_response: true)
          # Generate a unique request ID for requests
          if add_id && body.is_a?(Hash) && !body.key?("id")
            @id_mutex.synchronize { @id_counter += 1 }
            body["id"] = @id_counter
          end

          request_id = body.is_a?(Hash) ? body["id"] : nil
          is_initialization = body.is_a?(Hash) && body["method"] == "initialize"

          # Create a queue for this request's response if needed
          response_queue = setup_response_queue(request_id, wait_for_response)

          # Send the HTTP request
          response = send_http_request(body, request_id, is_initialization: is_initialization)

          # Handle different response types based on content
          handle_response(response, request_id, response_queue, wait_for_response)
        end

        def alive?
          @running
        end

        def close
          @running = false
          @connection&.close if @connection.respond_to?(:close)
          @connection = nil
        end

        # Set the negotiated protocol version after initialization
        def set_protocol_version(version)
          @protocol_version = version
        end

        private

        def create_connection
          Faraday.new(url: @url) do |f|
            f.options.timeout = @request_timeout / 1000
            f.options.open_timeout = 10
          end
        end

        def build_headers
          headers = @base_headers.dup
          headers["Mcp-Session-Id"] = @session_id if @session_id
          # Add MCP-Protocol-Version header for all subsequent requests after initialization
          headers["MCP-Protocol-Version"] = @protocol_version if @protocol_version
          headers
        end

        def build_initialization_headers
          # Initialization request should not include MCP-Protocol-Version header
          @base_headers.dup
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
          headers = is_initialization ? build_initialization_headers : build_headers
          is_ping = body.is_a?(Hash) && body[:method] == "ping"

          # For requests that might return streaming responses, we need to handle streaming
          @connection.post do |req|
            headers.each { |key, value| req.headers[key] = value }
            req.body = JSON.generate(body)

            # Set up streaming callback only for requests that might return streaming responses
            # Skip for initialization, ping, and other simple request/response operations
            unless is_initialization || is_ping
              setup_post_streaming_callback(req, request_id)
            end
          end
        rescue StandardError => e
          @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) } if request_id
          raise RubyLLM::MCP::Errors::TransportError.new(message: e.message)
        end

        def setup_post_streaming_callback(request, request_id)
          buffer = +""
          request.options.on_data = proc do |chunk, _size, env|
            # Only process streaming data if the response is SSE
            if env[:response_headers]["content-type"]&.include?("text/event-stream")
              buffer << chunk

              # Get the response queue from pending requests
              response_queue = nil
              @pending_mutex.synchronize do
                response_queue = @pending_requests[request_id.to_s]
              end

              process_sse_buffer_events(buffer, request_id.to_s, response_queue)
            end
          end
        end

        def handle_response(response, request_id, response_queue, wait_for_response)
          case response.status
          when 200
            handle_200_response(response, request_id, response_queue, wait_for_response)
          when 202
            # Accepted - for notifications/responses only, no body expected
            nil
          when 400..499
            handle_client_error(response)
          when 404
            handle_session_expired
          else
            raise "HTTP request failed: #{response.status} - #{response.body}"
          end
        rescue StandardError => e
          @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) } if request_id
          raise e
        end

        def handle_200_response(response, request_id, response_queue, wait_for_response)
          content_type = response.headers["content-type"]

          if content_type&.include?("text/event-stream")
            handle_sse_response(response, request_id, response_queue, wait_for_response)
          elsif content_type&.include?("application/json")
            handle_json_response(response, request_id, response_queue, wait_for_response)
          else
            raise "Unexpected content type: #{content_type}"
          end
        end

        def handle_sse_response(response, request_id, response_queue, wait_for_response)
          # Extract session ID from initial response if present
          extract_session_id(response)

          # For POST responses that are streaming, the streaming is handled in the callback
          # We just need to wait for the response if requested
          if wait_for_response && request_id
            wait_for_response_with_timeout(request_id.to_s, response_queue)
          end
        end

        def handle_json_response(response, request_id, response_queue, wait_for_response)
          # Extract session ID from response if present
          extract_session_id(response)

          begin
            json_response = JSON.parse(response.body)
            result = RubyLLM::MCP::Result.new(json_response)

            if wait_for_response && request_id && response_queue
              @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
            end

            result
          rescue JSON::ParserError => e
            raise "Invalid JSON response: #{e.message}"
          end
        end

        def extract_session_id(response)
          session_id = response.headers["Mcp-Session-Id"]
          @session_id = session_id if session_id
        end

        def handle_client_error(response)
          begin
            error_body = JSON.parse(response.body)
            if error_body.is_a?(Hash) && error_body["error"]
              error_message = error_body["error"]["message"] || error_body["error"]["code"]

              if error_message.to_s.downcase.include?("session")
                raise "Server error: #{error_message} (Current session ID: #{@session_id || 'none'})"
              end

              raise "Server error: #{error_message}"
            end
          rescue JSON::ParserError
            # Fall through to generic error
          end

          raise "HTTP client error: #{response.status} - #{response.body}"
        end

        def handle_session_expired
          @session_id = nil
          raise RubyLLM::MCP::Errors::SessionExpiredError.new(
            message: "Session expired, re-initialization required"
          )
        end

        def process_sse_buffer_events(buffer, request_id, response_queue)
          while (event = extract_sse_event(buffer))
            event_data, remaining_buffer = event
            buffer.replace(remaining_buffer)
            process_sse_event_data(event_data, request_id, response_queue) if event_data
          end
        end

        def extract_sse_event(buffer)
          return nil unless buffer.include?("\n\n")

          raw, rest = buffer.split("\n\n", 2)
          [parse_sse_event(raw), rest]
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

        def process_sse_event_data(raw_event, request_id, response_queue)
          return if raw_event[:data].nil?

          begin
            event_data = JSON.parse(raw_event[:data])
            result = RubyLLM::MCP::Result.new(event_data)

            # Store event ID for resumability
            if raw_event[:id]
              @last_event_ids[request_id] = raw_event[:id]
            end

            # Handle notifications (always process regardless of request matching)
            if result.notification?
              coordinator.process_notification(result)
              return
            end

            # Handle ping responses
            if result.ping?
              coordinator.ping_response(id: result.id)
              return
            end

            # Handle responses matching our request (for request streams)
            if response_queue && result.matching_id?(request_id)
              response_queue.push(result)
              # Clean up the request from pending_requests once we get the final response
              @pending_mutex.synchronize { @pending_requests.delete(request_id) }
            elsif result.request?
              # Server-initiated request during stream
              coordinator.process_request(result)
            end
          rescue JSON::ParserError => e
            RubyLLM::MCP.logger.warn "Warning: Failed to parse SSE event data: #{raw_event[:data]} - #{e.message}"
          end
        end

        def wait_for_response_with_timeout(request_id, response_queue)
          Timeout.timeout(@request_timeout / 1000) do
            result = response_queue.pop
            # Request cleanup is handled in process_sse_event_data when we get the response
            result
          end
        rescue Timeout::Error
          @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
          raise RubyLLM::MCP::Errors::TimeoutError.new(
            message: "Request timed out after #{@request_timeout / 1000} seconds",
            request_id: request_id
          )
        end
      end
    end
  end
end
