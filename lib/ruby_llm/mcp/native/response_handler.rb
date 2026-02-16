# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      class ResponseHandler
        attr_reader :coordinator

        def initialize(coordinator)
          @coordinator = coordinator
        end

        def execute(result)
          operation = CancellableOperation.new(result.id)
          coordinator.register_in_flight_request(result.id, operation)
          is_deferred = false

          begin
            # Execute in a separate thread that can be terminated on cancellation
            operation.execute do
              handled, deferred = dispatch_request(result)
              is_deferred = deferred
              handled
            end
          rescue Errors::RequestCancelled => e
            RubyLLM::MCP.logger.info("Request #{result.id} was cancelled: #{e.message}")
            # Don't send response - cancellation means result is unused
            # Clean up if this was a deferred elicitation
            Handlers::ElicitationRegistry.remove(result.id) if is_deferred
            true
          ensure
            # Only unregister if not deferred (async operations stay registered)
            coordinator.unregister_in_flight_request(result.id) unless is_deferred
          end
        end

        private

        def dispatch_request(result)
          case result.method
          when Native::Messages::METHOD_PING
            coordinator.ping_response(id: result.id)
            [true, false]
          when "roots/list"
            handle_roots_response(result)
            [true, false]
          when "sampling/createMessage"
            handle_sampling_response(result)
            [true, false]
          when "elicitation/create"
            [true, handle_elicitation_response(result)]
          when Native::Messages::METHOD_TASKS_LIST
            handle_tasks_list_response(result)
            [true, false]
          when Native::Messages::METHOD_TASKS_GET
            handle_task_get_response(result)
            [true, false]
          when Native::Messages::METHOD_TASKS_RESULT
            handle_task_result_response(result)
            [true, false]
          when Native::Messages::METHOD_TASKS_CANCEL
            handle_task_cancel_response(result)
            [true, false]
          else
            handle_unknown_request(result)
            RubyLLM::MCP.logger.error("MCP client was sent unknown method type and \
              could not respond: #{result.inspect}.")
            [false, false]
          end
        end

        def handle_roots_response(result)
          RubyLLM::MCP.logger.info("Roots request: #{result.inspect}")
          roots_paths = coordinator.roots_paths
          if roots_paths&.any?
            coordinator.roots_list_response(id: result.id)
          else
            coordinator.error_response(
              id: result.id,
              message: "Roots are not enabled",
              code: Native::JsonRpc::ErrorCodes::SERVER_ERROR
            )
          end
        rescue StandardError => e
          RubyLLM::MCP.logger.error("Error in roots request: #{e.message}\n#{e.backtrace.join("\n")}")
          coordinator.error_response(
            id: result.id,
            message: "Internal error processing roots request",
            code: Native::JsonRpc::ErrorCodes::INTERNAL_ERROR,
            data: { detail: e.message }
          )
        end

        def handle_sampling_response(result)
          unless MCP.config.sampling.enabled?
            RubyLLM::MCP.logger.info("Sampling is disabled, yet server requested sampling")
            coordinator.error_response(
              id: result.id,
              message: "Sampling is disabled",
              code: Native::JsonRpc::ErrorCodes::SERVER_ERROR
            )
            return
          end

          RubyLLM::MCP.logger.info("Sampling request: #{result.inspect}")
          Sample.new(result, coordinator).execute
        rescue StandardError => e
          RubyLLM::MCP.logger.error("Error in sampling request: #{e.message}\n#{e.backtrace.join("\n")}")
          coordinator.error_response(
            id: result.id,
            message: "Internal error processing sampling request",
            code: Native::JsonRpc::ErrorCodes::INTERNAL_ERROR,
            data: { detail: e.message }
          )
        end

        def handle_elicitation_response(result)
          RubyLLM::MCP.logger.info("Elicitation request: #{result.inspect}")
          elicitation = Elicitation.new(coordinator, result)
          elicitation.execute

          # Return true if this elicitation is deferred (async)
          elicitation.instance_variable_get(:@deferred)
        rescue StandardError => e
          RubyLLM::MCP.logger.error("Error in elicitation request: #{e.message}\n#{e.backtrace.join("\n")}")
          coordinator.error_response(
            id: result.id,
            message: "Internal error processing elicitation request",
            code: Native::JsonRpc::ErrorCodes::INTERNAL_ERROR,
            data: { detail: e.message }
          )
          false
        end

        def handle_unknown_request(result)
          coordinator.error_response(
            id: result.id,
            message: "Method not found: #{result.method}",
            code: Native::JsonRpc::ErrorCodes::METHOD_NOT_FOUND
          )
        end

        def handle_tasks_list_response(result)
          coordinator.result_response(
            id: result.id,
            value: { tasks: coordinator.task_registry.tasks }
          )
        end

        def handle_task_get_response(result)
          task_id = result.params["taskId"]
          return error_invalid_task_id(result.id) if task_id.nil? || task_id.empty?

          task = coordinator.task_registry.task(task_id)
          if task.nil?
            error_unknown_task(result.id, task_id)
          else
            coordinator.result_response(id: result.id, value: task)
          end
        end

        def handle_task_result_response(result)
          task_id = result.params["taskId"]
          return error_invalid_task_id(result.id) if task_id.nil? || task_id.empty?

          payload = coordinator.task_registry.payload(task_id)
          if payload.nil?
            error_unknown_task(result.id, task_id)
          else
            coordinator.result_response(id: result.id, value: payload)
          end
        end

        def handle_task_cancel_response(result)
          task_id = result.params["taskId"]
          return error_invalid_task_id(result.id) if task_id.nil? || task_id.empty?

          task = coordinator.task_registry.update_status(
            task_id,
            status: "cancelled",
            status_message: "Cancelled by server request"
          )

          coordinator.result_response(
            id: result.id,
            value: task || build_missing_task(task_id, "cancelled", "Task not found; treated as cancelled")
          )
        end

        def error_invalid_task_id(request_id)
          coordinator.error_response(
            id: request_id,
            message: "Invalid task request: taskId is required",
            code: Native::JsonRpc::ErrorCodes::INVALID_PARAMS
          )
        end

        def error_unknown_task(request_id, task_id)
          coordinator.error_response(
            id: request_id,
            message: "Task not found: #{task_id}",
            code: Native::JsonRpc::ErrorCodes::INVALID_PARAMS
          )
        end

        def build_missing_task(task_id, status, status_message)
          timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
          {
            "taskId" => task_id,
            "status" => status,
            "statusMessage" => status_message,
            "createdAt" => timestamp,
            "lastUpdatedAt" => timestamp,
            "ttl" => 0
          }
        end
      end
    end
  end
end
