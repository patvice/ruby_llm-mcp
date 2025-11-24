# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Native::Transports::Stdio do
  let(:coordinator) { instance_double(RubyLLM::MCP::Native::Client) }
  let(:command) { "echo" }
  let(:args) { [] }
  let(:env) { {} }
  let(:request_timeout) { 5000 }

  # Mock transport that bypasses process creation for testing
  let(:mock_transport) do
    transport = described_class.allocate
    transport.instance_variable_set(:@request_timeout, request_timeout)
    transport.instance_variable_set(:@command, command)
    transport.instance_variable_set(:@coordinator, coordinator)
    transport.instance_variable_set(:@args, args)
    transport.instance_variable_set(:@env, env)
    transport.instance_variable_set(:@client_id, SecureRandom.uuid)
    transport.instance_variable_set(:@id_counter, 0)
    transport.instance_variable_set(:@id_mutex, Mutex.new)
    transport.instance_variable_set(:@pending_requests, {})
    transport.instance_variable_set(:@pending_mutex, Mutex.new)
    transport.instance_variable_set(:@running, true)
    transport.instance_variable_set(:@stdin, mock_stdin)
    transport.instance_variable_set(:@stdout, mock_stdout)
    transport.instance_variable_set(:@stderr, mock_stderr)
    transport.instance_variable_set(:@wait_thread, mock_wait_thread)
    transport
  end

  let(:mock_stdin) { instance_double(IO) }
  let(:mock_stdout) { instance_double(IO) }
  let(:mock_stderr) { instance_double(IO) }
  let(:mock_wait_thread) { instance_double(Process::Waiter) }

  before do
    allow(mock_stdin).to receive(:puts)
    allow(mock_stdin).to receive(:flush)
    allow(mock_stdin).to receive(:close)
    allow(mock_stdout).to receive(:close)
    allow(mock_stderr).to receive(:close)
    allow(mock_wait_thread).to receive(:join).with(1)
    allow(mock_wait_thread).to receive(:alive?).and_return(true)
    allow(coordinator).to receive(:process_result)
  end

  describe "#initialize" do
    it "sets up the transport with basic properties" do
      transport = described_class.allocate
      transport.instance_variable_set(:@command, command)
      transport.instance_variable_set(:@coordinator, coordinator)

      expect(transport.command).to eq(command)
      expect(transport.coordinator).to eq(coordinator)
    end

    it "generates a unique client ID" do
      transport1 = described_class.allocate
      transport2 = described_class.allocate
      transport1.instance_variable_set(:@client_id, SecureRandom.uuid)
      transport2.instance_variable_set(:@client_id, SecureRandom.uuid)

      expect(transport1.instance_variable_get(:@client_id)).not_to eq(
        transport2.instance_variable_get(:@client_id)
      )
    end
  end

  describe "#alive?" do
    it "returns true when transport is running" do
      expect(mock_transport.alive?).to be(true)
    end

    it "returns false when transport is not running" do
      mock_transport.instance_variable_set(:@running, false)
      expect(mock_transport.alive?).to be(false)
    end
  end

  describe "#close" do
    it "sets running to false" do
      mock_transport.close
      expect(mock_transport.alive?).to be(false)
    end

    it "handles multiple close calls gracefully" do
      expect { mock_transport.close }.not_to raise_error
      expect { mock_transport.close }.not_to raise_error
    end
  end

  describe "#request" do
    it "sends a request with provided ID" do
      request_body = { "method" => "test", "id" => "test-uuid-123" }
      captured_json = nil

      allow(mock_stdin).to receive(:puts) { |json_body| captured_json = json_body }
      allow(mock_stdin).to receive(:flush)

      # Mock successful response
      response_queue = Queue.new
      mock_result = RubyLLM::MCP::Result.new({ "id" => "test-uuid-123", "result" => {} })
      response_queue.push(mock_result)
      allow(Queue).to receive(:new).and_return(response_queue)

      # Mock the with_timeout method to avoid thread creation issues
      allow(mock_transport).to receive(:with_timeout) do |_timeout, **_opts|
        response_queue.pop
      end

      result = mock_transport.request(request_body)

      expect(mock_stdin).to have_received(:puts)
      expect(mock_stdin).to have_received(:flush)
      expect(result).to eq(mock_result)

      parsed = JSON.parse(captured_json)
      expect(parsed["method"]).to eq("test")
      expect(parsed["id"]).to eq("test-uuid-123")
    end

    it "handles requests without waiting for response" do
      request_body = { "method" => "notification" }

      result = mock_transport.request(request_body, wait_for_response: false)

      expect(result).to be_nil
      expect(mock_stdin).to have_received(:puts)
      expect(mock_stdin).to have_received(:flush)
    end

    it "handles multiple requests with different IDs" do
      allow(mock_stdin).to receive(:puts)
      allow(mock_stdin).to receive(:flush)

      captured_jsons = []
      allow(mock_stdin).to receive(:puts) { |json_body| captured_jsons << json_body }

      mock_transport.request({ "method" => "test1", "id" => "id-1" }, wait_for_response: false)
      mock_transport.request({ "method" => "test2", "id" => "id-2" }, wait_for_response: false)

      parsed1 = JSON.parse(captured_jsons[0])
      parsed2 = JSON.parse(captured_jsons[1])

      expect(parsed1["id"]).to eq("id-1")
      expect(parsed2["id"]).to eq("id-2")
    end

    context "when handling errors" do
      it "raises TransportError on IOError" do
        request_body = { "method" => "test" }
        allow(mock_stdin).to receive(:puts).and_raise(IOError.new("Broken pipe"))
        allow(mock_transport).to receive(:restart_process)

        expect { mock_transport.request(request_body) }.to raise_error(RubyLLM::MCP::Errors::TransportError) do |error|
          expect(error.message).to include("Broken pipe")
          expect(error.error).to be_a(IOError)
        end
      end

      it "raises TransportError on EPIPE" do
        request_body = { "method" => "test" }
        allow(mock_stdin).to receive(:puts).and_raise(Errno::EPIPE.new("Broken pipe"))
        allow(mock_transport).to receive(:restart_process)

        expect { mock_transport.request(request_body) }.to raise_error(RubyLLM::MCP::Errors::TransportError) do |error|
          expect(error.message).to include("Broken pipe")
          expect(error.error).to be_a(Errno::EPIPE)
        end
      end

      it "raises TimeoutError when request times out" do
        request_body = { "method" => "test", "id" => "timeout-test-id" }
        allow(mock_stdin).to receive(:puts)
        allow(mock_stdin).to receive(:flush)

        # Mock timeout behavior
        allow(mock_transport).to receive(:with_timeout).and_raise(
          RubyLLM::MCP::Errors::TimeoutError.new(
            message: "Request timed out",
            request_id: "timeout-test-id"
          )
        )

        short_timeout_transport = mock_transport
        short_timeout_transport.instance_variable_set(:@request_timeout, 10)

        expect do
          short_timeout_transport.request(request_body)
        end.to raise_error(RubyLLM::MCP::Errors::TimeoutError)

        begin
          short_timeout_transport.request(request_body)
        rescue RubyLLM::MCP::Errors::TimeoutError => e
          expect(e.message).to include("timed out")
          expect(e.request_id).to eq("timeout-test-id")
        end
      end
    end
  end

  describe "response processing" do
    it "processes valid JSON responses" do
      valid_response = '{"id": "1", "result": {"success": true}}'

      allow(coordinator).to receive(:process_result)

      expect { mock_transport.send(:process_response, valid_response) }.not_to raise_error
    end

    it "handles JSON parse errors gracefully" do
      invalid_response = "invalid json {"
      allow(RubyLLM::MCP.logger).to receive(:error)

      mock_transport.send(:process_response, invalid_response)

      expect(RubyLLM::MCP.logger).to have_received(:error).with(/JSON parse error/)
    end

    it "processes notifications correctly" do
      notification = '{"jsonrpc": "2.0", "method": "notifications/message", "params": {"level": "info", "data": "test"}}'
      result = instance_double(RubyLLM::MCP::Result)

      allow(RubyLLM::MCP::Result).to receive(:new).and_return(result)
      allow(result).to receive_messages(notification?: true, request?: false)
      allow(coordinator).to receive(:process_result)

      mock_transport.send(:process_response, notification)

      expect(coordinator).to have_received(:process_result).with(result)
    end

    it "processes requests correctly" do
      request = '{"jsonrpc": "2.0", "id": "123", "method": "tools/call", "params": {}}'
      result = instance_double(RubyLLM::MCP::Result)

      allow(RubyLLM::MCP::Result).to receive(:new).and_return(result)
      allow(result).to receive_messages(notification?: false, request?: true)
      allow(coordinator).to receive(:process_result)

      mock_transport.send(:process_response, request)

      expect(coordinator).to have_received(:process_result).with(result)
    end

    it "handles responses with matching request IDs" do
      response = '{"jsonrpc": "2.0", "id": "1", "result": {"data": "test"}}'
      result = instance_double(RubyLLM::MCP::Result)
      response_queue = Queue.new

      allow(RubyLLM::MCP::Result).to receive(:new).and_return(result)
      allow(result).to receive(:matching_id?).with("1").and_return(true)
      allow(coordinator).to receive(:process_result).and_return(result)

      mock_transport.instance_variable_get(:@pending_requests)["1"] = response_queue

      mock_transport.send(:process_response, response)

      expect(response_queue.size).to eq(1)
    end
  end

  describe "thread safety" do
    it "handles concurrent ID generation safely" do
      threads = 5.times.map do |_i|
        Thread.new do
          mock_transport.instance_variable_get(:@id_mutex).synchronize do
            current = mock_transport.instance_variable_get(:@id_counter)
            mock_transport.instance_variable_set(:@id_counter, current + 1)
          end
        end
      end

      threads.each(&:join)
      expect(mock_transport.instance_variable_get(:@id_counter)).to eq(5)
    end
  end

  describe "configuration" do
    it "stores command and arguments correctly" do
      transport = described_class.allocate
      transport.instance_variable_set(:@command, "test_command")
      transport.instance_variable_set(:@args, %w[arg1 arg2])

      expect(transport.instance_variable_get(:@command)).to eq("test_command")
      expect(transport.instance_variable_get(:@args)).to eq(%w[arg1 arg2])
    end

    it "stores environment variables correctly" do
      transport = described_class.allocate
      test_env = { "TEST_VAR" => "test_value" }
      transport.instance_variable_set(:@env, test_env)

      expect(transport.instance_variable_get(:@env)).to eq(test_env)
    end

    it "stores request timeout correctly" do
      transport = described_class.allocate
      transport.instance_variable_set(:@request_timeout, 10_000)

      expect(transport.instance_variable_get(:@request_timeout)).to eq(10_000)
    end
  end

  describe "process restart behavior" do
    it "can handle restart scenarios" do
      allow(mock_transport).to receive(:start_process)
      allow(mock_transport).to receive(:close)

      expect { mock_transport.send(:restart_process) }.not_to raise_error
    end
  end

  describe "graceful shutdown" do
    let(:real_stdin) { IO.pipe[1] }
    let(:real_stdout) { IO.pipe[0] }
    let(:real_stderr) { IO.pipe[0] }
    let(:real_wait_thread) { instance_double(Process::Waiter, alive?: true, join: nil) }

    let(:transport_with_threads) do
      transport = described_class.allocate
      transport.instance_variable_set(:@request_timeout, request_timeout)
      transport.instance_variable_set(:@command, command)
      transport.instance_variable_set(:@coordinator, coordinator)
      transport.instance_variable_set(:@args, args)
      transport.instance_variable_set(:@env, env)
      transport.instance_variable_set(:@client_id, SecureRandom.uuid)
      transport.instance_variable_set(:@id_counter, 0)
      transport.instance_variable_set(:@id_mutex, Mutex.new)
      transport.instance_variable_set(:@pending_requests, {})
      transport.instance_variable_set(:@pending_mutex, Mutex.new)
      transport.instance_variable_set(:@running, true)
      transport.instance_variable_set(:@stdin, real_stdin)
      transport.instance_variable_set(:@stdout, real_stdout)
      transport.instance_variable_set(:@stderr, real_stderr)
      transport.instance_variable_set(:@wait_thread, real_wait_thread)
      transport
    end

    after do
      [real_stdin, real_stdout, real_stderr].each do |io|
        io.close
      rescue IOError, Errno::EBADF
        nil
      end
    end

    it "does not log ERROR messages during normal shutdown" do
      transport_with_threads.send(:start_reader_thread)
      transport_with_threads.send(:start_stderr_thread)
      sleep 0.1

      error_logs = []
      allow(RubyLLM::MCP.logger).to receive(:error) do |message|
        error_logs << message
      end
      allow(RubyLLM::MCP.logger).to receive(:debug)
      allow(RubyLLM::MCP.logger).to receive(:info)

      transport_with_threads.close

      expect(error_logs).to be_empty, "Expected no ERROR logs during graceful shutdown, but got: #{error_logs.inspect}"
    end

    it "checks @running flag before logging errors in stdout reader" do
      transport_with_threads.send(:start_reader_thread)
      sleep 0.1

      error_calls = 0
      debug_calls = 0
      allow(RubyLLM::MCP.logger).to receive(:error) { error_calls += 1 }
      allow(RubyLLM::MCP.logger).to receive(:debug) { debug_calls += 1 }

      transport_with_threads.instance_variable_set(:@running, false)
      real_stdout.close

      sleep 0.2

      expect(error_calls).to eq(0), "Expected no ERROR logs during graceful shutdown"
      expect(debug_calls).to be > 0, "Expected DEBUG logs during graceful shutdown"
    end

    it "checks @running flag before logging errors in stderr reader" do
      transport_with_threads.send(:start_stderr_thread)
      sleep 0.1

      error_calls = 0
      debug_calls = 0
      allow(RubyLLM::MCP.logger).to receive(:error) { error_calls += 1 }
      allow(RubyLLM::MCP.logger).to receive(:debug) { debug_calls += 1 }
      allow(RubyLLM::MCP.logger).to receive(:info)
      transport_with_threads.instance_variable_set(:@running, false)
      real_stderr.close
      sleep 0.2

      expect(error_calls).to eq(0), "Expected no ERROR logs during graceful shutdown"
      expect(debug_calls).to be > 0, "Expected DEBUG logs during graceful shutdown"
    end

    it "allows reader threads to exit cleanly during shutdown" do
      transport_with_threads.send(:start_reader_thread)
      transport_with_threads.send(:start_stderr_thread)
      # Give threads time to start
      sleep 0.1

      reader_thread = transport_with_threads.instance_variable_get(:@reader_thread)
      stderr_thread = transport_with_threads.instance_variable_get(:@stderr_thread)

      expect(reader_thread).to be_alive
      expect(stderr_thread).to be_alive

      allow(RubyLLM::MCP.logger).to receive(:error)
      allow(RubyLLM::MCP.logger).to receive(:debug)
      allow(RubyLLM::MCP.logger).to receive(:info)
      transport_with_threads.close

      expect(reader_thread.join(2)).to eq(reader_thread), "Reader thread should exit cleanly"
      expect(stderr_thread.join(2)).to eq(stderr_thread), "Stderr thread should exit cleanly"
    end

    it "logs errors and restarts when @running is true and stream closes unexpectedly" do
      transport_with_threads.send(:start_reader_thread)
      # Give thread time to start
      sleep 0.1

      error_logs = []
      allow(RubyLLM::MCP.logger).to receive(:error) do |message|
        error_logs << message
      end
      allow(RubyLLM::MCP.logger).to receive(:debug)

      restart_called = false
      allow(transport_with_threads).to receive(:restart_process) do
        restart_called = true
        transport_with_threads.instance_variable_set(:@running, false)
      end
      real_stdout.close

      deadline = Time.now + 2
      sleep 0.1 until restart_called || Time.now > deadline

      expect(restart_called).to be(true), "Expected restart_process to be called within 2 seconds"
    end
  end
end
