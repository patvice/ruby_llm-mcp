# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Human-in-the-Loop Handler Integration" do
  let(:coordinator) do
    double(
      "Coordinator",
      native_client: double("NativeClient")
    )
  end

  before do
    RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.clear
  end

  after do
    RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.clear
  end

  describe "sync handler usage" do
    it "approves with custom handler class" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
        def execute
          # Auto-approve read operations
          tool_name.start_with?("read") ? approve : deny("Only read operations allowed")
        end
      end

      # Test approval
      handler = handler_class.new(
        tool_name: "read_file",
        parameters: { path: "test.txt" },
        approval_id: "approval-1",
        coordinator: coordinator
      )
      result = handler.call
      expect(result[:approved]).to be true

      # Test denial
      handler = handler_class.new(
        tool_name: "delete_file",
        parameters: { path: "test.txt" },
        approval_id: "approval-2",
        coordinator: coordinator
      )
      result = handler.call
      expect(result[:approved]).to be false
      expect(result[:reason]).to include("Only read operations allowed")
    end

    it "uses guards to filter requests" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
        guard :check_safe_path

        def execute
          approve
        end

        def check_safe_path
          return true unless parameters[:path]
          return true unless parameters[:path].start_with?("/")

          "Absolute paths require approval"
        end
      end

      # Relative path should pass guard
      handler = handler_class.new(
        tool_name: "read_file",
        parameters: { path: "relative/test.txt" },
        approval_id: "approval-1",
        coordinator: coordinator
      )
      result = handler.call
      expect(result[:approved]).to be true

      # Absolute path should fail guard
      handler = handler_class.new(
        tool_name: "read_file",
        parameters: { path: "/absolute/test.txt" },
        approval_id: "approval-2",
        coordinator: coordinator
      )
      result = handler.call
      expect(result[:approved]).to be false
      expect(result[:reason]).to include("Absolute paths")
    end
  end

  describe "async handler with promise" do
    it "handles promise-based async approval" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
        def execute
          promise = create_promise

          # Simulate async approval
          Thread.new do
            sleep 0.1
            promise.resolve(true)
          end

          promise
        end
      end

      handler = handler_class.new(
        tool_name: "execute_command",
        parameters: { command: "ls" },
        approval_id: "approval-1",
        coordinator: coordinator
      )

      result = handler.call
      expect(result).to be_a(RubyLLM::MCP::Handlers::Promise)

      # Wait for resolution
      approved = result.wait
      expect(approved).to be true
    end
  end

  describe "async handler with :pending" do
    it "stores in registry for later completion" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
        async_execution

        def execute
          :pending
        end
      end

      handler = handler_class.new(
        tool_name: "execute_command",
        parameters: { command: "rm -rf /" },
        approval_id: "approval-dangerous",
        coordinator: coordinator
      )

      # Should return pending
      result = handler.call
      expect(result).to eq(:pending)
    end

    it "can be approved via registry" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
        async_execution

        def execute
          :pending
        end
      end

      approval_id = "approval-registry-test"
      promise = RubyLLM::MCP::Handlers::Promise.new

      # Manually store in registry (normally done by adapter)
      RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.store(
        approval_id,
        {
          promise: promise,
          timeout: 300,
          tool_name: "test_tool",
          parameters: {}
        }
      )

      # Approve via registry (simulating external approval)
      RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.approve(approval_id)

      # Promise should be resolved
      sleep 0.1
      expect(promise.fulfilled?).to be true
      expect(promise.value).to be true

      # Should be removed from registry
      expect(RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.size).to eq(0)
    end

    it "can be denied via registry" do
      approval_id = "approval-deny-test"
      promise = RubyLLM::MCP::Handlers::Promise.new

      RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.store(
        approval_id,
        {
          promise: promise,
          timeout: 300,
          tool_name: "dangerous_tool",
          parameters: {}
        }
      )

      # Deny via registry
      RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.deny(
        approval_id,
        reason: "Too dangerous"
      )

      # Promise should be resolved with false
      sleep 0.1
      expect(promise.fulfilled?).to be true
      expect(promise.value).to be false

      # Should be removed from registry
      expect(RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.size).to eq(0)
    end
  end

  describe "backward compatibility with blocks" do
    it "still works with block-based callbacks" do
      # Simulate block-based callback
      block_callback = lambda do |name, params|
        name == "safe_tool" && params[:safe] == true
      end

      # Test approval
      result = block_callback.call("safe_tool", { safe: true })
      expect(result).to be true

      # Test denial
      result = block_callback.call("dangerous_tool", { safe: false })
      expect(result).to be false
    end
  end
end
