# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      # Native MCP protocol client implementation
      # This is the core protocol implementation that handles all MCP operations
      # It's self-contained and could potentially be extracted as a separate gem
      class Client
        TOOL_CALL_CANCELLED_MESSAGE = "Tool call was cancelled by the client"

        attr_reader :name, :transport_type, :config, :capabilities, :protocol_version, :elicitation_callback,
                    :sampling_callback, :human_in_the_loop_registry, :registry_owner_id, :task_registry

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
          extensions_capabilities: nil,
          protocol_version: nil,
          request_timeout: nil
        )
          @name = name
          @transport_type = transport_type
          @config = transport_config.merge(request_timeout: request_timeout || MCP.config.request_timeout)
          @requested_protocol_version = protocol_version || MCP.config.protocol_version || Native::Protocol.latest_version
          @protocol_version = @requested_protocol_version
          @extensions_capabilities = extensions_capabilities || {}

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
          @task_registry = Native::TaskRegistry.new

          # Track in-flight server-initiated requests for cancellation
          @in_flight_requests = {}
          @in_flight_mutex = Mutex.new

          # Human-in-the-loop approvals are scoped per client lifecycle.
          @registry_owner_id = "native-client-#{SecureRandom.uuid}"
          @human_in_the_loop_registry = Handlers::HumanInTheLoopRegistry.for_owner(@registry_owner_id)
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
          @task_registry = Native::TaskRegistry.new
          @protocol_version = @requested_protocol_version || MCP.config.protocol_version || Native::Protocol.latest_version
          Handlers::HumanInTheLoopRegistry.release(@registry_owner_id)
          @human_in_the_loop_registry = Handlers::HumanInTheLoopRegistry.for_owner(@registry_owner_id)
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
          if @human_in_the_loop_callback
            approved = evaluate_tool_approval(name: name, parameters: parameters)
            return create_cancelled_result unless approved
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

        def resources_unsubscribe(uri:)
          body = Native::Messages::Requests.resources_unsubscribe(uri: uri, tracking_progress: tracking_progress?)
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

        def tasks_list(cursor: nil)
          body = Native::Messages::Requests.tasks_list(cursor: cursor, tracking_progress: tracking_progress?)
          result = request(body)
          result.raise_error! if result.error?

          task_registry.upsert_many(result.value["tasks"])

          if result.next_cursor?
            result.value["tasks"] + tasks_list(cursor: result.next_cursor)
          else
            result.value["tasks"] || []
          end
        end

        def task_get(task_id:)
          body = Native::Messages::Requests.task_get(task_id: task_id, tracking_progress: tracking_progress?)
          result = request(body)
          result.raise_error! if result.error?

          task_registry.upsert(result.value)
          result
        end

        def task_result(task_id:)
          body = Native::Messages::Requests.task_result(task_id: task_id, tracking_progress: tracking_progress?)
          result = request(body)
          result.raise_error! if result.error?

          task_registry.store_payload(task_id, result.value)
          result
        end

        def task_cancel(task_id:)
          body = Native::Messages::Requests.task_cancel(task_id: task_id, tracking_progress: tracking_progress?)
          result = request(body)
          result.raise_error! if result.error?

          task_registry.upsert(result.value)
          result
        end

        def task_status_notification(task:)
          task_registry.upsert(task)
        end

        def set_progress_tracking(enabled:)
          @progress_tracking_enabled = enabled
        end

        def set_elicitation_enabled(enabled:)
          @elicitation_enabled = enabled
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

        def result_response(id:, value:)
          body = Native::Messages::Responses.result(id: id, value: value)
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
            sampling_capabilities = {}
            sampling_capabilities[:tools] = {} if MCP.config.sampling.tools
            sampling_capabilities[:context] = {} if MCP.config.sampling.context
            capabilities_hash[:sampling] = sampling_capabilities
          end

          if @elicitation_enabled
            elicitation_capabilities = {}
            elicitation_capabilities[:form] = {} if MCP.config.elicitation.form
            elicitation_capabilities[:url] = {} if MCP.config.elicitation.url
            capabilities_hash[:elicitation] = elicitation_capabilities unless elicitation_capabilities.empty?
          end

          if MCP.config.respond_to?(:tasks) && MCP.config.tasks.enabled?
            capabilities_hash[:tasks] = {
              list: {},
              cancel: {}
            }
          end

          if @extensions_capabilities.any? && Native::Protocol.extensions_supported?(@protocol_version)
            capabilities_hash[:extensions] = @extensions_capabilities
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

        # Register a server-initiated request that can be cancelled
        # @param request_id [String] The ID of the request
        # @param cancellable_operation [CancellableOperation, nil] The operation that can be cancelled
        def register_in_flight_request(request_id, cancellable_operation = nil)
          @in_flight_mutex.synchronize do
            @in_flight_requests[request_id.to_s] = cancellable_operation
          end
        end

        # Unregister a completed or cancelled request
        # @param request_id [String] The ID of the request
        def unregister_in_flight_request(request_id)
          @in_flight_mutex.synchronize do
            @in_flight_requests.delete(request_id.to_s)
          end
        end

        # Cancel an in-flight server-initiated request
        # @param request_id [String] The ID of the request to cancel
        # @return [Symbol] cancellation outcome
        #   :cancelled, :already_cancelled, :already_completed, :not_found, :not_cancellable, :failed
        def cancel_in_flight_request(request_id)
          operation = nil
          @in_flight_mutex.synchronize do
            operation = @in_flight_requests[request_id.to_s]
          end

          unless operation
            RubyLLM::MCP.logger.debug("Request #{request_id} was not found for cancellation")
            return :not_found
          end

          unless operation.respond_to?(:cancel)
            RubyLLM::MCP.logger.warn("Request #{request_id} cannot be cancelled or was already completed")
            return :not_cancellable
          end

          outcome = normalize_cancellation_outcome(operation.cancel)
          if %i[cancelled already_cancelled already_completed].include?(outcome)
            unregister_in_flight_request(request_id)
          end

          outcome
        end

        private

        def evaluate_tool_approval(name:, parameters:)
          decision = @human_in_the_loop_callback.call(name, parameters)
          unless decision.is_a?(Handlers::ApprovalDecision)
            RubyLLM::MCP.logger.error(
              "Human-in-the-loop callback must return ApprovalDecision, got #{decision.class}"
            )
            return false
          end

          return true if decision.approved?
          return false if decision.denied?
          return wait_for_deferred_approval(decision) if decision.deferred?

          RubyLLM::MCP.logger.error(
            "Human-in-the-loop callback returned unknown decision status '#{decision.status.inspect}'"
          )
          false
        rescue Errors::InvalidApprovalDecision => e
          RubyLLM::MCP.logger.error("Invalid approval decision: #{e.message}")
          false
        rescue StandardError => e
          RubyLLM::MCP.logger.error("Error evaluating tool approval: #{e.message}")
          false
        end

        def wait_for_deferred_approval(decision)
          unless decision.promise
            RubyLLM::MCP.logger.error("Deferred approval #{decision.approval_id} missing promise")
            return false
          end

          approved = decision.promise.wait(timeout: decision.timeout)
          approved == true
        rescue Timeout::Error
          RubyLLM::MCP.logger.warn(
            "Deferred approval #{decision.approval_id} timed out after #{decision.timeout} seconds"
          )
          human_in_the_loop_registry.deny(
            decision.approval_id,
            reason: "Timed out waiting for approval"
          )
          false
        rescue StandardError => e
          RubyLLM::MCP.logger.error("Deferred approval #{decision.approval_id} failed: #{e.message}")
          false
        end

        def normalize_cancellation_outcome(raw_outcome)
          case raw_outcome
          when Symbol
            raw_outcome
          when true
            :cancelled
          else
            :failed
          end
        end

        # Create a result for cancelled tool execution
        def create_cancelled_result
          Result.new(
            {
              "result" => {
                "isError" => true,
                "content" => [{ "type" => "text", "text" => TOOL_CALL_CANCELLED_MESSAGE }]
              }
            }
          )
        end
      end
    end
  end
end
