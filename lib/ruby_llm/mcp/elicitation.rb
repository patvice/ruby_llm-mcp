# frozen_string_literal: true

module RubyLLM
  module MCP
    class Elicitation
      ACCEPT_ACTION = "accept"
      CANCEL_ACTION = "cancel"
      REJECT_ACTION = "reject"

      attr_writer :structured_response

      def initialize(coordinator, result)
        @coordinator = coordinator
        @result = result

        @message = @result.params["message"]
        @requested_schema = @result.params["requestedSchema"]
      end

      def execute
        success = @coordinator.client.on[:elicitation].call(self)
        if success
          valid = validate_response
          if valid
            @coordinator.elicitation_response(@id, action: ACCEPT_ACTION, content: @structured_response)
          else
            @coordinator.elicitation_response(@id, action: CANCEL_ACTION, content: nil)
          end
        else
          @coordinator.elicitation_response(@id, action: REJECT_ACTION, content: nil)
        end
      end

      def validate_response
        JSON::Validator.validate(@requested_schema, @structured_response)
      end
    end
  end
end
