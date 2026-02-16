# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Handlers::ApprovalDecision do
  describe ".from_handler_result" do
    it "parses approved decisions" do
      decision = described_class.from_handler_result(
        { status: :approved },
        approval_id: "approval-1"
      )

      expect(decision).to be_approved
    end

    it "parses denied decisions with reason" do
      decision = described_class.from_handler_result(
        { status: :denied, reason: "dangerous tool" },
        approval_id: "approval-1"
      )

      expect(decision).to be_denied
      expect(decision.reason).to eq("dangerous tool")
    end

    it "parses deferred decisions and keeps timeout" do
      decision = described_class.from_handler_result(
        { status: :deferred, timeout: 12 },
        approval_id: "approval-1"
      )

      expect(decision).to be_deferred
      expect(decision.approval_id).to eq("approval-1")
      expect(decision.timeout).to eq(12.0)
    end

    it "rejects non-hash returns" do
      expect do
        described_class.from_handler_result(true, approval_id: "approval-1")
      end.to raise_error(RubyLLM::MCP::Errors::InvalidApprovalDecision, /must return a Hash/)
    end

    it "rejects deferred decisions without timeout" do
      expect do
        described_class.from_handler_result({ status: :deferred }, approval_id: "approval-1")
      end.to raise_error(RubyLLM::MCP::Errors::InvalidApprovalDecision, /require a positive timeout/)
    end
  end
end
