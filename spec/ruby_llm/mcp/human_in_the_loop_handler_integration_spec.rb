# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Human-in-the-Loop Handler Integration" do # rubocop:disable RSpec/DescribeClass
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
    it "returns structured approved/denied decisions" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
        def execute
          tool_name.start_with?("read") ? approve : deny("Only read operations allowed")
        end
      end

      handler = handler_class.new(
        tool_name: "read_file",
        parameters: { path: "test.txt" },
        approval_id: "approval-1",
        coordinator: coordinator
      )
      result = handler.call
      expect(result).to eq({ status: :approved })

      handler = handler_class.new(
        tool_name: "delete_file",
        parameters: { path: "test.txt" },
        approval_id: "approval-2",
        coordinator: coordinator
      )
      result = handler.call
      expect(result).to eq({ status: :denied, reason: "Only read operations allowed" })
    end

    it "uses guards to produce denied decisions" do
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

      handler = handler_class.new(
        tool_name: "read_file",
        parameters: { path: "relative/test.txt" },
        approval_id: "approval-1",
        coordinator: coordinator
      )
      result = handler.call
      expect(result).to eq({ status: :approved })

      handler = handler_class.new(
        tool_name: "read_file",
        parameters: { path: "/absolute/test.txt" },
        approval_id: "approval-2",
        coordinator: coordinator
      )
      result = handler.call
      expect(result).to eq({ status: :denied, reason: "Absolute paths require approval" })
    end
  end

  describe "async handler usage" do
    it "returns structured deferred decisions" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
        async_execution timeout: 30

        def execute
          defer
        end
      end

      handler = handler_class.new(
        tool_name: "execute_command",
        parameters: { command: "rm -rf /" },
        approval_id: "approval-dangerous",
        coordinator: coordinator
      )

      result = handler.call
      expect(result).to eq({ status: :deferred, timeout: 30 })
    end

    it "can be approved via registry" do
      approval_id = "approval-registry-test"
      promise = RubyLLM::MCP::Handlers::Promise.new

      RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.store(
        approval_id,
        {
          promise: promise,
          timeout: 300,
          tool_name: "test_tool",
          parameters: {}
        }
      )

      RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.approve(approval_id)

      sleep 0.1
      expect(promise.fulfilled?).to be true
      expect(promise.value).to be true
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

      RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.deny(
        approval_id,
        reason: "Too dangerous"
      )

      sleep 0.1
      expect(promise.fulfilled?).to be true
      expect(promise.value).to be false
      expect(RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.size).to eq(0)
    end
  end
end
