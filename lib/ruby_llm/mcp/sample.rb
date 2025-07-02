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

        def to_request
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
        return unless callback_guard_success?

        chat_message = chat
        @coordinator.sampling_create_message_response(
          id: @id, message: chat_message, model: prefered_model
        )
      end

      def message
        @message ||= raw_messages.map { |message| message.fetch("content")&.fetch("text") }.join("\n")
      end

      private

      def callback_guard_success?
        return true unless @coordinator.client.sampling_callback_enabled?

        unless @coordinator.client.on[:sampling].call(self)
          @coordinator.error_response(id: @id, message: REJECTED_MESSAGE)
          return false
        end

        true
      rescue StandardError => e
        RubyLLM::MCP.logger.error("Error in callback guard: #{e.message}, #{e.backtrace.join("\n")}")
        @coordinator.error_response(id: @id, message: "Error executing sampling request")
        false
      end

      def chat
        chat = RubyLLM::Chat.new(
          model: prefered_model
        )
        if system_prompt
          formated_system_message = create_message(system_message)
          chat.add_message(formated_system_message)
        end
        raw_messages.each { |message| chat.add_message(create_message(message)) }

        chat.complete
      end

      def prefered_model
        @prefered_model ||= begin
          model = RubyLLM::MCP.config.sampling.prefered_model
          if model.respond_to?(:call)
            model.call(model_preferences.hints)
          else
            model
          end
        end
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
