# frozen_string_literal: true

# Builds the RubyLLM::Chat that the adapter specs drive.
#
# RubyLLM 2.0 tightened two things these specs relied on. Both are about the
# fixtures rather than about this gem:
#
#   * A bare model ID now resolves to a provider through the registry, and
#     "claude-sonnet-4" resolves to vertexai, which the suite does not
#     configure. The provider is already known here, so it is passed
#     explicitly rather than inferred.
#
#   * "gemini-2.0-flash" has been retired from the registry. Every request in
#     these specs is replayed from a cassette, so the registry lookup buys
#     nothing — skipping it also stops a future retirement from breaking the
#     suite.
#
# OpenAI additionally defaults to the Responses API in 2.0, while the committed
# cassettes were recorded against Chat Completions. Pinning the protocol keeps
# them valid. To cover the 2.0 default instead, re-record with
# VCR_REFRESH=true and drop the pin.
module ChatBuilder
  module_function

  def build(model_config)
    options = {
      model: model_config[:model],
      provider: model_config[:provider],
      assume_model_exists: true
    }
    options[:protocol] = :chat_completions if model_config[:provider] == :openai

    RubyLLM.chat(**options)
  end
end
