# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Transports
        class Stdio
          include Support::Timeout

          attr_reader :command, :stdin, :stdout, :stderr, :id, :coordinator

          # Default environment that merges with user-provided env
          # This ensures PATH and other critical env vars are preserved
          DEFAULT_ENV = ENV.to_h.freeze

          def initialize(command:, coordinator:, request_timeout:, args: [], env: {})
            @request_timeout = request_timeout
            @command = command
            @coordinator = coordinator
            @args = args
            # Merge provided env with default environment (user env takes precedence)
            @env = DEFAULT_ENV.merge(env || {})
            @client_id = SecureRandom.uuid

            @id_counter = 0
            @id_mutex = Mutex.new
            @pending_requests = {}
            @pending_mutex = Mutex.new
            @state_mutex = Mutex.new
            @running = false
            @reader_thread = nil
            @stderr_thread = nil
          end

          def request(body, wait_for_response: true)
            request_id = prepare_request_id(body, wait_for_response)
            response_queue = register_pending_request(request_id, wait_for_response)

            send_request(body, request_id)

            return unless wait_for_response

            wait_for_request_response(request_id, response_queue)
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
            start_process
          end

          def close
            @state_mutex.synchronize do
              return unless @running

              @running = false
            end
            shutdown_process
            fail_pending_requests!(RubyLLM::MCP::Errors::TransportError.new(message: "Transport closed"))
          end

          def set_protocol_version(version)
            @protocol_version = version
          end

          private

          def prepare_request_id(body, wait_for_response)
            request_id = body["id"] || body[:id]

            if wait_for_response && request_id.nil?
              raise ArgumentError, "Request ID must be provided in message body when wait_for_response is true"
            end

            request_id
          end

          def register_pending_request(request_id, wait_for_response)
            return nil unless wait_for_response

            response_queue = Queue.new
            @pending_mutex.synchronize do
              @pending_requests[request_id.to_s] = response_queue
            end
            response_queue
          end

          def send_request(body, request_id)
            body = JSON.generate(body)
            RubyLLM::MCP.logger.debug "Sending Request: #{body}"
            stdin = @state_mutex.synchronize { @stdin }
            unless stdin
              raise RubyLLM::MCP::Errors::TransportError.new(message: "Transport is not connected")
            end

            stdin.puts(body)
            stdin.flush
          rescue IOError, Errno::EPIPE => e
            @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) } if request_id
            raise RubyLLM::MCP::Errors::TransportError.new(message: e.message, error: e)
          rescue RubyLLM::MCP::Errors::TransportError => e
            @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) } if request_id
            raise e
          end

          def wait_for_request_response(request_id, response_queue)
            result = with_timeout(@request_timeout / 1000, request_id: request_id) do
              response_queue.pop
            end
            raise result if result.is_a?(RubyLLM::MCP::Errors::TransportError)

            result
          rescue RubyLLM::MCP::Errors::TimeoutError => e
            @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
            log_message = "Stdio request timeout (ID: #{request_id}) after #{@request_timeout / 1000} seconds"
            RubyLLM::MCP.logger.error(log_message)
            raise e
          end

          def start_process
            shutdown_process if @stdin || @stdout || @stderr || @wait_thread

            # Always pass env - it now includes defaults merged with user overrides
            @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(@env, @command, *@args)

            start_reader_thread
            start_stderr_thread
          end

          def shutdown_process
            close_stdin
            terminate_child_process
            close_output_streams
            join_reader_threads
            clear_process_handles
          end

          def close_stdin
            @stdin&.close
          rescue IOError, Errno::EBADF
            # Already closed
          end

          def terminate_child_process
            return unless @wait_thread

            @wait_thread.join(1) if @wait_thread.alive? # 1s grace period
            send_signal_to_process("TERM", 2) if @wait_thread.alive?
            send_signal_to_process("KILL", 0) if @wait_thread.alive?
          end

          def send_signal_to_process(signal, wait_time)
            Process.kill(signal, @wait_thread.pid)
            @wait_thread.join(wait_time) if wait_time.positive?
          rescue StandardError => e
            RubyLLM::MCP.logger.debug "Error sending #{signal}: #{e.message}"
          end

          def close_output_streams
            [@stdout, @stderr].each do |stream|
              stream&.close
            rescue IOError, Errno::EBADF
              # Already closed
            end
          end

          def join_reader_threads
            [@reader_thread, @stderr_thread].each do |thread|
              next unless thread&.alive?
              next if Thread.current == thread # Avoid self-join deadlock

              thread.join(1)
            rescue StandardError => e
              RubyLLM::MCP.logger.debug "Error joining thread: #{e.message}"
            end
          end

          def clear_process_handles
            @stdin = @stdout = @stderr = nil
            @wait_thread = @reader_thread = @stderr_thread = nil
          end

          def fail_pending_requests!(error)
            @pending_mutex.synchronize do
              @pending_requests.each_value do |queue|
                queue.push(error)
              end
              @pending_requests.clear
            end
          end

          def safe_close_with_error(error)
            fail_pending_requests!(error)
            close
          end

          def start_reader_thread
            @reader_thread = Thread.new do
              read_stdout_loop
            end
          end

          def read_stdout_loop
            while running?
              begin
                handle_stdout_read
              rescue IOError, Errno::EPIPE => e
                handle_stream_error(e, "Reader")
                break unless running?
              rescue StandardError => e
                RubyLLM::MCP.logger.error "Error in reader thread: #{e.message}, #{e.backtrace.join("\n")}"
                sleep 1
              end
            end
          end

          def handle_stdout_read
            if @stdout.closed? || @wait_thread.nil? || !@wait_thread.alive?
              # Process is dead - if we're still running, this is an error
              if running?
                error = RubyLLM::MCP::Errors::TransportError.new(
                  message: "Process terminated unexpectedly"
                )
                safe_close_with_error(error)
              end
              return
            end

            line = @stdout.gets
            return unless line && !line.strip.empty?

            process_response(line.strip)
          end

          def handle_stream_error(error, stream_name)
            if running?
              RubyLLM::MCP.logger.error "#{stream_name} error: #{error.message}. Closing transport."
              safe_close_with_error(error)
            else
              RubyLLM::MCP.logger.debug "#{stream_name} thread exiting during shutdown"
            end
          end

          def start_stderr_thread
            @stderr_thread = Thread.new do
              read_stderr_loop
            end
          end

          def read_stderr_loop
            while running?
              begin
                handle_stderr_read
              rescue IOError, Errno::EPIPE => e
                handle_stream_error(e, "Stderr reader")
                break unless running?
              rescue StandardError => e
                RubyLLM::MCP.logger.error "Error in stderr thread: #{e.message}"
                sleep 1
              end
            end
          end

          def handle_stderr_read
            if @stderr.closed? || @wait_thread.nil? || !@wait_thread.alive?
              return
            end

            line = @stderr.gets
            return unless line && !line.strip.empty?

            RubyLLM::MCP.logger.info(line.strip)
          end

          def process_response(line)
            response = parse_and_validate_envelope(line)
            return unless response

            request_id = response["id"]&.to_s
            result = RubyLLM::MCP::Result.new(response)
            RubyLLM::MCP.logger.debug "Result Received: #{result.inspect}"

            result = @coordinator.process_result(result)
            return if result.nil?

            @pending_mutex.synchronize do
              if result.matching_id?(request_id) && @pending_requests.key?(request_id)
                response_queue = @pending_requests.delete(request_id)
                response_queue&.push(result)
              end
            end
          end

          def parse_and_validate_envelope(line)
            response = JSON.parse(line)

            # Validate JSON-RPC envelope
            validator = Native::JsonRpc::EnvelopeValidator.new(response)
            unless validator.valid?
              RubyLLM::MCP.logger.error("Invalid JSON-RPC envelope: #{validator.error_message}\nRaw: #{line}")

              # If this is a request with an id, send an error response
              if response.is_a?(Hash) && response["id"]
                send_invalid_request_error(response["id"], validator.error_message)
              end

              return nil
            end

            response
          rescue JSON::ParserError => e
            RubyLLM::MCP.logger.error("JSON parse error: #{e.message}\nRaw response: #{line}")

            # JSON-RPC 2.0 §5.1: Parse error should return error with id: null
            send_parse_error(e.message)
            nil
          end

          def send_invalid_request_error(id, detail)
            error_body = Native::Messages::Responses.error(
              id: id,
              message: "Invalid Request",
              code: Native::JsonRpc::ErrorCodes::INVALID_REQUEST,
              data: { detail: detail }
            )

            begin
              body_json = JSON.generate(error_body)
              @stdin.puts(body_json)
              @stdin.flush
            rescue IOError, Errno::EPIPE => e
              RubyLLM::MCP.logger.error("Failed to send invalid request error: #{e.message}")
            end
          end

          def send_parse_error(detail)
            error_body = Native::Messages::Responses.error(
              id: nil,
              message: "Parse error",
              code: Native::JsonRpc::ErrorCodes::PARSE_ERROR,
              data: { detail: detail }
            )

            begin
              body_json = JSON.generate(error_body)
              @stdin.puts(body_json)
              @stdin.flush
            rescue IOError, Errno::EPIPE => e
              RubyLLM::MCP.logger.error("Failed to send parse error: #{e.message}")
            end
          end
        end
      end
    end
  end
end
