# frozen_string_literal: true

module RubyLLM
  module MCP
    class NotificationHandler
      attr_reader :coordinator, :client

      def initialize(coordinator)
        @coordinator = coordinator
        @client = coordinator.client
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
          # TODO: - do nothing at the moment until we support client operations
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
        progress_obj = RubyLLM::MCP::Progress.new(self, client.on[:progress], notification.params)
        if client.tracking_progress?
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

      def process_unknown_notification(notification)
        message = "Unknown notification type: #{notification.type} params: #{notification.params.to_h}"
        RubyLLM::MCP.logger.error(message)
      end
    end
  end
end
