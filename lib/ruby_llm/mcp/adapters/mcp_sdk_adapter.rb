# frozen_string_literal: true

require_relative "mcp_transports/coordinator_stub"
require_relative "mcp_transports/stdio"
require_relative "mcp_transports/sse"
require_relative "mcp_transports/streamable_http"

module RubyLLM
  module MCP
    module Adapters
      class MCPSdkAdapter < BaseAdapter
        # Only declare features the official MCP SDK supports
        # Note: The MCP gem (as of v0.4) does NOT support prompts or resource templates
        supports :tools, :resources

        # Supported transports:
        # - stdio: Via custom wrapper using native stdio transport ✓ FULLY TESTED
        # - sse: Via custom wrapper using native SSE transport ✓ FUNCTIONAL
        # - http: Via MCP::Client::HTTP (for simple JSON-only HTTP servers)
        supports_transport :stdio, :http, :sse, :streamable, :streamable_http

        attr_reader :transport_type, :config

        def initialize(client, transport_type:, config: {})
          validate_transport!(transport_type)
          require_mcp_gem!
          super

          @mcp_client = nil
<<<<<<< Updated upstream
=======
          @notification_handler = NotificationHandler.new(client)

          warn_passive_extension_support! if configured_extensions?
>>>>>>> Stashed changes
        end

        def start
          return if @mcp_client

          transport = build_transport
          transport.start if transport.respond_to?(:start)

          @mcp_client = ::MCP::Client.new(transport: transport)
        end

        def stop
          if @mcp_client && @mcp_client.transport.respond_to?(:close)
            @mcp_client.transport.close
          end
          @mcp_client = nil
        end

        def restart!
          stop
          start
        end

        def alive?
          !@mcp_client.nil?
        end

        def ping # rubocop:disable Naming/PredicateMethod
          ensure_started
          alive?
        end

        def capabilities
          # Return minimal capabilities for official SDK
          # Note: Prompts are not supported by the MCP gem
          ServerCapabilities.new({
                                   "tools" => {},
                                   "resources" => {}
                                 })
        end

        def client_capabilities
          {} # Official SDK handles this internally
        end

        def supports_extension_negotiation?
          false
        end

        def extension_mode
          :passive
        end

        def build_client_extensions_capabilities(protocol_version:) # rubocop:disable Lint/UnusedMethodArgument
          {}
        end

        def tool_list(cursor: nil) # rubocop:disable Lint/UnusedMethodArgument
          ensure_started
          @mcp_client.tools.map { |tool| transform_tool(tool) }
        end

        def execute_tool(name:, parameters:)
          ensure_started
          tool = find_tool(name)
          result = @mcp_client.call_tool(tool: tool, arguments: parameters)
          transform_tool_result(result)
        rescue RubyLLM::MCP::Errors::TimeoutError => e
          native_transport = @mcp_client&.transport&.native_transport
          if native_transport&.alive? && !e.request_id.nil?
            cancelled_notification(reason: "Request timed out", request_id: e.request_id)
          end
          raise e
        end

        def resource_list(cursor: nil) # rubocop:disable Lint/UnusedMethodArgument
          ensure_started
          @mcp_client.resources.map { |resource| transform_resource(resource) }
        end

        def resource_read(uri:)
          ensure_started
          result = @mcp_client.read_resource(uri: uri)
          transform_resource_content(result)
        end

        def prompt_list(cursor: nil) # rubocop:disable Lint/UnusedMethodArgument
          []
        end

        def execute_prompt(name:, arguments:)
          raise NotImplementedError, "Prompts are not supported by the MCP SDK (gem 'mcp')"
        end

        def resource_template_list(cursor: nil) # rubocop:disable Lint/UnusedMethodArgument
          []
        end

        def cancelled_notification(reason:, request_id:)
          return unless @mcp_client&.transport.respond_to?(:native_transport)

          native_transport = @mcp_client.transport.native_transport
          return unless native_transport

          body = RubyLLM::MCP::Native::Messages::Notifications.cancelled(
            request_id: request_id,
            reason: reason
          )
          native_transport.request(body, wait_for_response: false)
        end

        # These methods remain as NotImplementedError from base class:
        # - completion_resource
        # - completion_prompt
        # - set_logging
        # - resources_subscribe
        # - initialize_notification
        # - roots_list_change_notification
        # - ping_response
        # - roots_list_response
        # - sampling_create_message_response
        # - error_response
        # - elicitation_response
        # - register_resource

        private

        def ensure_started
          start unless @mcp_client
        end

        def require_mcp_gem!
          require "mcp"
          if ::MCP::VERSION < "0.4"
            raise Errors::AdapterConfigurationError.new(message: <<~MSG)
              The official MCP SDK version 0.4 or higher is required to use the :mcp_sdk adapter.
            MSG
          end
        rescue LoadError
          raise LoadError, <<~MSG
            The official MCP SDK is required to use the :mcp_sdk adapter.

            Add to your Gemfile:
              gem 'mcp', '~> 0.4'

            Then run: bundle install
          MSG
        end

        def build_transport
          case @transport_type
          when :http
            # MCP::Client::HTTP is for simple JSON-only HTTP servers
            # Use :streamable for servers that support the streamable HTTP/SSE protocol
            ::MCP::Client::HTTP.new(
              url: @config[:url],
              headers: @config[:headers] || {}
            )
          when :stdio
            MCPTransports::Stdio.new(
              command: @config[:command],
              args: @config[:args] || [],
              env: @config[:env] || {},
              request_timeout: @config[:request_timeout] || 10_000
            )
          when :sse
            MCPTransports::SSE.new(
              url: @config[:url],
              headers: @config[:headers] || {},
              version: @config[:version] || :http2,
              request_timeout: @config[:request_timeout] || 10_000
            )
          when :streamable, :streamable_http
            config_copy = @config.dup
            oauth_provider = Auth::TransportOauthHelper.create_oauth_provider(config_copy) if Auth::TransportOauthHelper.oauth_config_present?(config_copy)

            MCPTransports::StreamableHTTP.new(
              url: @config[:url],
              headers: @config[:headers] || {},
              version: @config[:version] || :http2,
              request_timeout: @config[:request_timeout] || 10_000,
              reconnection: @config[:reconnection] || {},
              oauth_provider: oauth_provider,
              rate_limit: @config[:rate_limit],
              session_id: @config[:session_id]
            )
          end
        end

        def find_tool(name)
          @mcp_client.tools.find { |t| t.name == name } ||
            raise(Errors::ResponseError.new(
                    message: "Tool '#{name}' not found",
                    error: { "code" => -32_602, "message" => "Tool not found" }
                  ))
        end

        # Transform methods to normalize official SDK objects
        def transform_tool(tool)
          {
            "name" => tool.name,
            "description" => tool.description,
<<<<<<< Updated upstream
            "inputSchema" => tool.input_schema
          }
=======
            "inputSchema" => tool.input_schema,
            "outputSchema" => tool.output_schema,
            "_meta" => extract_tool_meta(tool)
          }.compact
>>>>>>> Stashed changes
        end

        def transform_resource(resource)
          {
            "name" => resource["name"],
            "uri" => resource["uri"],
            "description" => resource["description"],
            "mimeType" => resource["mimeType"]
          }
        end

        def transform_tool_result(result)
          # The MCP gem returns the full JSON-RPC response
          # Extract the content from result["result"]["content"]
          content = if result.is_a?(Hash) && result["result"] && result["result"]["content"]
                      result["result"]["content"]
                    elsif result.is_a?(Array)
                      result.map { |item| transform_content_item(item) }
                    else
                      [{ "type" => "text", "text" => result.to_s }]
                    end

          is_error = if result.is_a?(Hash) && result["result"]
                       result["result"]["isError"]
                     end

          result_data = { "content" => content }
          result_data["isError"] = is_error unless is_error.nil?

          Result.new({
                       "result" => result_data
                     })
        end

        def transform_content_item(item)
          case item
          when String
            { "type" => "text", "text" => item }
          when Hash
            item
          else
            { "type" => "text", "text" => item.to_s }
          end
        end

        def transform_resource_content(result)
          contents = if result.is_a?(Array)
                       result.map { |r| transform_single_resource_content(r) }
                     else
                       [transform_single_resource_content(result)]
                     end

          Result.new({
                       "result" => {
                         "contents" => contents
                       }
                     })
        end

        def transform_single_resource_content(result)
          {
            "uri" => result["uri"],
            "mimeType" => result["mimeType"],
            "text" => result["text"],
            "blob" => result["blob"]
          }
        end
<<<<<<< Updated upstream
=======

        def transform_prompt_result(result)
          if result.is_a?(Hash) && (result.key?("result") || result.key?("error"))
            Result.new(result)
          else
            Result.new({
                         "result" => result || {}
                       })
          end
        end

        def configured_extensions?
          !Extensions::Registry.normalize_map(@config[:extensions]).empty?
        end

        def warn_passive_extension_support!
          self.class.warn_passive_extension_support_once
        end

        def extract_tool_meta(tool)
          return tool["_meta"] if tool.respond_to?(:[]) && tool["_meta"]
          return tool.meta if tool.respond_to?(:meta)
          return tool.instance_variable_get(:@meta) if tool.instance_variable_defined?(:@meta)

          nil
        end

        class << self
          def warn_passive_extension_support_once
            @extensions_warning_mutex ||= Mutex.new

            @extensions_warning_mutex.synchronize do
              return if @extensions_warning_emitted

              RubyLLM::MCP.logger.warn(
                "MCP SDK adapter extension configuration is passive: extensions are accepted but not advertised."
              )
              @extensions_warning_emitted = true
            end
          end
        end
>>>>>>> Stashed changes
      end
    end
  end
end
