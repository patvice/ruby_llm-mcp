# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Handlers::Concerns::ApprovalActions do
  let(:handler_class) do
    Class.new do
      include RubyLLM::MCP::Handlers::Concerns::Lifecycle
      include RubyLLM::MCP::Handlers::Concerns::ApprovalActions

      def initialize(tool_name:, parameters:, approval_id:)
        @tool_name = tool_name
        @parameters = parameters
        @approval_id = approval_id
      end
    end
  end

  let(:tool_name) { "delete_file" }
  let(:parameters) { { path: "/tmp/test.txt" } }
  let(:approval_id) { "approval-123" }

  describe "attributes" do
    it "provides access to tool_name, parameters, and approval_id" do
      handler_class_with_execute = Class.new(handler_class) do
        def execute
          { tool: tool_name, params: parameters, id: approval_id }
        end
      end

      handler = handler_class_with_execute.new(
        tool_name: tool_name,
        parameters: parameters,
        approval_id: approval_id
      )

      result = handler.call

      expect(result[:tool]).to eq(tool_name)
      expect(result[:params]).to eq(parameters)
      expect(result[:id]).to eq(approval_id)
    end
  end

  describe "#approve" do
    it "returns approval hash" do
      handler_class_with_approve = Class.new(handler_class) do
        def execute
          approve
        end
      end

      handler = handler_class_with_approve.new(
        tool_name: tool_name,
        parameters: parameters,
        approval_id: approval_id
      )

      result = handler.call
      expect(result).to eq({ approved: true })
    end
  end

  describe "#deny" do
    it "returns denial hash with default reason" do
      handler_class_with_deny = Class.new(handler_class) do
        def execute
          deny
        end
      end

      handler = handler_class_with_deny.new(
        tool_name: tool_name,
        parameters: parameters,
        approval_id: approval_id
      )

      result = handler.call
      expect(result).to eq({ approved: false, reason: "Denied by user" })
    end

    it "returns denial hash with custom reason" do
      handler_class_with_custom_deny = Class.new(handler_class) do
        def execute
          deny("Tool is too dangerous")
        end
      end

      handler = handler_class_with_custom_deny.new(
        tool_name: tool_name,
        parameters: parameters,
        approval_id: approval_id
      )

      result = handler.call
      expect(result).to eq({ approved: false, reason: "Tool is too dangerous" })
    end
  end

  describe "#guard_failed" do
    it "returns denial when guard fails" do
      handler_with_guard = Class.new do
        include RubyLLM::MCP::Handlers::Concerns::Lifecycle
        include RubyLLM::MCP::Handlers::Concerns::GuardChecks
        include RubyLLM::MCP::Handlers::Concerns::ApprovalActions

        guard :check_safety

        def initialize(tool_name:, parameters:, approval_id:)
          @tool_name = tool_name
          @parameters = parameters
          @approval_id = approval_id
        end

        def execute
          approve
        end

        def check_safety
          "Tool not allowed"
        end
      end

      handler = handler_with_guard.new(
        tool_name: tool_name,
        parameters: parameters,
        approval_id: approval_id
      )

      result = handler.call
      expect(result).to eq({ approved: false, reason: "Tool not allowed" })
    end
  end
end
