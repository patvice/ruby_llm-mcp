# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Handlers::Promise do
  describe "initialization" do
    it "starts in pending state" do
      promise = described_class.new
      expect(promise.state).to eq(:pending)
      expect(promise).to be_pending
    end
  end

  describe "#resolve" do
    it "transitions to fulfilled state with value" do
      promise = described_class.new
      promise.resolve("success value")

      expect(promise.state).to eq(:fulfilled)
      expect(promise).to be_fulfilled
      expect(promise.value).to eq("success value")
    end

    it "executes registered then callbacks" do
      promise = described_class.new
      callback_value = nil

      promise.then { |val| callback_value = val }
      promise.resolve("test value")

      sleep 0.1 # Give thread time to execute
      expect(callback_value).to eq("test value")
    end

    it "executes callback immediately if already fulfilled" do
      promise = described_class.new
      promise.resolve("already fulfilled")

      callback_value = nil
      promise.then { |val| callback_value = val }

      sleep 0.1
      expect(callback_value).to eq("already fulfilled")
    end

    it "cannot transition from fulfilled state" do
      promise = described_class.new
      promise.resolve("first value")
      promise.resolve("second value")

      expect(promise.value).to eq("first value")
    end
  end

  describe "#reject" do
    it "transitions to rejected state with reason" do
      promise = described_class.new
      promise.reject("error reason")

      expect(promise.state).to eq(:rejected)
      expect(promise).to be_rejected
      expect(promise.reason).to eq("error reason")
    end

    it "executes registered catch callbacks" do
      promise = described_class.new
      callback_reason = nil

      promise.catch { |reason| callback_reason = reason }
      promise.reject("test error")

      sleep 0.1
      expect(callback_reason).to eq("test error")
    end

    it "executes callback immediately if already rejected" do
      promise = described_class.new
      promise.reject("already rejected")

      callback_reason = nil
      promise.catch { |reason| callback_reason = reason }

      sleep 0.1
      expect(callback_reason).to eq("already rejected")
    end
  end

  describe "#then" do
    it "returns self for chaining" do
      promise = described_class.new
      result = promise.then { |val| val }
      expect(result).to eq(promise)
    end

    it "allows multiple then callbacks" do
      promise = described_class.new
      callback1_value = nil
      callback2_value = nil

      promise.then { |val| callback1_value = val }
      promise.then { |val| callback2_value = val }
      promise.resolve("value")

      sleep 0.1
      expect(callback1_value).to eq("value")
      expect(callback2_value).to eq("value")
    end
  end

  describe "#catch" do
    it "returns self for chaining" do
      promise = described_class.new
      result = promise.catch { |reason| reason }
      expect(result).to eq(promise)
    end

    it "allows multiple catch callbacks" do
      promise = described_class.new
      callback1_reason = nil
      callback2_reason = nil

      promise.catch { |reason| callback1_reason = reason }
      promise.catch { |reason| callback2_reason = reason }
      promise.reject("error")

      sleep 0.1
      expect(callback1_reason).to eq("error")
      expect(callback2_reason).to eq("error")
    end
  end

  describe "#wait" do
    it "waits for promise to fulfill and returns value" do
      promise = described_class.new

      Thread.new do
        sleep 0.1
        promise.resolve("async value")
      end

      result = promise.wait
      expect(result).to eq("async value")
    end

    it "raises error when promise is rejected" do
      promise = described_class.new
      promise.reject("error")

      expect { promise.wait }.to raise_error("error")
    end

    it "times out with timeout option" do
      promise = described_class.new

      expect do
        promise.wait(timeout: 0.1)
      end.to raise_error(Timeout::Error, /timed out/)
    end
  end

  describe "#settled?" do
    it "returns false when pending" do
      promise = described_class.new
      expect(promise).to be_pending
      expect(promise.settled?).to be false
    end

    it "returns true when fulfilled" do
      promise = described_class.new
      promise.resolve("value")
      expect(promise.settled?).to be true
    end

    it "returns true when rejected" do
      promise = described_class.new
      promise.reject("error")
      expect(promise.settled?).to be true
    end
  end

  describe "thread safety" do
    it "handles concurrent resolve/reject safely" do
      promise = described_class.new

      threads = 10.times.map do |i|
        Thread.new do
          if i.even?
            promise.resolve("value #{i}")
          else
            promise.reject("error #{i}")
          end
        end
      end

      threads.each(&:join)

      # Should have settled to one state
      expect(promise.settled?).to be true
    end
  end
end
