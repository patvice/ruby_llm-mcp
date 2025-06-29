# frozen_string_literal: true

class TestServerManager
  @stdio_server_pid = nil
  @http_server_pid = nil

  COMMAND = "bun"
  STDIO_ARGS = "spec/fixtures/typescript-mcp/index.ts"
  HTTP_ARGS = "spec/fixtures/typescript-mcp/index.ts"
  FLAGS = ["--silent"].freeze

  class << self
    attr_accessor :stdio_server_pid, :http_server_pid

    def start_server
      return if stdio_server_pid && http_server_pid

      begin
        # Start stdio server
        unless stdio_server_pid
          self.stdio_server_pid = spawn(COMMAND, STDIO_ARGS, "--", *FLAGS, "--stdio")
          Process.detach(stdio_server_pid)
        end

        # Start HTTP streamable server
        unless http_server_pid
          self.http_server_pid = spawn(COMMAND, HTTP_ARGS, "--", *FLAGS)
          Process.detach(http_server_pid)
        end

        # Give servers time to start
        sleep 1.0
      rescue StandardError => e
        puts "Failed to start test server: #{e.message}"
        stop_server
        raise
      end
    end

    def stop_server
      stop_stdio_server
      stop_http_server
    end

    def stop_stdio_server
      return unless stdio_server_pid

      begin
        Process.kill("TERM", stdio_server_pid)
        Process.wait(stdio_server_pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # Process already dead or doesn't exist
      rescue StandardError => e
        puts "Warning: Failed to cleanly shutdown stdio server: #{e.message}"
      ensure
        self.stdio_server_pid = nil
      end
    end

    def stop_http_server
      return unless http_server_pid

      begin
        Process.kill("TERM", http_server_pid)
        Process.wait(http_server_pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # Process already dead or doesn't exist
      rescue StandardError => e
        puts "Warning: Failed to cleanly shutdown HTTP server: #{e.message}"
      ensure
        self.http_server_pid = nil
      end
    end

    def ensure_cleanup
      stop_server if stdio_server_pid || http_server_pid
    end

    def running?
      stdio_server_pid && process_exists?(stdio_server_pid) &&
        http_server_pid && process_exists?(http_server_pid)
    end

    private

    def process_exists?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end
  end
end

# Ensure server is always killed on exit
at_exit do
  TestServerManager.ensure_cleanup
end
