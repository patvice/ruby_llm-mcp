# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      # Centralized message builders for MCP JSON-RPC communication
      # All message construction happens here, returning properly formatted bodies
      module Messages
        JSONRPC_VERSION = "2.0"

        # Request methods
        METHOD_INITIALIZE = "initialize"
        METHOD_PING = "ping"
        METHOD_TOOLS_LIST = "tools/list"
        METHOD_TOOLS_CALL = "tools/call"
        METHOD_RESOURCES_LIST = "resources/list"
        METHOD_RESOURCES_READ = "resources/read"
        METHOD_RESOURCES_TEMPLATES_LIST = "resources/templates/list"
        METHOD_RESOURCES_SUBSCRIBE = "resources/subscribe"
        METHOD_PROMPTS_LIST = "prompts/list"
        METHOD_PROMPTS_GET = "prompts/get"
        METHOD_COMPLETION_COMPLETE = "completion/complete"
        METHOD_LOGGING_SET_LEVEL = "logging/setLevel"

        # Notification methods
        METHOD_NOTIFICATION_INITIALIZED = "notifications/initialized"
        METHOD_NOTIFICATION_CANCELLED = "notifications/cancelled"
        METHOD_NOTIFICATION_ROOTS_LIST_CHANGED = "notifications/roots/list_changed"

        # Reference types
        REF_TYPE_PROMPT = "ref/prompt"
        REF_TYPE_RESOURCE = "ref/resource"
      end
    end
  end
end
