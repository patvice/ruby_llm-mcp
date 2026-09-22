# frozen_string_literal: true

module RubyLLM
  module MCP
    # Text and files returned by an MCP server, held together until they are
    # handed to RubyLLM.
    #
    # RubyLLM 2.0 removed RubyLLM::Content, which this used to subclass. That
    # class existed because a message's content could be either a String or a
    # text-plus-files object; 2.0 settled the question by making Message#content
    # a String and giving files their own +attachments+ argument. MCP still
    # returns the two together in one payload, so the pairing stays here and is
    # split at the boundary — see #to_message_arguments.
    class Content
      attr_reader :text, :attachments, :content

      def initialize(text: nil, attachments: nil)
        @text = text
        # Attachment.wrap handles the shapes this used to special-case: it
        # passes Attachment instances (including MCP::Attachment) straight
        # through, builds one from anything else, and drops blanks.
        @attachments = RubyLLM::Attachment.wrap(attachments)
      end

      # The RubyLLM::Message arguments for this content.
      #
      # Keeps every Message.new call site in the gem on one shape, so the
      # text/attachment split lives in a single place.
      def to_message_arguments
        { content: @text, attachments: @attachments }
      end

      # This is a workaround to allow the content object to be passed as the tool call
      # to return audio or image attachments.
      def to_s
        text.to_s
      end
    end
  end
end
