# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Messages
        # Request message builders
        # All methods return a JSON-RPC request body ready to be sent
        module Requests
          extend Helpers

          module_function

          def initialize(protocol_version:, capabilities:)
            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_INITIALIZE,
              params: {
                protocolVersion: protocol_version,
                capabilities: capabilities,
                clientInfo: {
                  name: "RubyLLM-MCP Client",
                  version: RubyLLM::MCP::VERSION
                }
              }
            }
          end

          def ping(tracking_progress: false)
            params = add_progress_token({}, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_PING,
              params: params
            }.tap { |body| body.delete(:params) if params.empty? }
          end

          def tool_list(cursor: nil, tracking_progress: false)
            params = {}
            params = add_cursor(params, cursor)
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_TOOLS_LIST,
              params: params
            }.tap { |body| body.delete(:params) if params.empty? }
          end

          def tool_call(name:, parameters: {}, tracking_progress: false)
            params = {
              name: name,
              arguments: parameters
            }
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_TOOLS_CALL,
              params: params
            }
          end

          def resource_list(cursor: nil, tracking_progress: false)
            params = {}
            params = add_cursor(params, cursor)
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_RESOURCES_LIST,
              params: params
            }.tap { |body| body.delete(:params) if params.empty? }
          end

          def resource_read(uri:, tracking_progress: false)
            params = { uri: uri }
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_RESOURCES_READ,
              params: params
            }
          end

          def resource_template_list(cursor: nil, tracking_progress: false)
            params = {}
            params = add_cursor(params, cursor)
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_RESOURCES_TEMPLATES_LIST,
              params: params
            }.tap { |body| body.delete(:params) if params.empty? }
          end

          def resources_subscribe(uri:, tracking_progress: false)
            params = { uri: uri }
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_RESOURCES_SUBSCRIBE,
              params: params
            }
          end

          def resources_unsubscribe(uri:, tracking_progress: false)
            params = { uri: uri }
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_RESOURCES_UNSUBSCRIBE,
              params: params
            }
          end

          def prompt_list(cursor: nil, tracking_progress: false)
            params = {}
            params = add_cursor(params, cursor)
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_PROMPTS_LIST,
              params: params
            }.tap { |body| body.delete(:params) if params.empty? }
          end

          def prompt_call(name:, arguments: {}, tracking_progress: false)
            params = {
              name: name,
              arguments: arguments
            }
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_PROMPTS_GET,
              params: params
            }
          end

          def completion_resource(uri:, argument:, value:, context: nil, tracking_progress: false)
            params = {
              ref: {
                type: REF_TYPE_RESOURCE,
                uri: uri
              },
              argument: {
                name: argument,
                value: value
              },
              context: format_completion_context(context)
            }.compact
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_COMPLETION_COMPLETE,
              params: params
            }
          end

          def completion_prompt(name:, argument:, value:, context: nil, tracking_progress: false)
            params = {
              ref: {
                type: REF_TYPE_PROMPT,
                name: name
              },
              argument: {
                name: argument,
                value: value
              },
              context: format_completion_context(context)
            }.compact
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_COMPLETION_COMPLETE,
              params: params
            }
          end

          def logging_set_level(level:, tracking_progress: false)
            params = { level: level }
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_LOGGING_SET_LEVEL,
              params: params
            }
          end

          def tasks_list(cursor: nil, tracking_progress: false)
            params = {}
            params = add_cursor(params, cursor)
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_TASKS_LIST,
              params: params
            }.tap { |body| body.delete(:params) if params.empty? }
          end

          def task_get(task_id:, tracking_progress: false)
            params = { taskId: task_id }
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_TASKS_GET,
              params: params
            }
          end

          def task_result(task_id:, tracking_progress: false)
            params = { taskId: task_id }
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_TASKS_RESULT,
              params: params
            }
          end

          def task_cancel(task_id:, tracking_progress: false)
            params = { taskId: task_id }
            params = add_progress_token(params, tracking_progress: tracking_progress)

            {
              jsonrpc: JSONRPC_VERSION,
              id: generate_id,
              method: METHOD_TASKS_CANCEL,
              params: params
            }
          end
        end
      end
    end
  end
end
