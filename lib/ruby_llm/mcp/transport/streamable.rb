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
        attr_reader :headers, :id, :session_id

        def initialize(url, headers: {})
          @url = url
          @client_id = SecureRandom.uuid
          @session_id = nil
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
          @sse_streams = {}
          @sse_mutex = Mutex.new

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

        def close
          @running = false
          @sse_mutex.synchronize do
            @sse_streams.each_value(&:close)
            @sse_streams.clear
          end
          @connection&.close if @connection.respond_to?(:close)
          @connection = nil
        end

        def terminate_session
          return unless @session_id

          begin
            response = @connection.delete do |req|
              build_headers.each { |key, value| req.headers[key] = value }
            end
            @session_id = nil if response.status == 200
          rescue StandardError => e
            # Server may not support session termination (405), which is allowed
            puts "Warning: Failed to terminate session: #{e.message}"
          end
        end

        private

        def create_connection
          Faraday.new(url: @url) do |f|
            f.options.timeout = 300
            f.options.open_timeout = 10
          end
        end

        def build_headers
          headers = @base_headers.dup
          headers["Mcp-Session-Id"] = @session_id if @session_id
          headers
        end

        def build_initialization_headers
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
          @connection.post do |req|
            headers = is_initialization ? build_initialization_headers : build_headers
            headers.each { |key, value| req.headers[key] = value }
            req.body = JSON.generate(body)
          end
        rescue StandardError => e
          @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) } if request_id
          raise e
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

          if wait_for_response && request_id
            # Process SSE stream for this specific request
            process_sse_for_request(response.body, request_id.to_s, response_queue)
            # Wait for the response with timeout
            wait_for_response_with_timeout(request_id.to_s, response_queue)
          else
            # Process general SSE stream
            process_sse_stream(response.body)
            nil
          end
        end

        def handle_json_response(response, request_id, response_queue, wait_for_response)
          # Extract session ID from response if present
          extract_session_id(response)

          begin
            json_response = JSON.parse(response.body)

            if wait_for_response && request_id && response_queue
              @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
              return json_response
            end

            json_response
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

        def process_sse_for_request(sse_body, request_id, response_queue)
          Thread.new do
            process_sse_events(sse_body) do |event_data|
              if event_data.is_a?(Hash) && event_data["id"]&.to_s == request_id
                response_queue.push(event_data)
                @pending_mutex.synchronize { @pending_requests.delete(request_id) }
                break # Found our response, stop processing
              end
            end
          rescue StandardError => e
            puts "Error processing SSE stream: #{e.message}"
            response_queue.push({ "error" => { "message" => e.message } })
          end
        end

        def process_sse_stream(sse_body)
          Thread.new do
            process_sse_events(sse_body) do |event_data|
              # Handle server-initiated requests/notifications
              handle_server_message(event_data) if event_data.is_a?(Hash)
            end
          rescue StandardError => e
            puts "Error processing SSE stream: #{e.message}"
          end
        end

        def process_sse_events(sse_body)
          event_buffer = ""
          event_id = nil

          sse_body.each_line do |line|
            line = line.strip

            if line.empty?
              # End of event, process accumulated data
              unless event_buffer.empty?
                begin
                  event_data = JSON.parse(event_buffer)
                  yield event_data
                rescue JSON::ParserError
                  puts "Warning: Failed to parse SSE event data: #{event_buffer}"
                end
                event_buffer = ""
              end
            elsif line.start_with?("id:")
              event_id = line[3..].strip
            elsif line.start_with?("data:")
              data = line[5..].strip
              event_buffer += data
            elsif line.start_with?("event:")
              # Event type - could be used for different message types
              # For now, we treat all as data events
            end
          end
        end

        def handle_server_message(message)
          # Handle server-initiated requests and notifications
          # This would typically be passed to a message handler
          puts "Received server message: #{message.inspect}"
        end

        def wait_for_response_with_timeout(request_id, response_queue)
          Timeout.timeout(30) do
            response_queue.pop
          end
        rescue Timeout::Error
          @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
          raise RubyLLM::MCP::Errors::TimeoutError.new(message: "Request timed out after 30 seconds")
        end
      end
    end
  end
end
