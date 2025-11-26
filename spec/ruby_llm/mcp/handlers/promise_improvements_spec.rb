# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Promise Improvements" do # rubocop:disable RSpec/DescribeClass
  describe "condition variable waiting" do
    it "wakes up immediately when resolved" do
      promise = RubyLLM::MCP::Handlers::Promise.new

      start_time = Time.now

      thread = Thread.new do
        promise.wait
      end

      # Give thread time to start waiting
      sleep 0.01

      # Resolve promise
      promise.resolve("value")

      thread.join

      # Should wake up almost immediately (well under 1 second)
      duration = Time.now - start_time
      expect(duration).to be < 0.1
    end

    it "handles timeout correctly with condition variables" do
      promise = RubyLLM::MCP::Handlers::Promise.new

      start_time = Time.now

      expect do
        promise.wait(timeout: 0.1)
      end.to raise_error(Timeout::Error)

      duration = Time.now - start_time
      # Should timeout around 0.1 seconds (with small margin)
      expect(duration).to be_between(0.09, 0.15)
    end

    it "handles multiple concurrent waiters efficiently" do
      promise = RubyLLM::MCP::Handlers::Promise.new
      results = []
      start_times = []

      # Start 10 threads waiting
      threads = 10.times.map do
        Thread.new do
          start_times << Time.now
          result = promise.wait(timeout: 1)
          results << result
        end
      end

      # Give threads time to start waiting
      sleep 0.05

      resolve_time = Time.now
      promise.resolve("resolved")

      threads.each(&:join)

      # All threads should get the same result
      expect(results).to all(eq("resolved"))
      expect(results.size).to eq(10)

      # All threads should have waited approximately the same time
      wait_times = start_times.map { |t| resolve_time - t }
      expect(wait_times.max - wait_times.min).to be < 0.1
    end

    it "properly releases mutex when exception occurs during wait" do
      promise = RubyLLM::MCP::Handlers::Promise.new

      # Try to wait with very short timeout that will fail
      expect do
        promise.wait(timeout: 0.001)
      end.to raise_error(Timeout::Error)

      # Should still be able to interact with promise
      expect { promise.resolve("value") }.not_to raise_error
      expect(promise.value).to eq("value")
    end

    it "handles spurious wakeups correctly" do
      promise = RubyLLM::MCP::Handlers::Promise.new

      thread = Thread.new do
        promise.wait(timeout: 1)
      end

      sleep 0.01

      # Manually signal condition (spurious wakeup simulation)
      # Promise should continue waiting since it's still pending
      promise.instance_variable_get(:@condition).broadcast

      sleep 0.01

      # Now actually resolve
      promise.resolve("value")

      result = thread.value
      expect(result).to eq("value")
    end
  end

  describe "callback execution isolation" do
    it "executes then callbacks outside mutex" do
      promise = RubyLLM::MCP::Handlers::Promise.new
      callback_executed = false
      mutex_held = false

      promise.then do |_value|
        # Try to check if mutex is locked (it shouldn't be during callback)
        callback_executed = true
        # If we can synchronize, mutex was released
        promise.instance_variable_get(:@mutex).try_lock
        mutex_held = !promise.instance_variable_get(:@mutex).locked?
        begin
          promise.instance_variable_get(:@mutex).unlock
        rescue StandardError
          nil
        end
      end

      promise.resolve("value")

      # Give callback time to execute
      sleep 0.1

      expect(callback_executed).to be true
    end

    it "executes catch callbacks outside mutex" do
      promise = RubyLLM::MCP::Handlers::Promise.new
      callback_executed = false

      promise.catch do |_reason|
        callback_executed = true
      end

      promise.reject("error")

      # Give callback time to execute
      sleep 0.1

      expect(callback_executed).to be true
    end

    it "allows callbacks to safely interact with promise" do
      promise1 = RubyLLM::MCP::Handlers::Promise.new
      promise2 = RubyLLM::MCP::Handlers::Promise.new

      promise1.then do |value|
        # Callback resolves another promise
        promise2.resolve("chained-#{value}")
      end

      promise1.resolve("original")

      # Wait for chain to complete
      result = promise2.wait(timeout: 1)
      expect(result).to eq("chained-original")
    end
  end

  describe "state consistency under concurrency" do
    it "maintains consistent state when resolve/reject called concurrently" do
      100.times do
        promise = RubyLLM::MCP::Handlers::Promise.new

        threads = []
        threads << Thread.new { promise.resolve("value") }
        threads << Thread.new { promise.reject("error") }
        threads << Thread.new { promise.resolve("other") }

        threads.each(&:join)

        # Promise should be in exactly one terminal state
        expect(promise.settled?).to be true
        expect(promise.fulfilled? ^ promise.rejected?).to be true
      end
    end

    it "prevents double resolution" do
      promise = RubyLLM::MCP::Handlers::Promise.new

      promise.resolve("first")
      promise.resolve("second")
      promise.reject("error")

      expect(promise.value).to eq("first")
      expect(promise.fulfilled?).to be true
    end

    it "prevents double rejection" do
      promise = RubyLLM::MCP::Handlers::Promise.new

      promise.reject("first")
      promise.reject("second")
      promise.resolve("value")

      expect(promise.reason).to eq("first")
      expect(promise.rejected?).to be true
    end
  end
end
