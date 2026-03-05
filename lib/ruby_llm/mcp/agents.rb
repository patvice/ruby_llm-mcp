# frozen_string_literal: true

module RubyLLM
  module MCP
    module Agents
      def self.included(base)
        base.extend(ClassMethods)
        base.prepend(InstanceMethods)
      end

      module ClassMethods
        def with_toolsets(*toolset_names)
          @mcp_toolset_names = toolset_names.flatten.compact.map(&:to_s).uniq
          self
        end

        alias with_mcp_tools with_toolsets

        def with_mcps(*mcp_names)
          @mcp_client_names = mcp_names.flatten.compact.map(&:to_s).uniq
          self
        end

        def mcp_toolset_names
          return @mcp_toolset_names if instance_variable_defined?(:@mcp_toolset_names)
          return superclass.mcp_toolset_names if superclass.respond_to?(:mcp_toolset_names)

          []
        end

        def mcp_client_names
          return @mcp_client_names if instance_variable_defined?(:@mcp_client_names)
          return superclass.mcp_client_names if superclass.respond_to?(:mcp_client_names)

          []
        end

        def mcp_tools_from_clients(clients)
          return [] if mcp_toolset_names.empty? && mcp_client_names.empty?

          normalized_clients = normalize_clients(clients)

          toolset_tools = resolve_toolset_tools(normalized_clients)
          mcp_tools = resolve_mcp_tools(normalized_clients)

          (toolset_tools + mcp_tools).uniq(&:name)
        end

        def with_mcp_tools?
          mcp_toolset_names.any? || mcp_client_names.any?
        end

        private

        def normalize_clients(clients)
          return clients.transform_keys(&:to_s) if clients.is_a?(Hash)

          Array(clients).each_with_object({}) do |client, acc|
            acc[client.name.to_s] = client
          end
        end

        def resolve_toolset_tools(clients)
          return [] if mcp_toolset_names.empty?

          configured_toolsets = RubyLLM::MCP.toolsets
          missing_toolsets = mcp_toolset_names.reject { |name| configured_toolsets.key?(name.to_sym) }
          if missing_toolsets.any?
            raise Errors::ConfigurationError.new(
              message: "Unknown MCP toolset name(s): #{missing_toolsets.join(', ')}"
            )
          end

          mcp_toolset_names.flat_map do |name|
            toolset = configured_toolsets.fetch(name.to_sym)
            toolset.tools(clients: clients.values)
          end
        end

        def resolve_mcp_tools(clients)
          return [] if mcp_client_names.empty?

          missing_clients = mcp_client_names - clients.keys
          if missing_clients.any?
            raise Errors::ConfigurationError.new(
              message: "Unknown MCP client name(s): #{missing_clients.join(', ')}"
            )
          end

          mcp_client_names.flat_map { |name| clients.fetch(name).tools }
        end
      end

      module InstanceMethods
        def ask(...)
          return with_mcp_tools_connection { super } if self.class.with_mcp_tools?

          super
        end

        private

        def with_mcp_tools_connection
          RubyLLM::MCP.establish_connection do |clients|
            tools = self.class.mcp_tools_from_clients(clients)
            chat.with_tools(*tools) if tools.any?
            yield
          end
        end
      end
    end
  end
end
