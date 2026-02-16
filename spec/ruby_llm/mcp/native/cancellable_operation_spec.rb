# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Native::CancellableOperation do
  let(:request_id) { "test-request-123" }
  let(:operation) { described_class.new(request_id) }

  describe "#initialize" do
    it "sets the request_id" do
      expect(operation.request_id).to eq(request_id)
    end

    it "initializes as not cancelled" do
      expect(operation.cancelled?).to be false
    end

    it "initializes with no thread" do
      expect(operation.thread).to be_nil
    end
  end

  describe "#cancelled?" do
    it "returns false by default" do
      expect(operation.cancelled?).to be false
    end

    it "returns true after cancel is called" do
      expect(operation.cancel).to eq(:cancelled)
      expect(operation.cancelled?).to be true
    end
  end

  describe "#execute" do
    it "executes the block in a separate thread" do
      execution_thread = nil
      calling_thread = Thread.current

      operation.execute do
        execution_thread = Thread.current
      end

      expect(execution_thread).not_to be_nil
      expect(execution_thread).not_to eq(calling_thread)
    end

    it "clears the thread reference after execution" do
      operation.execute { "test" }
      expect(operation.thread).to be_nil
    end

    it "returns the result of the block" do
      result = operation.execute { "test result" }
      expect(result).to eq("test result")
    end

    it "re-raises StandardError exceptions" do
      expect do
        operation.execute { raise StandardError, "test error" }
      end.to raise_error(StandardError, "test error")

      expect(operation.thread).to be_nil
    end

    it "does not re-raise RequestCancelled exceptions" do
      operation.cancel

      # Give the operation a chance to start before cancelling
      expect do
        operation.execute { sleep 0.1 }
      end.not_to raise_error

      expect(operation.thread).to be_nil
    end
  end

  describe "#cancel" do
    it "sets the cancelled flag" do
      expect(operation.cancel).to eq(:cancelled)
      expect(operation.cancelled?).to be true
    end

    context "when a thread is executing" do
      it "terminates the executing thread with RequestCancelled" do
        started = false
        finished = false

        # Start execution in a separate thread
        execution_thread = Thread.new do
          operation.execute do
            started = true
            sleep 1 # Long operation
            finished = true
          end
        end

        # Wait for execution to start
        sleep 0.01 until started

        # Cancel while executing
        expect(operation.cancel).to eq(:cancelled)

        # Wait for the thread to complete
        execution_thread.join

        # The operation should have been cancelled before finishing
        expect(finished).to be false
        expect(operation.cancelled?).to be true
      end
    end

    context "when no thread is executing" do
      it "does not raise an error" do
        expect(operation.cancel).to eq(:cancelled)
      end

      it "returns already_cancelled when cancelled twice" do
        operation.cancel
        expect(operation.cancel).to eq(:already_cancelled)
      end
    end
  end

  describe "thread safety" do
    it "handles concurrent cancellation checks safely" do
      threads = 10.times.map do
        Thread.new { operation.cancelled? }
      end

      threads.each(&:join)
      expect(operation.cancelled?).to be false
    end

    it "handles concurrent cancellation calls safely" do
      threads = 10.times.map do
        Thread.new { operation.cancel }
      end

      threads.each(&:join)
      expect(operation.cancelled?).to be true
    end
  end
end
