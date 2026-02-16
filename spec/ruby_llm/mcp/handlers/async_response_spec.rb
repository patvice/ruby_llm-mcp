# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Handlers::AsyncResponse do
  let(:elicitation_id) { "test-elicit-123" }

  describe "initialization" do
    it "starts in pending state" do
      response = described_class.new(elicitation_id: elicitation_id)
      expect(response.state).to eq(:pending)
      expect(response).to be_pending
    end

    it "stores elicitation_id" do
      response = described_class.new(elicitation_id: elicitation_id)
      expect(response.elicitation_id).to eq(elicitation_id)
    end
  end

  describe "#complete" do
    it "transitions to completed state" do
      response = described_class.new(elicitation_id: elicitation_id)
      response.complete({ "data" => "value" })

      expect(response.state).to eq(:completed)
      expect(response).to be_completed
      expect(response.result).to eq({ "data" => "value" })
    end

    it "executes completion callbacks" do
      response = described_class.new(elicitation_id: elicitation_id)
      callback_called = false
      callback_state = nil
      callback_data = nil

      response.on_complete do |state, data|
        callback_called = true
        callback_state = state
        callback_data = data
      end

      response.complete({ "test" => "data" })

      # Give callback thread time to execute
      sleep 0.1

      expect(callback_called).to be true
      expect(callback_state).to eq(:completed)
      expect(callback_data).to eq({ "test" => "data" })
    end

    it "cannot transition from completed state" do
      response = described_class.new(elicitation_id: elicitation_id)
      response.complete({ "data" => "value" })

      expect(response).to be_completed

      # Try to change state
      response.reject("reason")

      # Should still be completed
      expect(response).to be_completed
      expect(response.result).to eq({ "data" => "value" })
    end
  end

  describe "#reject" do
    it "transitions to rejected state" do
      response = described_class.new(elicitation_id: elicitation_id)
      response.reject("Validation failed")

      expect(response.state).to eq(:rejected)
      expect(response).to be_rejected
      expect(response.error).to eq("Validation failed")
    end

    it "executes completion callbacks" do
      response = described_class.new(elicitation_id: elicitation_id)
      callback_state = nil

      response.on_complete { |state, _data| callback_state = state }
      response.reject("Error")

      sleep 0.1
      expect(callback_state).to eq(:rejected)
    end
  end

  describe "#cancel" do
    it "transitions to cancelled state" do
      response = described_class.new(elicitation_id: elicitation_id)
      response.cancel("User cancelled")

      expect(response.state).to eq(:cancelled)
      expect(response).to be_cancelled
      expect(response.error).to eq("User cancelled")
    end
  end

  describe "#timeout!" do
    it "transitions to timed_out state" do
      response = described_class.new(elicitation_id: elicitation_id)
      response.timeout!

      expect(response.state).to eq(:timed_out)
      expect(response).to be_timed_out
      expect(response.error).to eq("Operation timed out")
    end
  end

  describe "timeout handling" do
    it "automatically times out after timeout period" do
      response = described_class.new(elicitation_id: elicitation_id, timeout: 0.1)

      expect(response).to be_pending
      sleep 0.2

      expect(response).to be_timed_out
    end

    it "does not timeout if completed before timeout" do
      response = described_class.new(elicitation_id: elicitation_id, timeout: 1)
      response.complete({ "data" => "value" })

      sleep 1.1
      expect(response).to be_completed
      expect(response).not_to be_timed_out
    end
  end

  describe "#finished?" do
    it "returns false when pending" do
      response = described_class.new(elicitation_id: elicitation_id)
      expect(response).to be_pending
      expect(response.finished?).to be false
    end

    it "returns true when completed" do
      response = described_class.new(elicitation_id: elicitation_id)
      response.complete({ "data" => "value" })
      expect(response.finished?).to be true
    end

    it "returns true when rejected" do
      response = described_class.new(elicitation_id: elicitation_id)
      response.reject("error")
      expect(response.finished?).to be true
    end
  end

  describe "thread safety" do
    it "handles concurrent state transitions safely" do
      response = described_class.new(elicitation_id: elicitation_id)

      threads = 10.times.map do |i|
        Thread.new do
          if i.even?
            response.complete({ "thread" => i })
          else
            response.reject("thread #{i}")
          end
        end
      end

      threads.each(&:join)

      # Should have transitioned to one of the states
      expect(response.finished?).to be true
    end
  end
end
