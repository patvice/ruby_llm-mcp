# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      # Native MCP protocol client implementation
      # This is the core protocol implementation that handles all MCP operations
      # It's self-contained and could potentially be extracted as a separate gem
      class Client
        attr_reader :name, :transport_type, :config, :capabilities, :protocol_version, :elicitation_callback,
                    :sampling_callback

        def initialize( # rubocop:disable Metrics/ParameterLists
          name:,
          transport_type:,
          transport_config: {},
          human_in_the_loop_callback: nil,
          roots_callback: nil,
          logging_enabled: false,
          logging_level: nil,
          elicitation_enabled: false,
          elicitation_callback: nil,
          progress_tracking_enabled: false,
          sampling_callback: nil,
          notification_callback: nil,
          protocol_version: nil,
          request_timeout: nil
        )
          @name = name
          @transport_type = transport_type
          @config = transport_config.merge(request_timeout: request_timeout || MCP.config.request_timeout)
          @protocol_version = protocol_version || MCP.config.protocol_version || Native::Protocol.default_negotiated_version

          # Callbacks
          @human_in_the_loop_callback = human_in_the_loop_callback
          @roots_callback = roots_callback
          @logging_enabled = logging_enabled
          @logging_level = logging_level
          @elicitation_enabled = elicitation_enabled
          @elicitation_callback = elicitation_callback
          @progress_tracking_enabled = progress_tracking_enabled
          @sampling_callback = sampling_callback
          @notification_callback = notification_callback

          @transport = nil
          @capabilities = nil
        end

        def request(body, **options)
          transport.request(body, **options)
        rescue RubyLLM::MCP::Errors::TimeoutError => e
          if transport&.alive? && !e.request_id.nil?
            cancelled_notification(reason: "Request timed out", request_id: e.request_id)
          end
          raise e
        end

        def process_result(result)
          if result.notification?
            process_notification(result)
            return nil
          end

          if result.request?
            process_request(result) if alive?
            return nil
          end

          if result.response?
            return result
          end

          nil
        end

        def start
          return unless capabilities.nil?

          transport.start

          initialize_response = initialize_request
          initialize_response.raise_error! if initialize_response.error?

          # Extract and store the negotiated protocol version
          negotiated_version = initialize_response.value["protocolVersion"]

          if negotiated_version && !Native::Protocol.supported_version?(negotiated_version)
            raise Errors::UnsupportedProtocolVersion.new(
              message: <<~MESSAGE
                Unsupported protocol version, and could not negotiate a supported version: #{negotiated_version}.
                Supported versions: #{Native::Protocol.supported_versions.join(', ')}
              MESSAGE
            )
          end

          @protocol_version = negotiated_version if negotiated_version

          # Set the protocol version on the transport for subsequent requests
          if @transport.respond_to?(:set_protocol_version)
            @transport.set_protocol_version(@protocol_version)
          end

          @capabilities = RubyLLM::MCP::ServerCapabilities.new(initialize_response.value["capabilities"])
          initialize_notification

          if @logging_enabled && @logging_level
            set_logging(level: @logging_level)
          end
        end

        def stop
          @transport&.close
          @capabilities = nil
          @transport = nil
          @protocol_version = Native::Protocol.default_negotiated_version
        end

        def restart!
          @initialize_response = nil
          stop
          start
        end

        def alive?
          !!@transport&.alive?
        end

        def ping
          ping_request = Native::Requests::Ping.new(self)
          if alive?
            result = ping_request.call
          else
            transport.start

            result = ping_request.call
            @transport = nil
          end

          result.value == {}
        rescue RubyLLM::MCP::Errors::TimeoutError, RubyLLM::MCP::Errors::TransportError
          false
        end

        def process_notification(result)
          notification = result.notification
          @notification_callback&.call(notification)
        end

        def process_request(result)
          Native::ResponseHandler.new(self).execute(result)
        end

        def initialize_request
          Native::Requests::Initialization.new(self).call
        end

        def tool_list(cursor: nil)
          result = Native::Requests::ToolList.new(self, cursor: cursor).call
          result.raise_error! if result.error?

          if result.next_cursor?
            result.value["tools"] + tool_list(cursor: result.next_cursor)
          else
            result.value["tools"]
          end
        end

        def execute_tool(name:, parameters:)
          if @human_in_the_loop_callback && !@human_in_the_loop_callback.call(name, parameters)
            result = Result.new(
              {
                "result" => {
                  "isError" => true,
                  "content" => [{ "type" => "text", "text" => "Tool call was cancelled by the client" }]
                }
              }
            )
            return result
          end

          Native::Requests::ToolCall.new(self, name: name, parameters: parameters).call
        end

        def resource_list(cursor: nil)
          result = Native::Requests::ResourceList.new(self, cursor: cursor).call
          result.raise_error! if result.error?

          if result.next_cursor?
            result.value["resources"] + resource_list(cursor: result.next_cursor)
          else
            result.value["resources"]
          end
        end

        def resource_read(uri:)
          Native::Requests::ResourceRead.new(self, uri: uri).call
        end

        def resource_template_list(cursor: nil)
          result = Native::Requests::ResourceTemplateList.new(self, cursor: cursor).call
          result.raise_error! if result.error?

          if result.next_cursor?
            result.value["resourceTemplates"] + resource_template_list(cursor: result.next_cursor)
          else
            result.value["resourceTemplates"]
          end
        end

        def resources_subscribe(uri:)
          Native::Requests::ResourcesSubscribe.new(self, uri: uri).call
        end

        def prompt_list(cursor: nil)
          result = Native::Requests::PromptList.new(self, cursor: cursor).call
          result.raise_error! if result.error?

          if result.next_cursor?
            result.value["prompts"] + prompt_list(cursor: result.next_cursor)
          else
            result.value["prompts"]
          end
        end

        def execute_prompt(name:, arguments:)
          Native::Requests::PromptCall.new(self, name: name, arguments: arguments).call
        end

        def completion_resource(uri:, argument:, value:, context: nil)
          Native::Requests::CompletionResource.new(self, uri: uri, argument: argument, value: value,
                                                         context: context).call
        end

        def completion_prompt(name:, argument:, value:, context: nil)
          Native::Requests::CompletionPrompt.new(self, name: name, argument: argument, value: value,
                                                       context: context).call
        end

        def set_logging(level:)
          Native::Requests::LoggingSetLevel.new(self, level: level).call
        end

        def set_progress_tracking(enabled:)
          @progress_tracking_enabled = enabled
        end

        ## Notifications
        #
        def initialize_notification
          Native::Notifications::Initialize.new(self).call
        end

        def cancelled_notification(reason:, request_id:)
          Native::Notifications::Cancelled.new(self, reason: reason, request_id: request_id).call
        end

        def roots_list_change_notification
          Native::Notifications::RootsListChange.new(self).call
        end

        ## Responses
        #
        def ping_response(id:)
          Native::Responses::Ping.new(self, id: id).call
        end

        def roots_list_response(id:)
          Native::Responses::RootsList.new(self, id: id).call
        end

        def sampling_create_message_response(id:, model:, message:, **options)
          Native::Responses::SamplingCreateMessage.new(self, id: id, model: model, message: message,
                                                             **options).call
        end

        def error_response(id:, message:, code: -32_000)
          Native::Responses::Error.new(self, id: id, message: message, code: code).call
        end

        def elicitation_response(id:, elicitation:)
          Native::Responses::Elicitation.new(self, id: id, elicitation: elicitation).call
        end

        def client_capabilities
          capabilities_hash = {}

          if @roots_callback&.call&.any?
            capabilities_hash[:roots] = {
              listChanged: true
            }
          end

          if MCP.config.sampling.enabled?
            capabilities_hash[:sampling] = {}
          end

          if @elicitation_enabled
            capabilities_hash[:elicitation] = {}
          end

          capabilities_hash
        end

        def roots_paths
          @roots_callback&.call || []
        end

        def tracking_progress?
          @progress_tracking_enabled
        end

        def sampling_callback_enabled?
          !@sampling_callback.nil?
        end

        def transport
          @transport ||= Native::Transport.new(@transport_type, self, config: @config)
        end
      end
    end
  end
end
