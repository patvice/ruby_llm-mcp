# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Elicitation Handler Integration" do
  let(:coordinator) do
    double(
      "Coordinator",
      elicitation_callback: nil,
      elicitation_response: true
    )
  end

  let(:result) do
    RubyLLM::MCP::Result.new(
      {
        "id" => "elicit-123",
        "params" => {
          "message" => "Please confirm your choice",
          "requestedSchema" => {
            "type" => "object",
            "properties" => {
              "confirmed" => { "type" => "boolean" }
            },
            "required" => ["confirmed"]
          }
        }
      }
    )
  end

  before do
    RubyLLM::MCP::Handlers::ElicitationRegistry.clear
  end

  after do
    RubyLLM::MCP::Handlers::ElicitationRegistry.clear
  end

  describe "sync handler class usage" do
    it "accepts with structured response" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        def execute
          accept({ "confirmed" => true })
        end
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)

      expect(coordinator).to receive(:elicitation_response).with(
        hash_including(
          id: "elicit-123",
          elicitation: hash_including(action: "accept", content: { "confirmed" => true })
        )
      )

      elicitation.execute
    end

    it "rejects elicitation" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        def execute
          reject("User declined")
        end
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)

      expect(coordinator).to receive(:elicitation_response).with(
        hash_including(
          elicitation: hash_including(action: "reject")
        )
      )

      elicitation.execute
    end

    it "cancels with invalid response" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        def execute
          # Invalid - missing required field
          accept({ "wrong_field" => true })
        end
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)

      expect(coordinator).to receive(:elicitation_response).with(
        hash_including(
          elicitation: hash_including(action: "cancel")
        )
      )

      elicitation.execute
    end
  end

  describe "async handler with promise" do
    it "handles promise-based async completion" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        def execute
          promise = create_promise

          # Simulate async resolution
          Thread.new do
            sleep 0.1
            promise.resolve({ "confirmed" => true })
          end

          promise
        end
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)

      # Should not respond immediately
      expect(coordinator).not_to receive(:elicitation_response)
      elicitation.execute

      # Registry should have stored it
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(1)

      # Wait for async completion
      sleep 0.2

      # Should have responded after promise resolution
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
    end
  end

  describe "async handler with :pending" do
    it "stores in registry for later completion" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        async_execution

        def execute
          :pending
        end
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)

      # Should not respond immediately
      expect(coordinator).not_to receive(:elicitation_response)
      elicitation.execute

      # Should be stored in registry
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(1)
      stored = RubyLLM::MCP::Handlers::ElicitationRegistry.retrieve("elicit-123")
      expect(stored).to eq(elicitation)
    end

    it "can be completed via registry" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        async_execution

        def execute
          :pending
        end
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)
      elicitation.execute

      # Complete via registry (simulating websocket response)
      expect(coordinator).to receive(:elicitation_response).with(
        hash_including(
          id: "elicit-123",
          elicitation: hash_including(action: "accept", content: { "confirmed" => true })
        )
      )

      RubyLLM::MCP::Handlers::ElicitationRegistry.complete(
        "elicit-123",
        response: { "confirmed" => true }
      )

      # Should be removed from registry
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
    end

    it "can be cancelled via registry" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        async_execution

        def execute
          :pending
        end
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)
      elicitation.execute

      # Cancel via registry
      expect(coordinator).to receive(:elicitation_response).with(
        hash_including(
          id: "elicit-123",
          elicitation: hash_including(action: "cancel")
        )
      )

      RubyLLM::MCP::Handlers::ElicitationRegistry.cancel(
        "elicit-123",
        reason: "User cancelled"
      )

      # Should be removed from registry
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
    end
  end

  describe "async handler with AsyncResponse" do
    it "handles AsyncResponse object" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        async_execution timeout: 60

        def execute
          async_resp = defer

          # Simulate async completion
          Thread.new do
            sleep 0.1
            async_resp.complete({ "confirmed" => true })
          end

          async_resp
        end
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)

      expect(coordinator).not_to receive(:elicitation_response)
      elicitation.execute

      # Wait for async completion
      sleep 0.2

      # Should have been removed from registry
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
    end
  end

  describe "backward compatibility with blocks" do
    it "still works with block-based callbacks" do
      block_callback = lambda do |elicitation|
        elicitation.structured_response = { "confirmed" => true }
        true
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(block_callback)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)

      expect(coordinator).to receive(:elicitation_response).with(
        hash_including(
          elicitation: hash_including(action: "accept", content: { "confirmed" => true })
        )
      )

      elicitation.execute
    end
  end

  describe "timeout handling" do
    it "handles timeout in async handlers" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        async_execution timeout: 0.1

        def execute
          :pending
        end
      end

      allow(coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)
      elicitation.execute

      # Should be stored initially
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(1)

      # Wait for timeout
      sleep 0.2

      # Should be removed after timeout
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
    end
  end
end
