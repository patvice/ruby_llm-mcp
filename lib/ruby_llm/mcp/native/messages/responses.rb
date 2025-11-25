# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Messages
        # Response message builders
        # Responses are sent in reply to requests from the server
        module Responses
          extend Helpers

          module_function

          def ping(id:)
            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              result: {}
            }
          end

          def roots_list(id:, roots_paths:)
            roots_response = roots_paths.map do |path|
              {
                uri: "file://#{path}",
                name: File.basename(path, ".*")
              }
            end

            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              result: {
                roots: roots_response
              }
            }
          end

          def sampling_create_message(id:, message:, model:)
            stop_reason = if message.respond_to?(:stop_reason) && message.stop_reason
                            snake_to_camel(message.stop_reason)
                          else
                            "endTurn"
                          end

            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              result: {
                role: message.role,
                content: format_content(message.content),
                model: model,
                stopReason: stop_reason
              }
            }
          end

          def elicitation(id:, action:, content: nil)
            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              result: {
                action: action,
                content: content
              }.compact
            }
          end

          def error(id:, message:, code: JsonRpc::ErrorCodes::SERVER_ERROR, data: nil)
            error_object = {
              code: code,
              message: message
            }
            error_object[:data] = data if data

            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              error: error_object
            }
          end

          def format_content(content)
            if content.is_a?(RubyLLM::Content)
              if content.text.none? && content.attachments.any?
                attachment = content.attachments.first
                { type: attachment.type, data: attachment.content, mime_type: attachment.mime_type }
              else
                { type: "text", text: content.text }
              end
            else
              { type: "text", text: content }
            end
          end
          private_class_method :format_content

          def snake_to_camel(str)
            parts = str.split("_")
            parts.first + parts[1..].map(&:capitalize).join
          end
          private_class_method :snake_to_camel
        end
      end
    end
  end
end
