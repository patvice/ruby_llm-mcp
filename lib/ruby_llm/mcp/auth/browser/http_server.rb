# frozen_string_literal: true

require "cgi"
require "socket"

module RubyLLM
  module MCP
    module Auth
      module Browser
        # HTTP server utilities for OAuth callback handling
        # Provides lightweight HTTP server functionality without external dependencies
        class HttpServer
          attr_reader :port, :logger

          def initialize(port:, logger: nil)
            @port = port
            @logger = logger || MCP.logger
          end

          # Start TCP server for OAuth callbacks
          # @return [TCPServer] TCP server instance
          # @raise [Errors::TransportError] if server cannot start
          def start_server
            TCPServer.new("127.0.0.1", @port)
          rescue Errno::EADDRINUSE
            raise Errors::TransportError.new(
              message: "Cannot start OAuth callback server: port #{@port} is already in use. " \
                       "Please close the application using this port or choose a different callback_port."
            )
          rescue StandardError => e
            raise Errors::TransportError.new(
              message: "Failed to start OAuth callback server on port #{@port}: #{e.message}"
            )
          end

          # Configure client socket with timeout
          # @param client [TCPSocket] client socket
          def configure_client_socket(client)
            client.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [5, 0].pack("l_2"))
          end

          # Read HTTP request line from client
          # @param client [TCPSocket] client socket
          # @return [String, nil] request line
          def read_request_line(client)
            client.gets
          end

          # Extract method and path from request line
          # @param request_line [String] HTTP request line
          # @return [Array<String, String>, nil] method and path, or nil if invalid
          def extract_request_parts(request_line)
            parts = request_line.split
            return nil unless parts.length >= 2

            parts[0..1]
          end

          # Read HTTP headers from client
          # @param client [TCPSocket] client socket
          def read_http_headers(client)
            header_count = 0
            loop do
              break if header_count >= 100

              line = client.gets
              break if line.nil? || line.strip.empty?

              header_count += 1
            end
          end

          # Parse URL query parameters
          # @param query_string [String] query string
          # @return [Hash] parsed parameters
          def parse_query_params(query_string)
            params = {}
            query_string.split("&").each do |param|
              next if param.empty?

              key, value = param.split("=", 2)
              params[CGI.unescape(key)] = CGI.unescape(value || "")
            end
            params
          end

          # Send HTTP response to client
          # @param client [TCPSocket] client socket
          # @param status [Integer] HTTP status code
          # @param content_type [String] content type
          # @param body [String] response body
          def send_http_response(client, status, content_type, body)
            status_text = case status
                          when 200 then "OK"
                          when 400 then "Bad Request"
                          when 404 then "Not Found"
                          else "Unknown"
                          end

            response = "HTTP/1.1 #{status} #{status_text}\r\n"
            response += "Content-Type: #{content_type}\r\n"
            response += "Content-Length: #{body.bytesize}\r\n"
            response += "Connection: close\r\n"
            response += "\r\n"
            response += body

            client.write(response)
          rescue IOError, Errno::EPIPE => e
            @logger.debug("Error sending response: #{e.message}")
          end
        end
      end
    end
  end
end
