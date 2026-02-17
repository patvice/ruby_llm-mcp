# frozen_string_literal: true

module RubyLLM
  module MCP
    class NotificationHandler
      attr_reader :client

      def initialize(client)
        @client = client
      end

      def execute(notification)
        case notification.type
        when "notifications/tools/list_changed"
          client.reset_tools!
        when "notifications/resources/list_changed"
          client.reset_resources!
        when "notifications/resources/updated"
          process_resource_updated(notification)
        when "notifications/prompts/list_changed"
          client.reset_prompts!
        when "notifications/message"
          process_logging_message(notification)
        when "notifications/progress"
          process_progress_message(notification)
        when "notifications/cancelled"
          process_cancelled_notification(notification)
        when "notifications/tasks/status"
          process_task_status_notification(notification)
        when "notifications/elicitation/complete"
          process_elicitation_complete_notification(notification)
        else
          process_unknown_notification(notification)
        end
      end

      private

      def process_resource_updated(notification)
        uri = notification.params["uri"]
        resource = client.resources.find { |r| r.uri == uri }
        resource&.reset_content!
      end

      def process_logging_message(notification)
        if client.logging_handler_enabled?
          client.on[:logging].call(notification)
        else
          default_process_logging_message(notification)
        end
      end

      def process_progress_message(notification)
        if client.tracking_progress?
          progress_obj = RubyLLM::MCP::Progress.new(self, client.on[:progress], notification.params)
          progress_obj.execute_progress_handler
        end
      end

      def default_process_logging_message(notification, logger: RubyLLM::MCP.logger)
        level = notification.params["level"]
        logger_message = notification.params["logger"]
        message = notification.params["data"]

        message = "#{logger_message}: #{message}"

        case level
        when "debug"
          logger.debug(message["message"])
        when "info", "notice"
          logger.info(message["message"])
        when "warning"
          logger.warn(message["message"])
        when "error", "critical"
          logger.error(message["message"])
        when "alert", "emergency"
          logger.fatal(message["message"])
        end
      end

      def process_cancelled_notification(notification)
        request_id = notification.params["requestId"]
        reason = notification.params["reason"] || "No reason provided"

        RubyLLM::MCP.logger.info(
          "Received cancellation for request #{request_id}: #{reason}"
        )

        outcome = client.cancel_in_flight_request(request_id)

        case outcome
        when :cancelled, :already_cancelled, :already_completed
          RubyLLM::MCP.logger.debug("Cancellation outcome for #{request_id}: #{outcome}")
        when :not_found
          RubyLLM::MCP.logger.debug("Request #{request_id} was not found or already completed")
        when :not_cancellable
          RubyLLM::MCP.logger.warn("Request #{request_id} is not cancellable")
        else
          RubyLLM::MCP.logger.warn("Cancellation for #{request_id} returned unexpected outcome: #{outcome.inspect}")
        end
      end

      def process_unknown_notification(notification)
        message = "Unknown notification type: #{notification.type} params: #{notification.params.to_h}"
        RubyLLM::MCP.logger.error(message)
      end

      def process_task_status_notification(notification)
        return unless client.adapter.respond_to?(:task_status_notification)

        client.adapter.task_status_notification(task: notification.params)
      end

      def process_elicitation_complete_notification(notification)
        elicitation_id = notification.params["elicitationId"]
        return if elicitation_id.nil?

        Handlers::ElicitationRegistry.remove(elicitation_id)
      end
    end
  end
end
