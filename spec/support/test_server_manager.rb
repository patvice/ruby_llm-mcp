# frozen_string_literal: true

require "socket"
require "timeout"

class TestServerManager
  PORTS = {
    http: ENV.fetch("PORT1", 3005),
    sse: ENV.fetch("PORT2", 3006),
    pagination: ENV.fetch("PORT3", 3007)
  }.freeze

  HTTP_SERVER_URL = "http://localhost:#{PORTS[:http]}/mcp".freeze
  PAGINATION_SERVER_URL = "http://localhost:#{PORTS[:pagination]}/mcp".freeze
  SSE_SERVER_URL = "http://localhost:#{PORTS[:sse]}/mcp/sse".freeze

  # Environment variable to control whether to start servers as subprocesses
  # Set EXTERNAL_TEST_SERVERS=true to use external servers (useful for CI)
  EXTERNAL_SERVERS = ENV.fetch("EXTERNAL_TEST_SERVERS", "false").downcase == "true"

  SERVERS = {
    stdio: {
      command: "bun",
      args: ["spec/fixtures/typescript-mcp/index.ts", "--", "--silent", "--stdio"],
      pid_accessor: :stdio_server_pid
    },
    http: {
      command: "bun",
      args: ["spec/fixtures/typescript-mcp/index.ts", "--", "--silent"],
      pid_accessor: :http_server_pid,
      port: PORTS[:http]
    },
    pagination: {
      command: "bun",
      args: ["spec/fixtures/pagination-server/index.ts", "--", "--silent"],
      pid_accessor: :pagination_server_pid,
      port: PORTS[:pagination]
    },
    sse: {
      command: "ruby",
      args: ["lib/app.rb", "--silent"],
      chdir: "spec/fixtures/fast-mcp-ruby",
      pid_accessor: :sse_server_pid,
      port: PORTS[:sse]
    }
  }.freeze

  class << self
    attr_accessor :stdio_server_pid, :http_server_pid, :sse_server_pid, :pagination_server_pid

    def start_server
      if EXTERNAL_SERVERS
        wait_for_external_servers
      else
        start_subprocess_servers
      end
    end

    def stop_server
      return if EXTERNAL_SERVERS

      stop_stdio_server
      stop_http_server
      stop_sse_server
      stop_pagination_server
    end

    def stop_stdio_server
      return if EXTERNAL_SERVERS

      stop_server_type(:stdio)
    end

    def stop_http_server
      return if EXTERNAL_SERVERS

      stop_server_type(:http)
    end

    def stop_pagination_server
      return if EXTERNAL_SERVERS

      stop_server_type(:pagination)
    end

    def stop_sse_server
      return if EXTERNAL_SERVERS

      stop_server_type(:sse)
    end

    def ensure_cleanup
      return if EXTERNAL_SERVERS

      stop_server if stdio_server_pid || http_server_pid
      stop_sse_server if sse_server_pid
    end

    def running?
      if EXTERNAL_SERVERS
        external_servers_running?
      else
        stdio_server_pid && process_exists?(stdio_server_pid) &&
          http_server_pid && process_exists?(http_server_pid) &&
          sse_server_pid && process_exists?(sse_server_pid) &&
          pagination_server_pid && process_exists?(pagination_server_pid)
      end
    end

    private

    def start_subprocess_servers
      return if stdio_server_pid && http_server_pid && pagination_server_pid && sse_server_pid

      begin
        start_server_type(:stdio)
        start_server_type(:http)
        start_server_type(:sse)
        start_server_type(:pagination)
      rescue StandardError => e
        puts "Failed to start test server: #{e.message}"
        stop_server
        raise
      end
    end

    def wait_for_external_servers
      puts "Waiting for external servers to be ready..."

      # Wait for HTTP-based servers
      wait_for_external_server(:http)
      wait_for_external_server(:pagination)
      wait_for_external_server(:sse)

      puts "All external servers are ready!"
    end

    def wait_for_external_server(server_type)
      config = SERVERS[server_type]
      port = config[:port]

      return unless port

      begin
        wait_for_port(port)
        puts "External #{server_type} server is ready on port #{port}"
      rescue Timeout::Error
        raise "External #{server_type} server on port #{port} is not responding after timeout"
      end
    end

    def external_servers_running?
      %i[http pagination sse].all? do |server_type|
        config = SERVERS[server_type]
        port = config[:port]
        port_open?(port)
      end
    end

    def port_open?(port, host = "127.0.0.1")
      Socket.tcp(host, port, connect_timeout: 1).close
      true
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      false
    end

    def start_server_type(server_type)
      config = SERVERS[server_type]
      pid_accessor = config[:pid_accessor]

      return if send(pid_accessor)

      spawn_options = {}
      spawn_options[:chdir] = config[:chdir] if config[:chdir]

      pid = spawn(config[:command], *config[:args], **spawn_options)
      Process.detach(pid)
      send("#{pid_accessor}=", pid)

      # Wait for the server to start, ensure they are ready to start
      wait_for_port(config[:port]) if config[:port]
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

    def wait_for_port(port, host = "127.0.0.1", timeout = 15)
      Timeout.timeout(timeout) do
        loop do
          Socket.tcp(host, port, connect_timeout: 1).close
          break
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
          sleep 0.1
        end
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

# Ensure server is always killed on exit (only for subprocess mode)
at_exit do
  TestServerManager.ensure_cleanup
end
