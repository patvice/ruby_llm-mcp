# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Handler Concurrency" do # rubocop:disable RSpec/DescribeClass
  before do
    RubyLLM::MCP::Handlers::ElicitationRegistry.clear
    RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.clear
  end

  after do
    RubyLLM::MCP::Handlers::ElicitationRegistry.clear
    RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.clear
  end

  describe "ElicitationRegistry" do
    it "handles concurrent registrations" do
      threads = 10.times.map do |i|
        Thread.new do
          elicitation = double("Elicitation", timeout: nil)
          RubyLLM::MCP::Handlers::ElicitationRegistry.store("elicit-#{i}", elicitation)
        end
      end

      threads.each(&:join)
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(10)
    end

    it "handles concurrent completions" do
      # Store 10 elicitations
      coordinators = []
      10.times do |i|
        coordinator = double("Coordinator")
        allow(coordinator).to receive(:elicitation_response)
        coordinators << coordinator

        result = double(
          "Result",
          id: "elicit-#{i}",
          params: {
            "message" => "Test",
            "requestedSchema" => {
              "type" => "object",
              "properties" => { "value" => { "type" => "string" } }
            }
          }
        )

        elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)
        RubyLLM::MCP::Handlers::ElicitationRegistry.store("elicit-#{i}", elicitation)
      end

      # Complete them all concurrently
      threads = 10.times.map do |i|
        Thread.new do
          RubyLLM::MCP::Handlers::ElicitationRegistry.complete(
            "elicit-#{i}",
            response: { "value" => "response-#{i}" }
          )
        end
      end

      threads.each(&:join)
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
    end

    it "handles concurrent cancellations" do
      # Store 10 elicitations
      10.times do |i|
        coordinator = double("Coordinator")
        allow(coordinator).to receive(:elicitation_response)

        result = double(
          "Result",
          id: "elicit-#{i}",
          params: {
            "message" => "Test",
            "requestedSchema" => { "type" => "object" }
          }
        )

        elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)
        RubyLLM::MCP::Handlers::ElicitationRegistry.store("elicit-#{i}", elicitation)
      end

      # Cancel them all concurrently
      threads = 10.times.map do |i|
        Thread.new do
          RubyLLM::MCP::Handlers::ElicitationRegistry.cancel("elicit-#{i}", reason: "Test")
        end
      end

      threads.each(&:join)
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
    end

    it "properly cleans up timeout threads on concurrent removals" do
      # Store elicitations with timeouts
      10.times do |i|
        coordinator = double("Coordinator")
        allow(coordinator).to receive(:elicitation_response)

        result = double(
          "Result",
          id: "elicit-#{i}",
          params: {
            "message" => "Test",
            "requestedSchema" => { "type" => "object" }
          }
        )

        elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)
        elicitation.instance_variable_set(:@timeout, 10)
        RubyLLM::MCP::Handlers::ElicitationRegistry.store("elicit-#{i}", elicitation)
      end

      # Remove them all concurrently
      threads = 10.times.map do |i|
        Thread.new do
          RubyLLM::MCP::Handlers::ElicitationRegistry.remove("elicit-#{i}")
        end
      end

      threads.each(&:join)

      # Give threads time to clean up
      sleep 0.1

      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
    end
  end

  describe "HumanInTheLoopRegistry" do
    it "handles concurrent promise registrations" do
      threads = 10.times.map do |i|
        Thread.new do
          promise = RubyLLM::MCP::Handlers::Promise.new
          RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.store(
            "approval-#{i}",
            {
              promise: promise,
              timeout: nil,
              tool_name: "test_tool",
              parameters: {}
            }
          )
        end
      end

      threads.each(&:join)
      expect(RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.size).to eq(10)
    end

    it "handles concurrent approvals" do
      # Store 10 approvals
      promises = []
      10.times do |i|
        promise = RubyLLM::MCP::Handlers::Promise.new
        promises << promise
        RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.store(
          "approval-#{i}",
          {
            promise: promise,
            timeout: nil,
            tool_name: "test_tool",
            parameters: {}
          }
        )
      end

      # Approve them all concurrently
      threads = 10.times.map do |i|
        Thread.new do
          RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.approve("approval-#{i}")
        end
      end

      threads.each(&:join)

      # Wait for promises to resolve
      sleep 0.1

      expect(RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.size).to eq(0)
      promises.each do |promise|
        expect(promise.fulfilled?).to be true
        expect(promise.value).to be true
      end
    end

    it "handles concurrent denials" do
      # Store 10 approvals
      promises = []
      10.times do |i|
        promise = RubyLLM::MCP::Handlers::Promise.new
        promises << promise
        RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.store(
          "approval-#{i}",
          {
            promise: promise,
            timeout: nil,
            tool_name: "test_tool",
            parameters: {}
          }
        )
      end

      # Deny them all concurrently
      threads = 10.times.map do |i|
        Thread.new do
          RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.deny("approval-#{i}", reason: "Test")
        end
      end

      threads.each(&:join)

      # Wait for promises to resolve
      sleep 0.1

      expect(RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.size).to eq(0)
      promises.each do |promise|
        expect(promise.fulfilled?).to be true
        expect(promise.value).to be false
      end
    end
  end

  describe "Promise" do
    it "handles concurrent then/catch registrations" do
      promise = RubyLLM::MCP::Handlers::Promise.new

      # Register callbacks concurrently
      threads = 20.times.map do |i|
        Thread.new do
          if i.even?
            promise.then { |value| value }
          else
            promise.catch { |reason| reason }
          end
        end
      end

      threads.each(&:join)

      # Resolve the promise
      promise.resolve("test")

      expect(promise.fulfilled?).to be true
    end

    it "handles concurrent wait calls" do
      promise = RubyLLM::MCP::Handlers::Promise.new

      # Start multiple threads waiting on promise
      results = Queue.new
      threads = 5.times.map do
        Thread.new do
          results << promise.wait(timeout: 1)
        end
      end

      # Give threads time to start waiting
      sleep 0.1

      # Resolve the promise
      promise.resolve("resolved")

      threads.each(&:join)

      collected_results = 5.times.map { results.pop }
      expect(collected_results).to all(eq("resolved"))
    end

    it "handles concurrent resolve attempts (only first succeeds)" do
      promise = RubyLLM::MCP::Handlers::Promise.new

      # Try to resolve concurrently
      threads = 10.times.map do |i|
        Thread.new do
          promise.resolve("value-#{i}")
        end
      end

      threads.each(&:join)

      # Promise should be resolved with one of the values
      expect(promise.fulfilled?).to be true
      expect(promise.value).to match(/^value-\d+$/)
    end
  end

  describe "AsyncResponse" do
    it "handles concurrent callback registrations" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      # Register callbacks concurrently
      threads = 10.times.map do
        Thread.new do
          async_resp.on_complete { |state, data| [state, data] }
        end
      end

      threads.each(&:join)

      # Complete the response
      async_resp.complete({ "result" => "test" })

      expect(async_resp.completed?).to be true
    end

    it "safely handles callback errors without affecting other callbacks" do
      async_resp = RubyLLM::MCP::Handlers::AsyncResponse.new(
        elicitation_id: "test-123",
        timeout: nil
      )

      callback_results = []

      # Register callbacks, some will fail
      async_resp.on_complete do |_state, _data|
        raise "Intentional error"
      end

      async_resp.on_complete do |_state, _data|
        callback_results << "callback-1"
      end

      async_resp.on_complete do |_state, _data|
        callback_results << "callback-2"
      end

      # Complete should not raise
      expect { async_resp.complete("data") }.not_to raise_error

      # Wait for callbacks to execute
      sleep 0.1

      # Other callbacks should have executed
      expect(callback_results).to include("callback-1", "callback-2")
    end
  end

  describe "Edge Cases" do
    describe "timeout handling" do
      it "properly schedules and cancels timeout threads" do
        coordinator = double("Coordinator")
        allow(coordinator).to receive(:elicitation_response)

        result = double(
          "Result",
          id: "elicit-timeout",
          params: {
            "message" => "Test",
            "requestedSchema" => { "type" => "object" }
          }
        )

        RubyLLM::MCP::Elicitation.new(coordinator, result)
        # Create a mock elicitation with timeout method
        elicitation_with_timeout = double(
          "ElicitationWithTimeout",
          timeout: 10, # Long timeout that we'll cancel before it fires
          timeout!: nil
        )

        RubyLLM::MCP::Handlers::ElicitationRegistry.store("elicit-timeout", elicitation_with_timeout)

        # Should be in registry
        expect(RubyLLM::MCP::Handlers::ElicitationRegistry.retrieve("elicit-timeout")).not_to be_nil

        # Remove before timeout fires
        RubyLLM::MCP::Handlers::ElicitationRegistry.remove("elicit-timeout")

        # Give threads time to clean up
        sleep 0.1

        # Should be removed
        expect(RubyLLM::MCP::Handlers::ElicitationRegistry.retrieve("elicit-timeout")).to be_nil
      end

      it "handles promise wait with short timeout" do
        promise = RubyLLM::MCP::Handlers::Promise.new

        expect do
          promise.wait(timeout: 0.01)
        end.to raise_error(Timeout::Error)

        expect(promise.pending?).to be true
      end
    end

    describe "handler validation" do
      it "validates handler classes have execute method" do
        invalid_handler = Class.new do
          # Missing execute method
        end

        client = RubyLLM::MCP::Client.new(
          name: "test-client",
          transport_type: :stdio,
          start: false,
          config: { command: "echo", args: ["test"] }
        )

        expect do
          client.on_sampling(invalid_handler)
        end.to raise_error(ArgumentError, /must define #execute method/)
      end

      it "rejects non-class handlers" do
        client = RubyLLM::MCP::Client.new(
          name: "test-client",
          transport_type: :stdio,
          start: false,
          config: { command: "echo", args: ["test"] }
        )

        expect do
          client.on_sampling("not a class")
        end.to raise_error(ArgumentError, /must be a class/)
      end
    end

    describe "memory management" do
      it "cleans up all references after multiple operations" do
        # Perform many operations
        100.times do |i|
          coordinator = double("Coordinator")
          allow(coordinator).to receive(:elicitation_response)

          result = double(
            "Result",
            id: "elicit-#{i}",
            params: {
              "message" => "Test",
              "requestedSchema" => { "type" => "object", "properties" => { "value" => { "type" => "string" } } }
            }
          )

          elicitation = RubyLLM::MCP::Elicitation.new(coordinator, result)
          RubyLLM::MCP::Handlers::ElicitationRegistry.store("elicit-#{i}", elicitation)
          RubyLLM::MCP::Handlers::ElicitationRegistry.complete("elicit-#{i}", response: { "value" => "test" })
        end

        # Force garbage collection
        GC.start

        # Registry should be empty
        expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
      end
    end
  end
end
