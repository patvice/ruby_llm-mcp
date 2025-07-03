# frozen_string_literal: true

class TestServerManager
  SERVERS = {
    stdio: {
      command: "bun",
      args: ["spec/fixtures/typescript-mcp/index.ts", "--", "--silent", "--stdio"],
      pid_accessor: :stdio_server_pid
    },
    http: {
      command: "bun",
      args: ["spec/fixtures/typescript-mcp/index.ts", "--", "--silent"],
      pid_accessor: :http_server_pid
    },
    pagination: {
      command: "bun",
      args: ["spec/fixtures/pagination-server/index.ts", "--", "--silent"],
      pid_accessor: :pagination_server_pid
    },
    sse: {
      command: "ruby",
      args: ["lib/app.rb", "--silent"],
      chdir: "spec/fixtures/fast-mcp-ruby",
      pid_accessor: :sse_server_pid
    }
  }.freeze

  class << self
    attr_accessor :stdio_server_pid, :http_server_pid, :sse_server_pid, :pagination_server_pid

    def start_server
      return if stdio_server_pid && http_server_pid && pagination_server_pid

      begin
        start_server_type(:stdio)
        start_server_type(:http)
        start_server_type(:pagination)

        # Give servers time to start
        sleep 1.0
      rescue StandardError => e
        puts "Failed to start test server: #{e.message}"
        stop_server
        raise
      end
    end

    def start_sse_server
      start_server_type(:sse)
    end

    def stop_server
      stop_stdio_server
      stop_http_server
      stop_pagination_server
    end

    def stop_stdio_server
      stop_server_type(:stdio)
    end

    def stop_http_server
      stop_server_type(:http)
    end

    def stop_pagination_server
      stop_server_type(:pagination)
    end

    def stop_sse_server
      stop_server_type(:sse)
    end

    def ensure_cleanup
      stop_server if stdio_server_pid || http_server_pid
      stop_sse_server if sse_server_pid
    end

    def running?
      stdio_server_pid && process_exists?(stdio_server_pid) &&
        http_server_pid && process_exists?(http_server_pid) &&
        sse_server_pid && process_exists?(sse_server_pid) &&
        pagination_server_pid && process_exists?(pagination_server_pid)
    end

    private

    def start_server_type(server_type)
      config = SERVERS[server_type]
      pid_accessor = config[:pid_accessor]

      return if send(pid_accessor)

      spawn_options = {}
      spawn_options[:chdir] = config[:chdir] if config[:chdir]

      pid = spawn(config[:command], *config[:args], **spawn_options)
      Process.detach(pid)
      send("#{pid_accessor}=", pid)
    end

    def stop_server_type(server_type)
      config = SERVERS[server_type]
      pid_accessor = config[:pid_accessor]
      pid = send(pid_accessor)

      return unless pid

      begin
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # Process already dead or doesn't exist
      rescue StandardError => e
        puts "Warning: Failed to cleanly shutdown #{server_type} server: #{e.message}"
      ensure
        send("#{pid_accessor}=", nil)
      end
    end

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
