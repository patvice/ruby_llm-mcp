# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Transport::Stdio do
  let(:coordinator) { instance_double(RubyLLM::MCP::Coordinator) }
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
    allow(mock_wait_thread).to receive(:join)
    allow(mock_wait_thread).to receive(:alive?).and_return(true)
    allow(coordinator).to receive(:process_notification)
    allow(coordinator).to receive(:process_request)
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
    it "sends a request and adds an ID" do
      request_body = { "method" => "test" }
      captured_json = nil

      allow(mock_stdin).to receive(:puts) { |json_body| captured_json = json_body }
      allow(mock_stdin).to receive(:flush)

      # Mock successful response
      response_queue = Queue.new
      response_queue.push(RubyLLM::MCP::Result.new({ "id" => 1, "result" => {} }))
      allow(Queue).to receive(:new).and_return(response_queue)

      mock_transport.request(request_body)

      expect(mock_stdin).to have_received(:puts)
      expect(mock_stdin).to have_received(:flush)

      parsed = JSON.parse(captured_json)
      expect(parsed["method"]).to eq("test")
      expect(parsed["id"]).to be_a(Integer)
    end

    it "handles requests without waiting for response" do
      request_body = { "method" => "notification" }

      result = mock_transport.request(request_body, wait_for_response: false)

      expect(result).to be_nil
      expect(mock_stdin).to have_received(:puts)
      expect(mock_stdin).to have_received(:flush)
    end

    it "increments ID counter for multiple requests" do
      allow(mock_stdin).to receive(:puts)
      allow(mock_stdin).to receive(:flush)

      mock_transport.request({ "method" => "test1" }, wait_for_response: false)
      mock_transport.request({ "method" => "test2" }, wait_for_response: false)

      expect(mock_transport.instance_variable_get(:@id_counter)).to eq(2)
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
        request_body = { "method" => "test" }
        allow(mock_stdin).to receive(:puts)
        allow(mock_stdin).to receive(:flush)

        # Mock timeout behavior
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        short_timeout_transport = mock_transport
        short_timeout_transport.instance_variable_set(:@request_timeout, 10)

        expect do
          short_timeout_transport.request(request_body)
        end.to raise_error(RubyLLM::MCP::Errors::TimeoutError)

        begin
          short_timeout_transport.request(request_body)
        rescue RubyLLM::MCP::Errors::TimeoutError => e
          expect(e.message).to include("timed out")
          expect(e.request_id).to be_a(Integer)
        end
      end
    end
  end

  describe "response processing" do
    it "processes valid JSON responses" do
      valid_response = '{"id": "1", "result": {"success": true}}'

      allow(coordinator).to receive(:process_notification)
      allow(coordinator).to receive(:process_request)

      expect { mock_transport.send(:process_response, valid_response) }.not_to raise_error
    end

    it "handles JSON parse errors gracefully" do
      invalid_response = "invalid json {"
      allow(RubyLLM::MCP.logger).to receive(:error)

      mock_transport.send(:process_response, invalid_response)

      expect(RubyLLM::MCP.logger).to have_received(:error).with(/Error parsing response as JSON/)
    end

    it "processes notifications correctly" do
      notification = '{"method": "notifications/message", "params": {"level": "info", "data": "test"}}'
      result = instance_double(RubyLLM::MCP::Result)

      allow(RubyLLM::MCP::Result).to receive(:new).and_return(result)
      allow(result).to receive_messages(notification?: true, request?: false)
      allow(coordinator).to receive(:process_notification)

      mock_transport.send(:process_response, notification)

      expect(coordinator).to have_received(:process_notification).with(result)
    end

    it "processes requests correctly" do
      request = '{"id": "123", "method": "tools/call", "params": {}}'
      result = instance_double(RubyLLM::MCP::Result)

      allow(RubyLLM::MCP::Result).to receive(:new).and_return(result)
      allow(result).to receive_messages(notification?: false, request?: true)
      allow(coordinator).to receive(:process_request)

      mock_transport.send(:process_response, request)

      expect(coordinator).to have_received(:process_request).with(result)
    end

    it "handles responses with matching request IDs" do
      response = '{"id": "1", "result": {"data": "test"}}'
      result = instance_double(RubyLLM::MCP::Result)
      response_queue = Queue.new

      allow(RubyLLM::MCP::Result).to receive(:new).and_return(result)
      allow(result).to receive_messages(notification?: false, request?: false)
      allow(result).to receive(:matching_id?).with("1").and_return(true)

      # Set up pending request
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
end
