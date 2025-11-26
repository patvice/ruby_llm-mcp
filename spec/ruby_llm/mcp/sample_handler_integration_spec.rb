# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sample Handler Integration" do
  let(:coordinator) do
    double(
      "Coordinator",
      sampling_callback_enabled?: true,
      sampling_create_message_response: true,
      error_response: true
    )
  end

  let(:result) do
    RubyLLM::MCP::Result.new(
      {
        "id" => "sample-123",
        "params" => {
          "messages" => [
            {
              "role" => "user",
              "content" => { "type" => "text", "text" => "Hello, how are you?" }
            }
          ],
          "model" => "gpt-4",
          "systemPrompt" => "You are helpful",
          "maxTokens" => 100
        }
      }
    )
  end

  describe "handler class usage" do
    it "executes custom handler class" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::SamplingHandler) do
        def execute
          accept("Custom response")
        end
      end

      allow(coordinator).to receive(:sampling_callback).and_return(handler_class)

      sample = RubyLLM::MCP::Sample.new(result, coordinator)

      expect(coordinator).to receive(:sampling_create_message_response).with(
        hash_including(id: "sample-123", message: "Custom response")
      )

      sample.execute
    end

    it "executes handler with options" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::SamplingHandler) do
        option :custom_model

        def execute
          accept("Response from #{options[:custom_model]}")
        end
      end

      handler_with_options = ->(sample) do
        handler_class.new(sample: sample, coordinator: coordinator, custom_model: "claude-3").call
      end

      allow(coordinator).to receive(:sampling_callback).and_return(handler_with_options)

      sample = RubyLLM::MCP::Sample.new(result, coordinator)

      expect(coordinator).to receive(:sampling_create_message_response).with(
        hash_including(message: "Response from claude-3")
      )

      sample.execute
    end

    it "executes handler with hooks" do
      before_called = false
      after_called = false

      handler_class = Class.new(RubyLLM::MCP::Handlers::SamplingHandler) do
        before_execute { before_called = true }
        after_execute { |result| after_called = result[:accepted] }

        define_method(:execute) do
          accept("Response")
        end
      end

      allow(coordinator).to receive(:sampling_callback).and_return(handler_class)

      sample = RubyLLM::MCP::Sample.new(result, coordinator)
      sample.execute

      expect(before_called).to be true
      expect(after_called).to be true
    end

    it "executes handler with guards" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::SamplingHandler) do
        guard :check_message_length

        def execute
          accept("Response")
        end

        def check_message_length
          return true if sample.message.length < 100
          "Message too long"
        end
      end

      allow(coordinator).to receive(:sampling_callback).and_return(handler_class)

      sample = RubyLLM::MCP::Sample.new(result, coordinator)

      # Guard should pass
      expect(coordinator).to receive(:sampling_create_message_response)
      sample.execute
    end

    it "rejects when guard fails" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::SamplingHandler) do
        guard :always_fail

        def execute
          accept("Response")
        end

        def always_fail
          "Guard failed"
        end
      end

      allow(coordinator).to receive(:sampling_callback).and_return(handler_class)

      sample = RubyLLM::MCP::Sample.new(result, coordinator)

      # Should send error response
      expect(coordinator).to receive(:error_response).with(
        hash_including(message: "Guard failed")
      )
      sample.execute
    end
  end

  describe "backward compatibility with blocks" do
    it "still works with block-based callbacks" do
      block_callback = ->(sample) { sample.message.length < 100 }

      allow(coordinator).to receive(:sampling_callback).and_return(block_callback)
      allow(coordinator).to receive(:sampling_callback_enabled?).and_return(true)
      allow(RubyLLM::MCP.config.sampling).to receive(:preferred_model).and_return("gpt-4")

      sample = RubyLLM::MCP::Sample.new(result, coordinator)

      # Mock chat completion
      chat = double("Chat")
      allow(RubyLLM::Chat).to receive(:new).and_return(chat)
      allow(chat).to receive(:add_message)
      allow(chat).to receive(:complete).and_return("Chat response")

      expect(coordinator).to receive(:sampling_create_message_response).with(
        hash_including(message: "Chat response", model: "gpt-4")
      )

      sample.execute
    end
  end

end
