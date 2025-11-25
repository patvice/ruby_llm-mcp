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
          body = Native::Messages::Requests.ping(tracking_progress: tracking_progress?)
          if alive?
            result = request(body)
          else
            transport.start

            result = request(body)
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
          body = Native::Messages::Requests.initialize(
            protocol_version: protocol_version,
            capabilities: client_capabilities
          )
          request(body)
        end

        def tool_list(cursor: nil)
          body = Native::Messages::Requests.tool_list(cursor: cursor, tracking_progress: tracking_progress?)
          result = request(body)
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

          body = Native::Messages::Requests.tool_call(name: name, parameters: parameters,
                                                      tracking_progress: tracking_progress?)
          request(body)
        end

        def resource_list(cursor: nil)
          body = Native::Messages::Requests.resource_list(cursor: cursor, tracking_progress: tracking_progress?)
          result = request(body)
          result.raise_error! if result.error?

          if result.next_cursor?
            result.value["resources"] + resource_list(cursor: result.next_cursor)
          else
            result.value["resources"]
          end
        end

        def resource_read(uri:)
          body = Native::Messages::Requests.resource_read(uri: uri, tracking_progress: tracking_progress?)
          request(body)
        end

        def resource_template_list(cursor: nil)
          body = Native::Messages::Requests.resource_template_list(cursor: cursor,
                                                                   tracking_progress: tracking_progress?)
          result = request(body)
          result.raise_error! if result.error?

          if result.next_cursor?
            result.value["resourceTemplates"] + resource_template_list(cursor: result.next_cursor)
          else
            result.value["resourceTemplates"]
          end
        end

        def resources_subscribe(uri:)
          body = Native::Messages::Requests.resources_subscribe(uri: uri, tracking_progress: tracking_progress?)
          request(body, wait_for_response: false)
        end

        def prompt_list(cursor: nil)
          body = Native::Messages::Requests.prompt_list(cursor: cursor, tracking_progress: tracking_progress?)
          result = request(body)
          result.raise_error! if result.error?

          if result.next_cursor?
            result.value["prompts"] + prompt_list(cursor: result.next_cursor)
          else
            result.value["prompts"]
          end
        end

        def execute_prompt(name:, arguments:)
          body = Native::Messages::Requests.prompt_call(name: name, arguments: arguments,
                                                        tracking_progress: tracking_progress?)
          request(body)
        end

        def completion_resource(uri:, argument:, value:, context: nil)
          body = Native::Messages::Requests.completion_resource(uri: uri, argument: argument, value: value,
                                                                context: context, tracking_progress: tracking_progress?)
          request(body)
        end

        def completion_prompt(name:, argument:, value:, context: nil)
          body = Native::Messages::Requests.completion_prompt(name: name, argument: argument, value: value,
                                                              context: context, tracking_progress: tracking_progress?)
          request(body)
        end

        def set_logging(level:)
          body = Native::Messages::Requests.logging_set_level(level: level, tracking_progress: tracking_progress?)
          request(body)
        end

        def set_progress_tracking(enabled:)
          @progress_tracking_enabled = enabled
        end

        ## Notifications
        #
        def initialize_notification
          body = Native::Messages::Notifications.initialized
          request(body, wait_for_response: false)
        end

        def cancelled_notification(reason:, request_id:)
          body = Native::Messages::Notifications.cancelled(request_id: request_id, reason: reason)
          request(body, wait_for_response: false)
        end

        def roots_list_change_notification
          body = Native::Messages::Notifications.roots_list_changed
          request(body, wait_for_response: false)
        end

        ## Responses
        #
        def ping_response(id:)
          body = Native::Messages::Responses.ping(id: id)
          request(body, wait_for_response: false)
        end

        def roots_list_response(id:)
          body = Native::Messages::Responses.roots_list(id: id, roots_paths: roots_paths)
          request(body, wait_for_response: false)
        end

        def sampling_create_message_response(id:, model:, message:, **_options)
          body = Native::Messages::Responses.sampling_create_message(id: id, model: model, message: message)
          request(body, wait_for_response: false)
        end

        def error_response(id:, message:, code: Native::JsonRpc::ErrorCodes::SERVER_ERROR, data: nil)
          body = Native::Messages::Responses.error(id: id, message: message, code: code, data: data)
          request(body, wait_for_response: false)
        end

        def elicitation_response(id:, elicitation:)
          body = Native::Messages::Responses.elicitation(id: id, action: elicitation[:action],
                                                         content: elicitation[:content])
          request(body, wait_for_response: false)
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
