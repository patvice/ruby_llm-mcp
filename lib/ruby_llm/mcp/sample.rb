# frozen_string_literal: true

module RubyLLM
  module MCP
    class Sample
      class Hint
        attr_reader :model, :cost_priority, :speed_priority, :intelligence_priority

        def initialize(model, model_preferences)
          @model = model
          @model_preferences = model_preferences

          @hints = model_preferences&.fetch("hints", [])
          @cost_priority = model_preferences&.fetch("costPriority", nil)
          @speed_priority = model_preferences&.fetch("speedPriority", nil)
          @intelligence_priority = model_preferences&.fetch("intelligencePriority", nil)
        end

        def hints
          @hints.map { |hint| hint["name"] }
        end

        def to_h
          {
            model: model,
            hints: hints,
            cost_priority: @cost_priority,
            speed_priority: @speed_priority,
            intelligence_priority: @intelligence_priority
          }
        end
      end

      REJECTED_MESSAGE = "Sampling request was rejected"

      attr_reader :model_preferences, :system_prompt, :max_tokens, :raw_messages

      def initialize(result, coordinator)
        params = result.params
        @id = result.id
        @coordinator = coordinator

        @raw_messages = params["messages"] || []
        @model_preferences = Hint.new(params["model"], params["modelPreferences"])
        @system_prompt = params["systemPrompt"]
        @max_tokens = params["maxTokens"]
      end

      def execute
        # Check if handler is a class or block
        handler = @coordinator.sampling_callback

        if Handlers.handler_class?(handler)
          execute_with_handler_class(handler)
        else
          execute_with_block
        end
      end

      def message
        @message ||= raw_messages.map { |message| message.fetch("content")&.fetch("text") }.join("\n")
      end

      def to_h
        {
          id: @id,
          model_preferences: @model_preferences.to_h,
          system_prompt: @system_prompt,
          max_tokens: @max_tokens
        }
      end

      alias to_json to_h

      private

      # Execute using handler class
      def execute_with_handler_class(handler_class)
        handler_instance = handler_class.new(
          sample: self,
          coordinator: @coordinator
        )

        result = handler_instance.call

        # Handle different return types
        case result
        when Hash
          handle_handler_hash_result(result)
        when TrueClass, FalseClass
          handle_handler_boolean_result(result)
        else
          # Unexpected return type
          RubyLLM::MCP.logger.error("Handler returned unexpected type: #{result.class}")
          @coordinator.error_response(id: @id, message: "Internal error in sampling handler")
        end
      rescue StandardError => e
        RubyLLM::MCP.logger.error("Error in sampling handler: #{e.message}\n#{e.backtrace.join("\n")}")
        @coordinator.error_response(id: @id, message: "Error executing sampling request: #{e.message}")
      end

      # Handle hash result from handler
      def handle_handler_hash_result(result)
        if result[:accepted] == false
          @coordinator.error_response(id: @id, message: result[:message] || REJECTED_MESSAGE)
        elsif result[:accepted] == true && result[:response]
          # Handler provided the response directly
          model = preferred_model
          return unless model

          @coordinator.sampling_create_message_response(
            id: @id, message: result[:response], model: model
          )
        else
          # Invalid hash structure
          @coordinator.error_response(id: @id, message: "Invalid handler response")
        end
      end

      # Handle boolean result from handler
      def handle_handler_boolean_result(result)
        unless result
          @coordinator.error_response(id: @id, message: REJECTED_MESSAGE)
          return
        end

        model = preferred_model
        return unless model

        chat_message = chat(model)
        @coordinator.sampling_create_message_response(
          id: @id, message: chat_message, model: model
        )
      end

      # Execute using block (legacy/backward compatible)
      def execute_with_block
        return unless callback_guard_success?

        model = preferred_model
        return unless model

        chat_message = chat(model)
        @coordinator.sampling_create_message_response(
          id: @id, message: chat_message, model: model
        )
      end

      def callback_guard_success?
        return true unless @coordinator.sampling_callback_enabled?

        callback_result = @coordinator.sampling_callback&.call(self)
        # If callback returns nil, it means no guard was configured - allow it
        return true if callback_result.nil?

        unless callback_result
          @coordinator.error_response(id: @id, message: REJECTED_MESSAGE)
          return false
        end

        true
      rescue StandardError => e
        RubyLLM::MCP.logger.error("Error in callback guard: #{e.message}, #{e.backtrace.join("\n")}")
        @coordinator.error_response(id: @id, message: "Error executing sampling request")
        false
      end

      def chat(model)
        chat = RubyLLM::Chat.new(
          model: model
        )
        if system_prompt
          formated_system_message = create_message(system_message)
          chat.add_message(formated_system_message)
        end
        raw_messages.each { |message| chat.add_message(create_message(message)) }

        chat.complete
      end

      def preferred_model
        @preferred_model ||= begin
          model = RubyLLM::MCP.config.sampling.preferred_model
          if model.respond_to?(:call)
            model.call(model_preferences)
          else
            model
          end
        end
      rescue StandardError => e
        RubyLLM::MCP.logger.error("Error in preferred model: #{e.message}, #{e.backtrace.join("\n")}")
        @coordinator.error_response(id: @id, message: "Failed to determine preferred model: #{e.message}")
        false
      end

      def create_message(message)
        role = message["role"]
        content = create_content_for_message(message["content"])

        RubyLLM::Message.new({ role: role, content: content })
      end

      def create_content_for_message(content)
        case content["type"]
        when "text"
          MCP::Content.new(text: content["text"])
        when "image", "audio"
          attachment = MCP::Attachment.new(content["data"], content["mimeType"])
          MCP::Content.new(text: nil, attachments: [attachment])
        else
          raise RubyLLM::MCP::Errors::InvalidFormatError.new(message: "Invalid content type: #{content['type']}")
        end
      end

      def system_message
        {
          "role" => "system",
          "content" => { "type" => "text", "text" => system_prompt }
        }
      end
    end
  end
end
