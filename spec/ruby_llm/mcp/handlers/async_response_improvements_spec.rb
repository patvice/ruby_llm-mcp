# frozen_string_literal: true

require "spec_helper"

RSpec.describe "AsyncResponse Improvements" do
  describe "callback execution safety" do
    it "executes callbacks outside mutex to prevent deadlocks" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      deadlock_occurred = false
      callback_executed = false

      async_resp.on_complete do |state, data|
        # Try to register another callback from within callback
        # This would deadlock if callbacks were executed inside mutex
        begin
          async_resp.on_complete { |s, d| nil }
          callback_executed = true
        rescue ThreadError
          deadlock_occurred = true
        end
      end

      async_resp.complete("test")

      # Wait for callbacks
      sleep 0.1

      expect(deadlock_occurred).to be false
      expect(callback_executed).to be true
    end

    it "continues executing callbacks even if one fails" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      results = []

      # Register multiple callbacks
      async_resp.on_complete { |state, data| raise "Error in first callback" }
      async_resp.on_complete { |state, data| results << "callback-1" }
      async_resp.on_complete { |state, data| raise "Error in third callback" }
      async_resp.on_complete { |state, data| results << "callback-2" }
      async_resp.on_complete { |state, data| results << "callback-3" }

      # Complete should not raise
      expect { async_resp.complete("data") }.not_to raise_error

      # Wait for all callbacks
      sleep 0.1

      # Successful callbacks should have executed
      expect(results).to match_array(["callback-1", "callback-2", "callback-3"])
    end

    it "handles concurrent callback registrations during completion" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      results = []

      # Register initial callback
      async_resp.on_complete { |state, data| results << "initial" }

      # Start completion in one thread
      completion_thread = Thread.new do
        sleep 0.01 # Small delay
        async_resp.complete("data")
      end

      # Register more callbacks concurrently
      registration_threads = 5.times.map do |i|
        Thread.new do
          async_resp.on_complete { |state, data| results << "concurrent-#{i}" }
        end
      end

      [completion_thread, *registration_threads].each(&:join)

      # Wait for callbacks
      sleep 0.1

      # Should not raise and should execute at least some callbacks
      expect(results).not_to be_empty
      expect(results).to include("initial")
    end
  end

  describe "state transition safety" do
    it "only transitions once from pending" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      # Try multiple transitions concurrently
      threads = []
      threads << Thread.new { async_resp.complete("data") }
      threads << Thread.new { async_resp.reject("reason") }
      threads << Thread.new { async_resp.cancel("cancelled") }
      threads << Thread.new { async_resp.timeout! }

      threads.each(&:join)

      # Should be in exactly one terminal state
      terminal_states = [
        async_resp.completed?,
        async_resp.rejected?,
        async_resp.cancelled?,
        async_resp.timed_out?
      ].count(true)

      expect(terminal_states).to eq(1)
      expect(async_resp.finished?).to be true
    end

    it "prevents state changes after completion" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      callback_count = 0
      async_resp.on_complete { |state, data| callback_count += 1 }

      # Complete once
      async_resp.complete("data")
      sleep 0.1
      initial_count = callback_count

      # Try to complete again
      async_resp.complete("other")
      async_resp.reject("error")
      async_resp.cancel("cancel")

      sleep 0.1

      # Callbacks should only execute once
      expect(callback_count).to eq(initial_count)
      expect(async_resp.result).to eq("data")
    end
  end

  describe "instrumentation" do
    it "logs creation with timeout info" do
      expect(RubyLLM::MCP.logger).to receive(:debug).with(/AsyncResponse created for test-123/)

      RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: 60
      )
    end

    it "logs completion with duration" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      sleep 0.05 # Small delay

      expect(RubyLLM::MCP.logger).to receive(:debug).with(/AsyncResponse test-123 completed after/)

      async_resp.complete("data")
    end
  end

  describe "callback error isolation" do
    it "logs callback errors but doesn't crash" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      async_resp.on_complete do |state, data|
        raise StandardError, "Intentional test error"
      end

      # Should log error
      expect(RubyLLM::MCP.logger).to receive(:error).with(/Error in async response callback/)

      # Should not raise
      expect { async_resp.complete("data") }.not_to raise_error
    end

    it "isolates callback errors from state management" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      async_resp.on_complete { |state, data| raise "Error" }

      async_resp.complete("data")
      sleep 0.1

      # State should still be properly set
      expect(async_resp.completed?).to be true
      expect(async_resp.result).to eq("data")
    end
  end

  describe "timeout handling with improved thread safety" do
    it "cleans up timeout thread properly" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: 10
      )

      # Complete before timeout
      async_resp.complete("data")

      # Give time for any cleanup
      sleep 0.1

      # Should be completed, not timed out
      expect(async_resp.completed?).to be true
      expect(async_resp.timed_out?).to be false
    end

    it "handles timeout correctly" do
      callback_called = false
      timeout_handler_called = false

      timeout_handler = proc { timeout_handler_called = true }

      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: 0.05,
        timeout_handler: timeout_handler
      )

      async_resp.on_complete do |state, data|
        callback_called = true if state == :timed_out
      end

      # Wait for timeout
      sleep 0.1

      expect(async_resp.timed_out?).to be true
      expect(callback_called).to be true
      expect(timeout_handler_called).to be true
    end
  end

  describe "integration with complete workflow" do
    it "handles full async workflow correctly" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "workflow-test",
        timeout: 1
      )

      states_received = []
      data_received = []

      async_resp.on_complete do |state, data|
        states_received << state
        data_received << data
      end

      # Simulate async work
      Thread.new do
        sleep 0.05
        async_resp.complete({ "result" => "success" })
      end

      # Wait for completion
      sleep 0.1

      expect(states_received).to eq([:completed])
      expect(data_received).to eq([{ "result" => "success" }])
      expect(async_resp.completed?).to be true
    end

    it "handles rejection workflow" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "rejection-test",
        timeout: 1
      )

      states_received = []

      async_resp.on_complete do |state, data|
        states_received << state
      end

      async_resp.reject("User declined")

      sleep 0.05

      expect(states_received).to eq([:rejected])
      expect(async_resp.rejected?).to be true
      expect(async_resp.error).to eq("User declined")
    end

    it "handles cancellation workflow" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "cancel-test",
        timeout: 1
      )

      states_received = []

      async_resp.on_complete do |state, data|
        states_received << state
      end

      async_resp.cancel("Cancelled by user")

      sleep 0.05

      expect(states_received).to eq([:cancelled])
      expect(async_resp.cancelled?).to be true
      expect(async_resp.error).to eq("Cancelled by user")
    end
  end
end
