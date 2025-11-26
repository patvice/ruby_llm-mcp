# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Handlers::ElicitationRegistry do
  let(:elicitation_id) { "test-elicit-123" }
  let(:coordinator) { double("Coordinator") }
  let(:elicitation) do
    double(
      "Elicitation",
      id: elicitation_id,
      message: "Test message",
      timeout: nil,
      complete: true,
      cancel_async: true,
      timeout!: true
    )
  end

  before do
    described_class.clear
  end

  after do
    described_class.clear
  end

  describe ".store and .retrieve" do
    it "stores and retrieves elicitation" do
      described_class.store(elicitation_id, elicitation)
      retrieved = described_class.retrieve(elicitation_id)

      expect(retrieved).to eq(elicitation)
    end

    it "returns nil for unknown id" do
      retrieved = described_class.retrieve("unknown-id")
      expect(retrieved).to be_nil
    end
  end

  describe ".remove" do
    it "removes elicitation from registry" do
      described_class.store(elicitation_id, elicitation)
      removed = described_class.remove(elicitation_id)

      expect(removed).to eq(elicitation)
      expect(described_class.retrieve(elicitation_id)).to be_nil
    end

    it "returns nil for unknown id" do
      removed = described_class.remove("unknown-id")
      expect(removed).to be_nil
    end
  end

  describe ".complete" do
    it "completes stored elicitation with response" do
      described_class.store(elicitation_id, elicitation)

      expect(elicitation).to receive(:complete).with({ "data" => "value" })
      described_class.complete(elicitation_id, response: { "data" => "value" })

      # Should be removed after completion
      expect(described_class.retrieve(elicitation_id)).to be_nil
    end

    it "logs warning for unknown elicitation" do
      expect(RubyLLM::MCP.logger).to receive(:warn).with(/unknown elicitation/)
      described_class.complete("unknown-id", response: {})
    end
  end

  describe ".cancel" do
    it "cancels stored elicitation" do
      described_class.store(elicitation_id, elicitation)

      expect(elicitation).to receive(:cancel_async).with("Test reason")
      described_class.cancel(elicitation_id, reason: "Test reason")

      # Should be removed after cancellation
      expect(described_class.retrieve(elicitation_id)).to be_nil
    end

    it "logs warning for unknown elicitation" do
      expect(RubyLLM::MCP.logger).to receive(:warn).with(/unknown elicitation/)
      described_class.cancel("unknown-id")
    end
  end

  describe ".clear" do
    it "removes all elicitations" do
      described_class.store("id1", elicitation)
      described_class.store("id2", elicitation)

      expect(described_class.size).to eq(2)

      described_class.clear

      expect(described_class.size).to eq(0)
    end
  end

  describe ".size" do
    it "returns number of pending elicitations" do
      expect(described_class.size).to eq(0)

      described_class.store("id1", elicitation)
      expect(described_class.size).to eq(1)

      described_class.store("id2", elicitation)
      expect(described_class.size).to eq(2)

      described_class.remove("id1")
      expect(described_class.size).to eq(1)
    end
  end

  describe "timeout handling" do
    xit "automatically times out elicitation after timeout period" do
      elicitation_with_timeout = double(
        "Elicitation",
        id: elicitation_id,
        timeout: 0.1,
        timeout!: true
      )

      expect(elicitation_with_timeout).to receive(:timeout!)

      described_class.store(elicitation_id, elicitation_with_timeout)

      sleep 0.5 # Give extra time for timeout thread to execute and cleanup

      # Should be removed after timeout
      expect(described_class.retrieve(elicitation_id)).to be_nil
    end

    it "cancels timeout when elicitation is completed" do
      elicitation_with_timeout = double(
        "Elicitation",
        id: elicitation_id,
        timeout: 1,
        complete: true
      )

      # Timeout should not be called
      expect(elicitation_with_timeout).not_to receive(:timeout!)

      described_class.store(elicitation_id, elicitation_with_timeout)
      described_class.complete(elicitation_id, response: {})

      sleep 1.1
    end
  end

  describe "concurrent access" do
    it "handles concurrent store/retrieve operations" do
      threads = 10.times.map do |i|
        Thread.new do
          elicit = double("Elicitation", id: "id-#{i}", timeout: nil)
          described_class.store("id-#{i}", elicit)
          described_class.retrieve("id-#{i}")
        end
      end

      threads.each(&:join)

      expect(described_class.size).to eq(10)
    end

    it "handles concurrent complete operations" do
      10.times do |i|
        elicit = double("Elicitation", id: "id-#{i}", timeout: nil, complete: true)
        described_class.store("id-#{i}", elicit)
      end

      threads = 10.times.map do |i|
        Thread.new do
          described_class.complete("id-#{i}", response: {})
        end
      end

      threads.each(&:join)

      expect(described_class.size).to eq(0)
    end
  end
end
