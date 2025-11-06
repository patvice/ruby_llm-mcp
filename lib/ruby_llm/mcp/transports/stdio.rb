# frozen_string_literal: true

require "open3"
require "json"
require "timeout"
require "securerandom"

module RubyLLM
  module MCP
    module Transports
      class Stdio
        include Support::Timeout

        attr_reader :command, :stdin, :stdout, :stderr, :id, :coordinator

        def initialize(command:, coordinator:, request_timeout:, args: [], env: {}, oauth_provider: nil)
          @request_timeout = request_timeout
          @command = command
          @coordinator = coordinator
          @args = args
          @env = env || {}
          @client_id = SecureRandom.uuid
          # Note: Stdio transport doesn't use OAuth (local process communication)

          @id_counter = 0
          @id_mutex = Mutex.new
          @pending_requests = {}
          @pending_mutex = Mutex.new
          @running = false
          @reader_thread = nil
          @stderr_thread = nil
        end

        def request(body, add_id: true, wait_for_response: true)
          if add_id
            @id_mutex.synchronize { @id_counter += 1 }
            request_id = @id_counter
            body["id"] = request_id
          end

          response_queue = Queue.new
          if wait_for_response
            @pending_mutex.synchronize do
              @pending_requests[request_id.to_s] = response_queue
            end
          end

          begin
            body = JSON.generate(body)
            RubyLLM::MCP.logger.debug "Sending Request: #{body}"
            @stdin.puts(body)
            @stdin.flush
          rescue IOError, Errno::EPIPE => e
            @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
            restart_process
            raise RubyLLM::MCP::Errors::TransportError.new(message: e.message, error: e)
          end

          return unless wait_for_response

          begin
            with_timeout(@request_timeout / 1000, request_id: request_id) do
              response_queue.pop
            end
          rescue RubyLLM::MCP::Errors::TimeoutError => e
            @pending_mutex.synchronize { @pending_requests.delete(request_id.to_s) }
            log_message = "Stdio request timeout (ID: #{request_id}) after #{@request_timeout / 1000} seconds"
            RubyLLM::MCP.logger.error(log_message)
            raise e
          end
        end

        def alive?
          @running
        end

        def start
          start_process unless @running
          @running = true
        end

        def close
          @running = false

          [@stdin, @stdout, @stderr].each do |stream|
            stream&.close
          rescue IOError, Errno::EBADF
            nil
          end

          [@wait_thread, @reader_thread, @stderr_thread].each do |thread|
            thread&.join(1)
          rescue StandardError
            nil
          end

          @stdin = @stdout = @stderr = nil
          @wait_thread = @reader_thread = @stderr_thread = nil
        end

        def set_protocol_version(version)
          @protocol_version = version
        end

        private

        def start_process
          close if @stdin || @stdout || @stderr || @wait_thread

          @stdin, @stdout, @stderr, @wait_thread = if @env.empty?
                                                     Open3.popen3(@command, *@args)
                                                   else
                                                     Open3.popen3(@env, @command, *@args)
                                                   end

          start_reader_thread
          start_stderr_thread
        end

        def restart_process
          RubyLLM::MCP.logger.error "Process connection lost. Restarting..."
          start_process
        end

        def start_reader_thread
          @reader_thread = Thread.new do
            read_stdout_loop
          end

          @reader_thread.abort_on_exception = true
        end

        def read_stdout_loop
          while @running
            begin
              handle_stdout_read
            rescue IOError, Errno::EPIPE => e
              handle_stream_error(e, "Reader")
              break unless @running
            rescue StandardError => e
              RubyLLM::MCP.logger.error "Error in reader thread: #{e.message}, #{e.backtrace.join("\n")}"
              sleep 1
            end
          end
        end

        def handle_stdout_read
          if @stdout.closed? || @wait_thread.nil? || !@wait_thread.alive?
            if @running
              sleep 1
              restart_process
            end
            return
          end

          line = @stdout.gets
          return unless line && !line.strip.empty?

          process_response(line.strip)
        end

        def handle_stream_error(error, stream_name)
          # Check @running to distinguish graceful shutdown from unexpected errors.
          # During shutdown, streams are closed intentionally and shouldn't trigger restarts.
          if @running
            RubyLLM::MCP.logger.error "#{stream_name} error: #{error.message}. Restarting in 1 second..."
            sleep 1
            restart_process
          else
            # Graceful shutdown in progress
            RubyLLM::MCP.logger.debug "#{stream_name} thread exiting during shutdown"
          end
        end

        def start_stderr_thread
          @stderr_thread = Thread.new do
            read_stderr_loop
          end

          @stderr_thread.abort_on_exception = true
        end

        def read_stderr_loop
          while @running
            begin
              handle_stderr_read
            rescue IOError, Errno::EPIPE => e
              handle_stream_error(e, "Stderr reader")
              break unless @running
            rescue StandardError => e
              RubyLLM::MCP.logger.error "Error in stderr thread: #{e.message}"
              sleep 1
            end
          end
        end

        def handle_stderr_read
          if @stderr.closed? || @wait_thread.nil? || !@wait_thread.alive?
            sleep 1
            return
          end

          line = @stderr.gets
          return unless line && !line.strip.empty?

          RubyLLM::MCP.logger.info(line.strip)
        end

        def process_response(line)
          response = JSON.parse(line)
          request_id = response["id"]&.to_s
          result = RubyLLM::MCP::Result.new(response)
          RubyLLM::MCP.logger.debug "Result Received: #{result.inspect}"

          result = @coordinator.process_result(result)
          return if result.nil?

          # Handle regular responses (tool calls, etc.)
          @pending_mutex.synchronize do
            if result.matching_id?(request_id) && @pending_requests.key?(request_id)
              response_queue = @pending_requests.delete(request_id)
              response_queue&.push(result)
            end
          end
        rescue JSON::ParserError => e
          RubyLLM::MCP.logger.error("Error parsing response as JSON: #{e.message}\nRaw response: #{line}")
        end
      end
    end
  end
end
