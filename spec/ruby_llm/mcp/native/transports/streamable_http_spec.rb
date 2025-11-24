# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Native::Transports::StreamableHTTP do
  let(:client) do
    RubyLLM::MCP::Client.new(
      name: "test-client",
      transport_type: :streamable,
      request_timeout: 5000,
      config: {
        url: TestServerManager::HTTP_SERVER_URL
      }
    )
  end

  let(:mock_coordinator) { instance_double(RubyLLM::MCP::Adapters::MCPTransports::CoordinatorStub) }
  let(:transport) do
    RubyLLM::MCP::Native::Transports::StreamableHTTP.new(
      url: TestServerManager::HTTP_SERVER_URL,
      request_timeout: 5000,
      coordinator: mock_coordinator,
      options: { headers: {} }
    )
  end
  let(:logger) { instance_double(Logger) }

  before do
    allow(RubyLLM::MCP).to receive(:logger).and_return(logger)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:error)
    allow(logger).to receive(:info)
  end

  describe "protocol version negotiation" do
    it "successfully initializes and negotiates protocol version" do
      client.start

      # If protocol version negotiation succeeds, the client should be alive
      expect(client).to be_alive
      expect(client.capabilities).to be_a(RubyLLM::MCP::ServerCapabilities)

      client.stop
    end

    it "can access protocol version through private coordinator for verification" do
      client.start

      # Access native client through adapter for testing purposes
      native_client = client.adapter.native_client
      expect(native_client.protocol_version).to be_a(String)
      expect(native_client.protocol_version).to match(/\d{4}-\d{2}-\d{2}/)
      # Server negotiates its preferred version - should be one of the supported versions
      expect(RubyLLM::MCP::Native::Protocol.supported_versions).to include(native_client.protocol_version)

      client.stop
    end
  end

  describe "MCP-Protocol-Version header functionality" do
    it "successfully makes subsequent requests after initialization" do
      client.start

      # These requests should succeed if the protocol version header is correct
      tools = client.tools
      expect(tools).to be_an(Array)
      expect(tools.length).to be > 0

      resources = client.resources
      expect(resources).to be_an(Array)

      prompts = client.prompts
      expect(prompts).to be_an(Array)

      client.stop
    end

    it "can execute tools successfully with proper headers" do
      client.start

      # Tool execution should work if headers are correct
      tool = client.tool("add")
      expect(tool).to be_a(RubyLLM::MCP::Tool)

      result = tool.execute(a: 5, b: 3)
      expect(result).to be_a(RubyLLM::MCP::Content)
      expect(result.to_s).to eq("8")

      client.stop
    end

    it "maintains consistent communication across multiple operations" do
      client.start

      # Multiple operations should all work consistently
      expect(client.tools.length).to be > 0
      expect(client.resources.length).to be > 0
      expect(client.ping).to be(true)

      # Execute a tool to verify full round-trip functionality
      add_tool = client.tool("add")
      result = add_tool.execute(a: 10, b: 20)
      expect(result).to be_a(RubyLLM::MCP::Content)
      expect(result.to_s).to eq("30")

      client.stop
    end
  end

  describe "transport protocol version handling" do
    it "transport can set protocol version after initialization" do
      client.start

      # Verify the transport has the set_protocol_version method
      native_client = client.adapter.native_client
      transport = native_client.transport
      expect(transport).to respond_to(:set_protocol_version)

      client.stop
    end

    it "protocol version is correctly set on transport" do
      client.start

      # Access transport through native_client for verification
      native_client = client.adapter.native_client
      transport = native_client.transport

      # The transport should have a protocol version set to whatever was negotiated
      negotiated_version = transport.transport_protocol.protocol_version
      expect(negotiated_version).to be_a(String)
      expect(negotiated_version).to match(/\d{4}-\d{2}-\d{2}/)
      expect(RubyLLM::MCP::Native::Protocol.supported_versions).to include(negotiated_version)

      client.stop
    end
  end

  describe "error handling and compatibility" do
    it "handles normal server communication without issues" do
      client.start

      # Basic functionality should work indicating proper header handling
      expect(client).to be_alive
      expect(client.ping).to be(true)

      client.stop
    end

    it "supports the negotiated protocol version features" do
      client.start

      # Test capabilities that should be available with the protocol version
      expect(client.capabilities.tools_list?).to be(true)
      expect(client.capabilities.resources_list?).to be(true)

      client.stop
    end
  end

  describe "HTTP error handling" do
    before do
      WebMock.enable!
    end

    after do
      WebMock.reset!
      # Re-enable WebMock to ensure it's active for subsequent tests
      WebMock.enable!
    end

    describe "connection errors" do
      it "handles connection refused errors" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_raise(Errno::ECONNREFUSED)

        expect do
          transport.request({ "method" => "initialize", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Connection refused/)
      end

      it "handles timeout errors" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_timeout

        expect do
          transport.request({ "method" => "initialize", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError)
      end

      it "handles network errors" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_raise(SocketError.new("Failed to open TCP connection"))

        expect do
          transport.request({ "method" => "initialize", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Failed to open TCP connection/)
      end
    end

    describe "HTTP status errors" do
      it "handles 400 Bad Request with JSON error" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 400,
            headers: { "Content-Type" => "application/json" },
            body: '{"error": {"code": "invalid_request", "message": "Invalid JSON"}}'
          )

        expect do
          transport.request({ "method" => "invalid", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Invalid JSON/)
      end

      it "handles 400 Bad Request with malformed JSON error" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 400,
            headers: { "Content-Type" => "application/json" },
            body: "invalid json"
          )

        expect do
          transport.request({ "method" => "invalid", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /HTTP client error: 400/)
      end

      it "handles 401 Unauthorized by raising AuthenticationRequiredError" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(status: 401)

        expect do
          transport.request({ "method" => "initialize", "id" => 1 }, wait_for_response: false)
        end.to raise_error(RubyLLM::MCP::Errors::AuthenticationRequiredError, /OAuth authentication required/)
      end

      it "handles 404 Not Found (session expired)" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(status: 404)

        expect do
          transport.request({ "method" => "tools/list", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::SessionExpiredError)
      end

      it "handles 405 Method Not Allowed" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(status: 405)

        result = transport.request({ "method" => "unsupported", "id" => 1 }, wait_for_response: false)
        expect(result).to be_nil
      end

      it "handles 500 Internal Server Error" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 500,
            body: "Internal Server Error"
          )

        expect do
          transport.request({ "method" => "test", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /HTTP request failed: 500/)
      end

      it "handles session-related errors in error message" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 400,
            headers: { "Content-Type" => "application/json" },
            body: '{"error": {"message": "Session not found"}}'
          )

        transport.instance_variable_set(:@session_id, "test-session")

        expect do
          transport.request({ "method" => "test", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Session not found.*test-session/)
      end
    end

    describe "response content errors" do
      it "handles invalid JSON in successful response" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: "invalid json"
          )

        expect do
          transport.request({ "method" => "test", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /JSON parse error/)
      end

      it "handles unexpected content type" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "text/plain" },
            body: "plain text response"
          )

        expect do
          transport.request({ "method" => "test", "id" => 1 })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Unexpected content type/)
      end
    end

    describe "SSE (Server-Sent Events) errors" do
      it "handles SSE 400 errors" do
        stub_request(:get, TestServerManager::HTTP_SERVER_URL)
          .with(headers: { "Accept" => "text/event-stream" })
          .to_return(status: 400)

        options = RubyLLM::MCP::Native::Transports::StartSSEOptions.new

        expect do
          transport.send(:start_sse, options)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Failed to open SSE stream: 400/)
      end

      it "handles SSE 405 Method Not Allowed gracefully" do
        stub_request(:get, TestServerManager::HTTP_SERVER_URL)
          .with(headers: { "Accept" => "text/event-stream" })
          .to_return(status: 405)

        options = RubyLLM::MCP::Native::Transports::StartSSEOptions.new

        # Should not raise an error for 405 (acceptable per spec)
        expect do
          transport.send(:start_sse, options)
        end.not_to raise_error
      end

      context "when handling malformed SSE events" do
        it "logs warning and continues" do
          raw_event = { data: "invalid json data" }

          transport.send(:process_sse_event, raw_event, nil)

          expect(logger).to have_received(:warn).with(/Failed to parse SSE event data/)
        end
      end

      context "when handling unknown request errors in SSE processing" do
        before do
          allow(mock_coordinator).to receive(:process_result).and_raise(
            RubyLLM::MCP::Errors::UnknownRequest.new(message: "Unknown request type")
          )
        end

        it "logs error for invalid JSON-RPC envelope" do
          raw_event = { data: '{"method": "unknown", "params": {}}' }

          transport.send(:process_sse_event, raw_event, nil)
          expect(logger).to have_received(:error).with(/Invalid JSON-RPC envelope/)
        end
      end

      it "respects abort controller in SSE processing" do
        allow(mock_coordinator).to receive(:process_result)
        transport.instance_variable_set(:@abort_controller, true)

        raw_event = { data: '{"method": "test"}' }

        transport.send(:process_sse_event, raw_event, nil)

        expect(mock_coordinator).not_to have_received(:process_result)
      end

      it "respects running flag in SSE processing" do
        allow(mock_coordinator).to receive(:process_result)
        transport.instance_variable_set(:@running, false)

        raw_event = { data: '{"method": "test"}' }

        transport.send(:process_sse_event, raw_event, nil)

        expect(mock_coordinator).not_to have_received(:process_result)
      end

      it "handles SSE buffer events with abort controller" do
        allow(transport).to receive(:extract_sse_event)
        transport.instance_variable_set(:@abort_controller, true)

        buffer = +"data: test\n\n"

        transport.send(:process_sse_buffer_events, buffer, "test-id")

        expect(transport).not_to have_received(:extract_sse_event)
      end

      it "handles SSE buffer events when not running" do
        allow(transport).to receive(:extract_sse_event)
        transport.instance_variable_set(:@running, false)

        buffer = +"data: test\n\n"

        transport.send(:process_sse_buffer_events, buffer, "test-id")

        expect(transport).not_to have_received(:extract_sse_event)
      end
    end

    describe "session termination errors" do
      it "handles session termination failure" do
        transport.instance_variable_set(:@session_id, "test-session")

        stub_request(:delete, TestServerManager::HTTP_SERVER_URL)
          .to_return(status: 500, body: "Server Error")

        expect do
          transport.send(:terminate_session)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Failed to terminate session: 500/)
      end

      it "handles session termination connection error" do
        transport.instance_variable_set(:@session_id, "test-session")

        stub_request(:delete, TestServerManager::HTTP_SERVER_URL)
          .to_raise(Errno::ECONNREFUSED)

        expect do
          transport.send(:terminate_session)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Failed to terminate session/)
      end

      it "accepts 405 status for session termination" do
        transport.instance_variable_set(:@session_id, "test-session")

        stub_request(:delete, TestServerManager::HTTP_SERVER_URL)
          .to_return(status: 405)

        # Should not raise an error for 405 (acceptable per spec)
        expect do
          transport.send(:terminate_session)
        end.not_to raise_error

        expect(transport.instance_variable_get(:@session_id)).to be_nil
      end

      it "handles session termination when no session exists" do
        transport.instance_variable_set(:@session_id, nil)

        # Should return early without making any requests
        expect(WebMock).not_to have_requested(:delete, TestServerManager::HTTP_SERVER_URL)

        transport.send(:terminate_session)
      end

      context "when handling HTTPX error response in session termination" do
        before do
          transport.instance_variable_set(:@session_id, "test-session")

          stub_request(:delete, TestServerManager::HTTP_SERVER_URL)
            .to_return(status: 400, body: "Bad Request")
        end

        it "raises appropriate error" do
          expect do
            transport.send(:terminate_session)
          end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Failed to terminate session: 400/)
        end
      end
    end

    describe "request timeout handling" do
      let(:response_queue) { Queue.new }

      before do
        request_id = "timeout-test"
        allow(response_queue).to receive(:pop).and_raise(
          RubyLLM::MCP::Errors::TimeoutError.new(
            message: "Request timed out",
            request_id: request_id
          )
        )

        transport.instance_variable_get(:@pending_mutex).synchronize do
          transport.instance_variable_get(:@pending_requests)[request_id] = response_queue
        end
      end

      it "handles request timeout errors and cleans up" do
        request_id = "timeout-test"

        expect do
          transport.send(:wait_for_response_with_timeout, request_id, response_queue)
        end.to raise_error(RubyLLM::MCP::Errors::TimeoutError, /Request timed out/)

        # Should clean up the pending request
        pending_requests = transport.instance_variable_get(:@pending_requests)
        expect(pending_requests).not_to have_key(request_id)
      end
    end

    describe "client management errors" do
      context "when client closing fails" do
        let(:mock_client) { instance_double(HTTPX::Session) }

        before do
          allow(mock_client).to receive(:respond_to?).and_return(true)
          allow(mock_client).to receive(:close).and_raise(StandardError.new("Close failed"))
        end

        it "logs error but continues" do
          transport.send(:close_client, mock_client)

          expect(logger).to have_received(:debug).with(/Error closing HTTPX client/)
        end
      end

      it "tracks active client count correctly" do
        expect(transport.send(:active_clients_count)).to eq(1) # Initial connection

        # Create additional clients
        3.times { transport.send(:create_connection) }
        expect(transport.send(:active_clients_count)).to eq(4)

        # Close transport should clear all clients
        transport.close
        expect(transport.send(:active_clients_count)).to eq(0)
      end

      context "when client doesn't have close method" do
        # rubocop:disable RSpec/VerifiedDoubles
        let(:mock_client) { double("client_without_close") }
        # rubocop:enable RSpec/VerifiedDoubles

        before do
          allow(mock_client).to receive(:respond_to?).with(:close).and_return(false)
        end

        it "skips closing gracefully" do
          # This client doesn't have close method, so it should be skipped
          expect do
            transport.send(:close_client, mock_client)
          end.not_to raise_error

          # Since the client doesn't respond to :close, the method should not be called
          # The fact that no exception is raised proves it works correctly
        end
      end
    end

    describe "202 Accepted response handling" do
      it "starts SSE stream on initialization with 202" do
        allow(transport).to receive(:start_sse_stream)
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(status: 202)

        transport.request({ "method" => "initialize", "id" => 1 }, wait_for_response: false)

        expect(transport).to have_received(:start_sse_stream)
      end

      it "does not start SSE stream on non-initialization 202" do
        allow(transport).to receive(:start_sse_stream)
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(status: 202)

        result = transport.request({ "method" => "other", "id" => 1 }, wait_for_response: false)

        expect(transport).not_to have_received(:start_sse_stream)
        expect(result).to be_nil
      end
    end

    describe "SSE reconnection logic" do
      context "when implementing exponential backoff" do
        let(:reconnection_options) do
          {
            max_reconnection_delay: 10_000,
            initial_reconnection_delay: 100,
            reconnection_delay_grow_factor: 2.0,
            max_retries: 3
          }
        end

        let(:transport_with_options) do
          RubyLLM::MCP::Native::Transports::StreamableHTTP.new(
            url: TestServerManager::HTTP_SERVER_URL,
            request_timeout: 5000,
            coordinator: mock_coordinator,
            options: { reconnection: reconnection_options }
          )
        end

        it "calculates delays correctly" do
          expect(transport_with_options.send(:calculate_reconnection_delay, 0)).to eq(100)
          expect(transport_with_options.send(:calculate_reconnection_delay, 1)).to eq(200)
          expect(transport_with_options.send(:calculate_reconnection_delay, 2)).to eq(400)
          expect(transport_with_options.send(:calculate_reconnection_delay, 10)).to eq(10_000) # Capped at max
        end
      end

      context "when respecting max retry limit" do
        let(:reconnection_options) { { max_retries: 1 } }
        let(:transport_with_options) do
          RubyLLM::MCP::Native::Transports::StreamableHTTP.new(
            url: TestServerManager::HTTP_SERVER_URL,
            request_timeout: 1000,
            coordinator: mock_coordinator,
            options: { reconnection: reconnection_options }
          )
        end

        before do
          stub_request(:get, TestServerManager::HTTP_SERVER_URL)
            .with(headers: { "Accept" => "text/event-stream" })
            .to_raise(Errno::ECONNREFUSED)
        end

        it "stops after max retries" do
          options = RubyLLM::MCP::Native::Transports::StartSSEOptions.new

          expect do
            transport_with_options.send(:start_sse, options)
          end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Connection refused/)
        end
      end

      it "stops retrying when transport is closed" do
        transport.instance_variable_set(:@running, false)

        stub_request(:get, TestServerManager::HTTP_SERVER_URL)
          .with(headers: { "Accept" => "text/event-stream" })
          .to_raise(Errno::ECONNREFUSED)

        options = RubyLLM::MCP::Native::Transports::StartSSEOptions.new

        expect do
          transport.send(:start_sse, options)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Connection refused/)
      end

      it "returns a 400 error if server is not running" do
        transport.instance_variable_set(:@running, false)

        stub_request(:get, "http://fakeurl:4000/mcp")
          .with(headers: { "Accept" => "text/event-stream" })
          .to_raise(Errno::ECONNREFUSED)

        options = RubyLLM::MCP::Native::Transports::StartSSEOptions.new

        expect do
          transport.send(:start_sse, options)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Failed to open SSE stream: 400/)
      end

      it "stops retrying when abort controller is set" do
        transport.instance_variable_set(:@abort_controller, true)

        stub_request(:get, TestServerManager::HTTP_SERVER_URL)
          .with(headers: { "Accept" => "text/event-stream" })
          .to_raise(Errno::ECONNREFUSED)

        options = RubyLLM::MCP::Native::Transports::StartSSEOptions.new

        expect do
          transport.send(:start_sse, options)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Connection refused/)
      end
    end

    describe "edge cases and boundary conditions" do
      it "handles response without jsonrpc field" do
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: '{"result": "ok"}' # Missing jsonrpc field
          )

        expect do
          transport.request({ "method" => "test", "id" => 1 }, wait_for_response: false)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Invalid JSON-RPC envelope/)
      end

      it "handles request without ID gracefully" do
        session_id = SecureRandom.uuid

        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json", "mcp-session-id" => session_id },
            body: {
              "jsonrpc" => "2.0",
              "id" => nil,
              "result" => { "content" => [{ "type" => "text", "value" => "ok" }] }
            }.to_json
          )

        # Request without ID should be handled properly (notification)
        result = transport.request({ "method" => "test" }, wait_for_response: false)
        expect(result.session_id).to eq(session_id)
      end

      it "handles very large response gracefully" do
        large_response = {
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => { "content" => [{ "type" => "text", "value" => "x" * 10_000 }] }
        }

        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: large_response.to_json
          )

        # Very large response should be handled properly
        result = transport.request({ "method" => "test", "id" => 1 }, wait_for_response: false)
        expect(result.result["content"][0]["value"]).to eq("x" * 10_000)
      end

      it "handles response with event-stream content type" do
        allow(transport).to receive(:start_sse_stream)
        stub_request(:post, TestServerManager::HTTP_SERVER_URL)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "text/event-stream" },
            body: "data: test\n\n"
          )

        result = transport.request({ "method" => "test", "id" => 1 }, wait_for_response: false)

        expect(transport).to have_received(:start_sse_stream)
        expect(result).to be_nil
      end

      context "when handling session ID extraction from response headers" do
        before do
          stub_request(:post, TestServerManager::HTTP_SERVER_URL)
            .to_return(
              status: 200,
              headers: {
                "Content-Type" => "application/json",
                "mcp-session-id" => "new-session-123"
              },
              body: {
                "jsonrpc" => "2.0",
                "id" => 1,
                "result" => { "content" => [{ "type" => "text", "value" => "ok" }] }
              }.to_json
            )
        end

        it "extracts session ID correctly" do
          result = transport.request({ "method" => "test", "id" => 1 }, wait_for_response: false)
          expect(result.session_id).to eq("new-session-123")
        end
      end

      context "when response has malformed JSON" do
        before do
          stub_request(:post, TestServerManager::HTTP_SERVER_URL)
            .to_return(
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: "invalid json response"
            )
        end

        it "handles gracefully" do
          expect do
            transport.request({ "method" => "test", "id" => 1 }, wait_for_response: false)
          end.to raise_error(RubyLLM::MCP::Errors::TransportError)
        end
      end

      context "when handling HTTPX error response in main request" do
        before do
          stub_request(:post, TestServerManager::HTTP_SERVER_URL)
            .to_raise(Net::ReadTimeout.new("Connection timeout"))
        end

        it "raises appropriate error" do
          expect do
            transport.request({ "method" => "test", "id" => 1 })
          end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Connection timeout/)
        end
      end

      context "when HTTPX error response has no error message" do
        before do
          stub_request(:post, TestServerManager::HTTP_SERVER_URL)
            .to_return(status: 500, body: "Internal Server Error")
        end

        it "handles gracefully with default message" do
          expect do
            transport.request({ "method" => "test", "id" => 1 })
          end.to raise_error(RubyLLM::MCP::Errors::TransportError, /HTTP request failed: 500/)
        end
      end

      it "handles start_sse_stream when already closed" do
        transport.instance_variable_set(:@running, false)
        transport.instance_variable_set(:@abort_controller, true)

        # Should return early without creating thread
        result = transport.send(:start_sse_stream)
        expect(result).to be_nil

        # No SSE thread should be created
        expect(transport.instance_variable_get(:@sse_thread)).to be_nil
      end

      context "when SSE thread is already alive" do
        let(:mock_thread) { instance_double(Thread) }

        before do
          allow(mock_thread).to receive(:alive?).and_return(true)
          transport.instance_variable_set(:@sse_thread, mock_thread)
          allow(Thread).to receive(:new)
        end

        it "doesn't create new thread" do
          transport.send(:start_sse_stream)

          expect(Thread).not_to have_received(:new)
        end
      end
    end

    describe "SSE event parsing" do
      it "extracts SSE events correctly" do
        buffer = +"data: test message\nevent: notification\nid: 123\n\ndata: second\n\n"

        result = transport.send(:extract_sse_event, buffer)
        parsed_event, remaining = result

        expect(parsed_event[:data]).to eq("test message")
        expect(parsed_event[:event]).to eq("notification")
        expect(parsed_event[:id]).to eq("123")
        expect(remaining).to eq("data: second\n\n")
      end

      it "handles SSE events without complete data" do
        buffer = +"data: incomplete"

        result = transport.send(:extract_sse_event, buffer)
        expect(result).to be_nil
      end

      it "parses multi-line data correctly" do
        raw = "data: line 1\ndata: line 2\nevent: test"

        parsed = transport.send(:parse_sse_event, raw)
        expect(parsed[:data]).to eq("line 1\nline 2")
        expect(parsed[:event]).to eq("test")
      end

      context "when handling SSE response processing for different message types" do
        let(:mock_result) { instance_double(RubyLLM::MCP::Result) }

        before do
          allow(mock_coordinator).to receive(:process_result)
          allow(RubyLLM::MCP::Result).to receive(:new).and_return(mock_result)
        end

        it "processes notifications correctly" do
          notification_event = { data: '{"jsonrpc": "2.0", "method": "test_notification"}' }
          allow(mock_result).to receive_messages(notification?: true, request?: false, response?: false)

          transport.send(:process_sse_event, notification_event, nil)

          expect(mock_coordinator).to have_received(:process_result)
        end

        it "processes requests correctly" do
          request_event = { data: '{"jsonrpc": "2.0", "method": "test_request", "id": "req-1"}' }
          allow(mock_result).to receive_messages(notification?: false, request?: true, response?: false, id: "req-1")
          allow(mock_coordinator).to receive(:process_result).and_return(mock_result)

          transport.send(:process_sse_event, request_event, nil)

          expect(mock_coordinator).to have_received(:process_result)
        end
      end

      context "when handling SSE response type with request ID" do
        let(:response_queue) { Queue.new }
        let(:request_id) { "test-response-123" }
        let(:mock_result) { instance_double(RubyLLM::MCP::Result) }

        before do
          transport.instance_variable_get(:@pending_mutex).synchronize do
            transport.instance_variable_get(:@pending_requests)[request_id] = response_queue
          end
          allow(mock_result).to receive_messages(notification?: false, request?: false, response?: true, id: request_id)
          allow(mock_coordinator).to receive(:process_result).and_return(mock_result)
          allow(RubyLLM::MCP::Result).to receive(:new).and_return(mock_result)
        end

        it "queues response and removes from pending" do
          response_event = { data: "{\"jsonrpc\": \"2.0\", \"id\": \"#{request_id}\", \"result\": \"success\"}" }

          # Start a thread to check the queue
          result_thread = Thread.new do
            response_queue.pop
          end

          transport.send(:process_sse_event, response_event, nil)

          # Wait for the response to be queued
          result = result_thread.value
          expect(result).to eq(mock_result)

          # Request should be removed from pending
          pending_requests = transport.instance_variable_get(:@pending_requests)
          expect(pending_requests).not_to have_key(request_id)
        end
      end

      context "when handling replay message ID in SSE processing" do
        let(:replay_id) { "replay-123" }
        let(:original_event) { { data: '{"jsonrpc": "2.0", "id": "original-456", "method": "test"}' } }

        before do
          allow(JSON).to receive(:parse).with('{"jsonrpc": "2.0", "id": "original-456", "method": "test"}').and_return(
            { "jsonrpc" => "2.0", "id" => "original-456", "method" => "test" }
          )
          allow(mock_coordinator).to receive(:process_result)
        end

        it "processes with replay ID" do
          mock_result = instance_double(RubyLLM::MCP::Result)
          allow(mock_result).to receive_messages(notification?: true, request?: false, response?: false)
          allow(RubyLLM::MCP::Result).to receive(:new).and_return(mock_result)

          transport.send(:process_sse_event, original_event, replay_id)

          expect(mock_coordinator).to have_received(:process_result)
        end
      end
    end
  end

  describe "Protocol Version 2025-06-18 Negotiation" do
    it "includes MCP-Protocol-Version header in subsequent requests" do
      client.start

      # Any operation should succeed if protocol version header is properly set
      tools = client.tools
      expect(tools).to be_an(Array)
      expect(tools.length).to be > 0

      client.stop
    end

    it "maintains protocol version consistency across operations" do
      client.start

      # Multiple operations should all work consistently with the same protocol version
      expect(client.tools.length).to be > 0
      expect(client.resources.length).to be > 0
      expect(client.ping).to be(true)

      # Execute a tool to verify full round-trip functionality
      tool = client.tool("add")
      result = tool.execute(a: 5, b: 3)
      expect(result).to be_a(RubyLLM::MCP::Content)
      expect(result.to_s).to eq("8")

      client.stop
    end
  end

  describe "OAuth integration" do
    let(:server_url) { "http://localhost:3000/mcp" }
    let(:storage) { RubyLLM::MCP::Auth::MemoryStorage.new }

    it "accepts OAuth provider in options" do
      oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
        server_url: server_url,
        storage: storage
      )

      transport = described_class.new(
        url: server_url,
        coordinator: mock_coordinator,
        request_timeout: 5000,
        options: { oauth_provider: oauth_provider }
      )

      expect(transport.oauth_provider).to eq(oauth_provider)
    end

    it "applies OAuth authorization header when token available" do
      oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
        server_url: server_url,
        storage: storage
      )

      token = RubyLLM::MCP::Auth::Token.new(
        access_token: "test_access_token",
        expires_in: 3600
      )
      storage.set_token(server_url, token)

      transport = described_class.new(
        url: server_url,
        coordinator: mock_coordinator,
        request_timeout: 5000,
        options: { oauth_provider: oauth_provider }
      )

      headers = transport.send(:build_common_headers)

      expect(headers["Authorization"]).to eq("Bearer test_access_token")
    end

    it "does not apply OAuth header when no token available" do
      oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
        server_url: server_url,
        storage: storage
      )

      transport = described_class.new(
        url: server_url,
        coordinator: mock_coordinator,
        request_timeout: 5000,
        options: { oauth_provider: oauth_provider }
      )

      headers = transport.send(:build_common_headers)

      expect(headers["Authorization"]).to be_nil
    end

    it "works without OAuth provider" do
      transport = described_class.new(
        url: server_url,
        coordinator: mock_coordinator,
        request_timeout: 5000,
        options: {}
      )

      expect(transport.oauth_provider).to be_nil

      headers = transport.send(:build_common_headers)
      expect(headers["Authorization"]).to be_nil
    end

    context "with enhanced OAuth logging" do
      before do
        allow(logger).to receive(:debug)
        allow(logger).to receive(:warn)
        allow(logger).to receive(:info)
        allow(logger).to receive(:error)
      end

      it "logs detailed information when OAuth provider present and token available" do
        oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
          server_url: server_url,
          storage: storage
        )

        token = RubyLLM::MCP::Auth::Token.new(
          access_token: "test_access_token_12345",
          expires_in: 3600
        )
        storage.set_token(server_url, token)

        transport = described_class.new(
          url: server_url,
          coordinator: mock_coordinator,
          request_timeout: 5000,
          options: { oauth_provider: oauth_provider }
        )

        transport.send(:build_common_headers)

        expect(logger).to have_received(:debug).with(/OAuth provider present, attempting to get token/)
        expect(logger).to have_received(:debug).with(/Server URL:/)
        expect(logger).to have_received(:debug)
          .with(/Applied OAuth authorization header: Bearer test_access_token_12345/)
      end

      it "logs warning when OAuth provider present but no token available" do
        oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
          server_url: server_url,
          storage: storage
        )

        transport = described_class.new(
          url: server_url,
          coordinator: mock_coordinator,
          request_timeout: 5000,
          options: { oauth_provider: oauth_provider }
        )

        transport.send(:build_common_headers)

        expect(logger).to have_received(:warn).with(/OAuth provider present but no valid token available/)
        expect(logger).to have_received(:warn).with(/This means the token is not in storage or has expired/)
        expect(logger).to have_received(:warn).with(/Check that authentication completed successfully/)
      end

      it "logs debug when no OAuth provider configured" do
        transport = described_class.new(
          url: server_url,
          coordinator: mock_coordinator,
          request_timeout: 5000,
          options: {}
        )

        transport.send(:build_common_headers)

        expect(logger).to have_received(:debug).with("No OAuth provider configured for this transport")
      end
    end

    context "with enhanced error handling" do
      let(:response) { instance_double(HTTPX::Response) }

      before do
        allow(logger).to receive(:debug)
        allow(logger).to receive(:warn)
        allow(logger).to receive(:info)
        allow(logger).to receive(:error)
      end

      it "handles 403 Forbidden with OAuth provider and provides helpful error" do
        oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
          server_url: server_url,
          storage: storage
        )

        transport = described_class.new(
          url: server_url,
          coordinator: mock_coordinator,
          request_timeout: 5000,
          options: { oauth_provider: oauth_provider }
        )

        error_body = '{"error": {"message": "Invalid scope"}}'
        allow(response).to receive_messages(status: 403, body: error_body)
        allow(response).to receive(:respond_to?).with(:body).and_return(true)
        allow(response).to receive(:respond_to?).with(:status).and_return(true)

        expect do
          transport.send(:handle_client_error, response)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError,
                           /Authorization failed \(403 Forbidden\).*Invalid scope.*Check token scope/)
      end

      it "parses JSON error responses and extracts error message" do
        transport = described_class.new(
          url: server_url,
          coordinator: mock_coordinator,
          request_timeout: 5000,
          options: {}
        )

        error_body = '{"error": {"message": "Token expired", "code": "token_expired"}}'
        allow(response).to receive_messages(status: 401, body: error_body)
        allow(response).to receive(:respond_to?).with(:body).and_return(true)
        allow(response).to receive(:respond_to?).with(:status).and_return(true)

        expect do
          transport.send(:handle_client_error, response)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Token expired/)
      end

      it "handles empty error messages gracefully" do
        transport = described_class.new(
          url: server_url,
          coordinator: mock_coordinator,
          request_timeout: 5000,
          options: {}
        )

        error_body = '{"error": {"message": "", "code": ""}}'
        allow(response).to receive_messages(status: 400, body: error_body)
        allow(response).to receive(:respond_to?).with(:body).and_return(true)
        allow(response).to receive(:respond_to?).with(:status).and_return(true)

        expect do
          transport.send(:handle_client_error, response)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Empty error \(full response:/)
      end

      it "handles non-JSON error responses" do
        transport = described_class.new(
          url: server_url,
          coordinator: mock_coordinator,
          request_timeout: 5000,
          options: {}
        )

        error_body = "Plain text error message"
        allow(response).to receive_messages(status: 500, body: error_body)
        allow(response).to receive(:respond_to?).with(:body).and_return(true)
        allow(response).to receive(:respond_to?).with(:status).and_return(true)

        expect do
          transport.send(:handle_client_error, response)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Plain text error message/)
      end
    end
  end
end
