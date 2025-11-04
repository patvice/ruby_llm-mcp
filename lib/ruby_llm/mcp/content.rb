# frozen_string_literal: true

module RubyLLM
  module MCP
    class Content < RubyLLM::Content
      attr_reader :text, :attachments, :content

      def initialize(text: nil, attachments: nil) # rubocop:disable Lint/MissingSuper
        @text = text
        @attachments = []

        # Handle MCP::Attachment objects directly without processing
        if attachments.is_a?(Array) && attachments.all? { |a| a.is_a?(MCP::Attachment) }
          @attachments = attachments
        elsif attachments
          # Let parent class process other types of attachments
          process_attachments(attachments)
        end
      end

      # This is a workaround to allow the content object to be passed as the tool call
      # to return audio or image attachments.
      def to_s
        text.to_s
      end
    end
  end
end
