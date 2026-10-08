# frozen_string_literal: true

module RubyLLM
  module MCP
    content_class = defined?(RubyLLM::Content) ? RubyLLM::Content : Object
    class Content < content_class
      attr_reader :text, :attachments, :content

      def initialize(text: nil, attachments: nil) # rubocop:disable Lint/MissingSuper
        @text = text
        @attachments = []

        # Handle MCP::Attachment objects directly without processing
        if attachments.is_a?(Array) && attachments.all? { |a| a.is_a?(MCP::Attachment) }
          @attachments = attachments
        elsif attachments && defined?(RubyLLM::Content)
          # Let parent class process other types of attachments
          process_attachments(attachments)
        elsif attachments
          @attachments = RubyLLM::Attachment.wrap(attachments)
        end
      end

      # This is a workaround to allow the content object to be passed as the tool call
      # to return audio or image attachments.
      def to_s
        text.to_s
      end

      def to_ruby_llm
        if defined?(RubyLLM::Content)
          self
        elsif attachments.empty?
          text.to_s
        else
          [text, *attachments].compact
        end
      end

      def message_options
        if defined?(RubyLLM::Content)
          { content: self }
        else
          { content: text, attachments: attachments }
        end
      end
    end
  end
end
