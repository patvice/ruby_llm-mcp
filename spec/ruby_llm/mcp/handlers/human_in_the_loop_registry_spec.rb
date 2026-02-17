# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Handlers::HumanInTheLoopRegistry do
  let(:approval_id) { "approval-123" }
  let(:promise) { RubyLLM::MCP::Handlers::Promise.new }
  let(:approval_context) do
    {
      promise: promise,
      timeout: 300,
      tool_name: "delete_file",
      parameters: { path: "/tmp/test.txt" }
    }
  end

  before do
    described_class.clear
  end

  after do
    described_class.clear
  end

  describe ".store and .retrieve" do
    it "stores and retrieves approval context" do
      described_class.store(approval_id, approval_context)
      retrieved = described_class.retrieve(approval_id)

      expect(retrieved).to eq(approval_context)
    end

    it "returns nil for unknown id" do
      retrieved = described_class.retrieve("unknown-id")
      expect(retrieved).to be_nil
    end
  end

  describe ".remove" do
    it "removes approval from registry" do
      described_class.store(approval_id, approval_context)
      removed = described_class.remove(approval_id)

      expect(removed).to eq(approval_context)
      expect(described_class.retrieve(approval_id)).to be_nil
    end

    it "returns nil for unknown id" do
      removed = described_class.remove("unknown-id")
      expect(removed).to be_nil
    end
  end

  describe ".approve" do
    it "approves stored request" do
      described_class.store(approval_id, approval_context)

      described_class.approve(approval_id)

      # Promise should be resolved with true
      sleep 0.1 # Give thread time to execute
      expect(promise.fulfilled?).to be true
      expect(promise.value).to be true

      # Should be removed after approval
      expect(described_class.retrieve(approval_id)).to be_nil
    end

    it "logs warning for unknown approval" do
      expect(RubyLLM::MCP.logger).to receive(:warn).with(/unknown approval/)
      described_class.approve("unknown-id")
    end
  end

  describe ".deny" do
    it "denies stored request" do
      described_class.store(approval_id, approval_context)

      described_class.deny(approval_id, reason: "Too dangerous")

      # Promise should be resolved with false
      sleep 0.1
      expect(promise.fulfilled?).to be true
      expect(promise.value).to be false

      # Should be removed after denial
      expect(described_class.retrieve(approval_id)).to be_nil
    end

    it "logs warning for unknown approval" do
      expect(RubyLLM::MCP.logger).to receive(:warn).with(/unknown approval/)
      described_class.deny("unknown-id")
    end
  end

  describe ".clear" do
    it "removes all approvals" do
      described_class.store("id1", approval_context)
      described_class.store("id2", approval_context)

      expect(described_class.size).to eq(2)

      described_class.clear

      expect(described_class.size).to eq(0)
    end
  end

  describe ".size" do
    it "returns number of pending approvals" do
      expect(described_class.size).to eq(0)

      described_class.store("id1", approval_context)
      expect(described_class.size).to eq(1)

      described_class.store("id2", approval_context)
      expect(described_class.size).to eq(2)

      described_class.remove("id1")
      expect(described_class.size).to eq(1)
    end
  end

  describe "timeout handling" do
    it "automatically times out approval after timeout period" do
      context_with_timeout = approval_context.merge(timeout: 0.1)

      described_class.store(approval_id, context_with_timeout)

      expect(described_class.size).to eq(1)
      sleep 0.5 # Give extra time for timeout thread to execute and cleanup

      # Should be removed after timeout
      expect(described_class.size).to eq(0)

      # Promise should be resolved with false
      expect(promise.fulfilled?).to be true
      expect(promise.value).to be false
    end

    it "cancels timeout when approval is manually approved" do
      context_with_timeout = approval_context.merge(timeout: 1)

      described_class.store(approval_id, context_with_timeout)
      described_class.approve(approval_id)

      sleep 1.1

      # Should still be fulfilled (not timed out)
      expect(promise.fulfilled?).to be true
      expect(promise.value).to be true
    end
  end

  describe "concurrent access" do
    it "handles concurrent store/retrieve operations" do
      threads = 10.times.map do |i|
        Thread.new do
          context = approval_context.merge(tool_name: "tool_#{i}")
          described_class.store("id-#{i}", context)
          described_class.retrieve("id-#{i}")
        end
      end

      threads.each(&:join)

      expect(described_class.size).to eq(10)
    end

    it "handles concurrent approve operations" do
      10.times do |i|
        promise = RubyLLM::MCP::Handlers::Promise.new
        context = approval_context.merge(promise: promise)
        described_class.store("id-#{i}", context)
      end

      threads = 10.times.map do |i|
        Thread.new do
          described_class.approve("id-#{i}")
        end
      end

      threads.each(&:join)

      expect(described_class.size).to eq(0)
    end
  end

  describe "client-scoped registries" do
    it "routes approvals by id across multiple owner registries" do
      owner_a = described_class.for_owner("owner-a")
      owner_b = described_class.for_owner("owner-b")
      promise_a = RubyLLM::MCP::Handlers::Promise.new
      promise_b = RubyLLM::MCP::Handlers::Promise.new

      owner_a.store("owner-a:approval-1", approval_context.merge(promise: promise_a))
      owner_b.store("owner-b:approval-1", approval_context.merge(promise: promise_b))

      described_class.approve("owner-a:approval-1")
      described_class.deny("owner-b:approval-1")

      sleep 0.1
      expect(promise_a.value).to be true
      expect(promise_b.value).to be false
    end

    it "releases scoped registries on demand" do
      owner = described_class.for_owner("owner-release")
      owner.store("owner-release:approval-1", approval_context)

      expect(described_class.size).to be >= 1
      described_class.release("owner-release")
      expect(described_class.retrieve("owner-release:approval-1")).to be_nil
    end
  end
end
