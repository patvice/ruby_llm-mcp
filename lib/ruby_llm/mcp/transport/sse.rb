# frozen_string_literal: true

require "json"
require "uri"
require "faraday"
require "timeout"
require "securerandom"

module RubyLLM
  module MCP
    module Transport
      class SSE
        attr_reader :headers, :id

        def initialize(url, headers: {})
          @event_url = url
          @messages_url = nil

          uri = URI.parse(url)
          @root_url = "#{uri.scheme}://#{uri.host}"
          @root_url += ":#{uri.port}" if uri.port != uri.default_port

          @client_id = SecureRandom.uuid
          @headers = headers.merge({
                                     "Accept" => "text/event-stream",
                                     "Cache-Control" => "no-cache",
                                     "Connection" => "keep-alive",
                                     "X-CLIENT-ID" => @client_id
                                   })

          @id_counter = 0
          @id_mutex = Mutex.new
          @pending_requests = {}
          @pending_mutex = Mutex.new
          @connection_mutex = Mutex.new
          @running = true
          @sse_thread = nil

          # Start the SSE listener thread
          start_sse_listener
        end

        # rubocop:disable Metrics/MethodLength
        def request(body, add_id: true, wait_for_response: true)
          # Generate a unique request ID
          if add_id
            @id_mutex.synchronize { @id_counter += 1 }
            request_id = @id_counter
            body["id"] = request_id
          end

          # Create a queue for this request's response
          response_queue = Queue.new
          if wait_for_response
            @pending_mutex.synchronize do
              @pending_requests[request_id.to_s] = response_queue
            end
          end

          # Send the request using Faraday
          begin
            conn = Faraday.new do |f|
              f.options.timeout = 30
              f.options.open_timeout = 5
            end

            response = conn.post(@messages_url) do |req|
              @headers.each do |key, value|
                req.headers[key] = value
              end
              req.headers["Content-Type"] = "application/json"
              req.body = JSON.generate(body)
            end

            unless response.status == 200
              @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
              raise "Failed to request #{@messages_url}: #{response.status} - #{response.body}"
            end
          rescue StandardError => e
            @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
            raise e
          end
          return unless wait_for_response

          begin
            Timeout.timeout(30) do
              response_queue.pop
            end
          rescue Timeout::Error
            @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
            raise RubyLLM::MCP::Errors::TimeoutError.new(message: "Request timed out after 30 seconds")
          end
        end
        # rubocop:enable Metrics/MethodLength

        def close
          @running = false
          @sse_thread&.join(1) # Give the thread a second to clean up
          @sse_thread = nil
        end

        private

        def start_sse_listener
          @connection_mutex.synchronize do
            return if sse_thread_running?

            response_queue = Queue.new
            @pending_mutex.synchronize do
              @pending_requests["endpoint"] = response_queue
            end

            @sse_thread = Thread.new do
              listen_for_events while @running
            end
            @sse_thread.abort_on_exception = true

            endpoint = response_queue.pop
            set_message_endpoint(endpoint)

            @pending_mutex.synchronize { @pending_requests.delete("endpoint") }
          end
        end

        def set_message_endpoint(endpoint)
          uri = URI.parse(endpoint)

          @messages_url = if uri.host.nil?
                            "#{@root_url}#{endpoint}"
                          else
                            endpoint
                          end
        end

        def sse_thread_running?
          @sse_thread&.alive?
        end

        def listen_for_events
          stream_events_from_server
        rescue Faraday::Error => e
          handle_connection_error("SSE connection failed", e)
        rescue StandardError => e
          handle_connection_error("SSE connection error", e)
        end

        def stream_events_from_server
          buffer = +""
          create_sse_connection.get(@event_url) do |req|
            setup_request_headers(req)
            setup_streaming_callback(req, buffer)
          end
        end

        def create_sse_connection
          Faraday.new do |f|
            f.options.timeout = 300 # 5 minutes
            f.response :raise_error # raise errors on non-200 responses
          end
        end

        def setup_request_headers(request)
          @headers.each do |key, value|
            request.headers[key] = value
          end
        end

        def setup_streaming_callback(request, buffer)
          request.options.on_data = proc do |chunk, _size, _env|
            buffer << chunk
            process_buffer_events(buffer)
          end
        end

        def process_buffer_events(buffer)
          while (event = extract_event(buffer))
            event_data, buffer = event
            process_event(event_data) if event_data
          end
        end

        def handle_connection_error(message, error)
          puts "#{message}: #{error.message}. Reconnecting in 3 seconds..."
          sleep 3
        end

        def process_event(raw_event)
          return if raw_event[:data].nil?

          if raw_event[:event] == "endpoint"
            request_id = "endpoint"
            event = raw_event[:data]
          else
            event = begin
              JSON.parse(raw_event[:data])
            rescue StandardError
              nil
            end
            return if event.nil?

            request_id = event["id"]&.to_s
          end

          @pending_mutex.synchronize do
            if request_id && @pending_requests.key?(request_id)
              response_queue = @pending_requests.delete(request_id)
              response_queue&.push(event)
            end
          end
        rescue JSON::ParserError => e
          puts "Error parsing event data: #{e.message}"
        end

        def extract_event(buffer)
          return nil unless buffer.include?("\n\n")

          raw, rest = buffer.split("\n\n", 2)
          [parse_event(raw), rest]
        end

        def parse_event(raw)
          event = {}
          raw.each_line do |line|
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
      end
    end
  end
end
