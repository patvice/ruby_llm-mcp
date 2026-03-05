# frozen_string_literal: true

module RubyLLM
  module MCP
    class Toolset
      attr_reader :name

      def initialize(name:)
        @name = name.to_sym
        @client_names = []
        @include_tool_names = []
        @exclude_tool_names = []
        @exclusive = false
      end

      def from_clients(*names)
        @client_names = normalize_names(names)
        self
      end

      alias clients from_clients

      def include_tools(*names)
        @include_tool_names = normalize_names(names)
        @exclusive = true
        self
      end

      def exclude_tools(*names)
        @exclude_tool_names = normalize_names(names)
        self
      end

      def tools(clients:)
        normalized_clients = clients.is_a?(Hash) ? clients.values : clients

        return [] if normalized_clients.empty?

        selected_clients = if @client_names.any?
                             clients_by_name = normalized_clients.each_with_object({}) do |client, acc|
                               acc[client.name.to_s] = client
                             end
                             missing_names = @client_names - clients_by_name.keys
                             if missing_names.any?
                               raise Errors::ConfigurationError.new(
                                 message: "Unknown MCP client name(s): #{missing_names.join(', ')}"
                               )
                             end

                             clients_by_name.values_at(*@client_names)
                           else
                             normalized_clients
                           end

        resolved_tools = selected_clients.map(&:tools).flatten
        resolved_tools = resolve_include_tools(resolved_tools)
        resolved_tools = resolve_exclude_tools(resolved_tools)
        resolved_tools.uniq(&:name)
      end

      def to_a
        RubyLLM::MCP.establish_connection do |clients_map|
          tools(clients: clients_map.values)
        end
      end

      private

      def resolve_include_tools(resolved_tools)
        return resolved_tools unless @exclusive && @include_tool_names.any?

        resolved_tools.select { |tool| @include_tool_names.include?(tool.name) }
      end

      def resolve_exclude_tools(resolved_tools)
        return resolved_tools if @exclude_tool_names.empty?

        resolved_tools.reject { |tool| @exclude_tool_names.include?(tool.name) }
      end

      def normalize_names(names)
        names.flatten.compact.map(&:to_s)
      end
    end
  end
end
