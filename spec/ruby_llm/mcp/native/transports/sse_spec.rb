# frozen_string_literal: true

class Runner
  class << self
    def instance
      @instance ||= Runner.new
    end
  end

  def start
    client.start
  end

  def stop
    client&.stop
  end

  def client
    @client ||= RubyLLM::MCP::Client.new(
      name: "fast-mcp-ruby",
      transport_type: :sse,
      config: {
        url: "http://localhost:#{TestServerManager::PORTS[:sse]}/mcp/sse",
        version: :http1
      }
    )
  end
end

RSpec.describe RubyLLM::MCP::Native::Transports::SSE do
  let(:client) { Runner.instance.client }

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Runner.instance.start
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Runner.instance.stop
  end

  describe "start" do
    it "starts the transport" do
      expect(client.alive?).to be(true)
    end
  end

  describe "#request" do
    it "can get tool list" do
      tools = client.tools
      expect(tools.count).to eq(2)
    end

    it "can execute a tool" do
      tool = client.tool("CalculateTool")
      result = tool.execute(operation: "add", x: 1.0, y: 2.0)
      expect(result.to_s).to eq("3.0")
    end

    it "can get resource list" do
      resources = client.resources
      expect(resources.count).to eq(1)
    end
  end

  describe "HTTP/2 compatibility" do
    it "does not include Connection header (forbidden in HTTP/2)" do
      coordinator = instance_double(RubyLLM::MCP::Adapters::MCPTransports::CoordinatorStub)
      transport = RubyLLM::MCP::Native::Transports::SSE.new(
        url: "http://localhost:3000/sse",
        coordinator: coordinator,
        request_timeout: 5000
      )

      # Verify that the Connection header is not set
      expect(transport.headers).not_to have_key("Connection")

      # Verify we still have the essential headers
      expect(transport.headers).to include(
        "Accept" => "text/event-stream",
        "Content-Type" => "application/json",
        "Cache-Control" => "no-cache"
      )
      expect(transport.headers).to have_key("X-CLIENT-ID")
    end
  end

  describe "thread safety and lifecycle" do
    let(:coordinator) { instance_double(RubyLLM::MCP::Adapters::MCPTransports::CoordinatorStub) }
    let(:transport) do
      RubyLLM::MCP::Native::Transports::SSE.new(
        url: "http://localhost:3000/sse",
        coordinator: coordinator,
        request_timeout: 5000
      )
    end

    describe "#running?" do
      it "safely checks running state with mutex" do
        expect(transport.running?).to be(false) # Not started yet

        # Simulate concurrent access
        threads = 10.times.map do
          Thread.new { transport.running? }
        end

        results = threads.map(&:value)
        expect(results).to all(be(false))
      end
    end

    describe "#close" do
      it "handles multiple close calls gracefully" do
        expect { transport.close }.not_to raise_error
        expect { transport.close }.not_to raise_error
        expect(transport.running?).to be(false)
      end

      it "resets messages_url on close" do
        transport.instance_variable_set(:@messages_url, "http://test.com/messages")
        transport.instance_variable_set(:@running, true)

        transport.close

        expect(transport.instance_variable_get(:@messages_url)).to be_nil
      end

      it "is idempotent when called multiple times" do
        transport.instance_variable_set(:@running, true)

        expect { 3.times { transport.close } }.not_to raise_error
        expect(transport.running?).to be(false)
      end
    end
  end

  describe "pending request cleanup" do
    let(:coordinator) { instance_double(RubyLLM::MCP::Adapters::MCPTransports::CoordinatorStub) }
    let(:transport) do
      RubyLLM::MCP::Native::Transports::SSE.new(
        url: "http://localhost:3000/sse",
        coordinator: coordinator,
        request_timeout: 5000
      )
    end

    describe "#fail_pending_requests!" do
      it "pushes error to all pending request queues" do
        queue1 = Queue.new
        queue2 = Queue.new

        transport.instance_variable_get(:@pending_requests)["1"] = queue1
        transport.instance_variable_get(:@pending_requests)["2"] = queue2

        error = RubyLLM::MCP::Errors::TransportError.new(
          message: "Test error",
          code: nil
        )

        transport.send(:fail_pending_requests!, error)

        expect(queue1.pop).to eq(error)
        expect(queue2.pop).to eq(error)
        expect(transport.instance_variable_get(:@pending_requests)).to be_empty
      end

      it "clears all pending requests after pushing errors" do
        3.times do |i|
          transport.instance_variable_get(:@pending_requests)[i.to_s] = Queue.new
        end

        error = RubyLLM::MCP::Errors::TransportError.new(message: "Test", code: nil)
        transport.send(:fail_pending_requests!, error)

        expect(transport.instance_variable_get(:@pending_requests)).to be_empty
      end
    end

    describe "#close" do
      it "fails all pending requests with transport error" do
        queue = Queue.new
        transport.instance_variable_get(:@pending_requests)["test"] = queue
        transport.instance_variable_set(:@running, true)

        result_thread = Thread.new { queue.pop }
        sleep(0.05) # Let thread start waiting

        transport.close

        result = result_thread.value
        expect(result).to be_a(RubyLLM::MCP::Errors::TransportError)
        expect(result.message).to include("closed")
      end

      it "wakes up multiple waiting requests" do
        queues = 3.times.map do |i|
          queue = Queue.new
          transport.instance_variable_get(:@pending_requests)[i.to_s] = queue
          queue
        end
        transport.instance_variable_set(:@running, true)

        threads = queues.map { |q| Thread.new { q.pop } }
        sleep(0.05) # Let threads start waiting

        transport.close

        results = threads.map(&:value)
        expect(results).to all(be_a(RubyLLM::MCP::Errors::TransportError))
      end
    end
  end

  describe "endpoint bootstrapping" do
    let(:coordinator) { instance_double(RubyLLM::MCP::Adapters::MCPTransports::CoordinatorStub) }
    let(:transport) do
      RubyLLM::MCP::Native::Transports::SSE.new(
        url: "http://localhost:3000/sse",
        coordinator: coordinator,
        request_timeout: 5000
      )
    end

    describe "#set_message_endpoint" do
      it "handles string endpoints" do
        transport.send(:set_message_endpoint, "/messages")
        expect(transport.instance_variable_get(:@messages_url)).to eq("http://localhost:3000/messages")
      end

      it "handles JSON payloads with url key (string)" do
        transport.send(:set_message_endpoint, { "url" => "/api/messages" })
        expect(transport.instance_variable_get(:@messages_url)).to eq("http://localhost:3000/api/messages")
      end

      it "handles JSON payloads with url key (symbol)" do
        transport.send(:set_message_endpoint, { url: "/api/messages" })
        expect(transport.instance_variable_get(:@messages_url)).to eq("http://localhost:3000/api/messages")
      end

      it "raises error for missing URL in hash" do
        expect do
          transport.send(:set_message_endpoint, { "other" => "value" })
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /missing URL/)
      end

      it "raises error for invalid URI" do
        expect do
          transport.send(:set_message_endpoint, "ht!tp://invalid")
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Invalid endpoint URL/)
      end

      it "handles absolute URLs" do
        transport.send(:set_message_endpoint, "http://other.com:8080/messages")
        expect(transport.instance_variable_get(:@messages_url)).to eq("http://other.com:8080/messages")
      end

      it "raises error for empty string" do
        expect do
          transport.send(:set_message_endpoint, "")
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /missing URL/)
      end

      it "raises error for nil" do
        expect do
          transport.send(:set_message_endpoint, nil)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /missing URL/)
      end
    end

    describe "#process_endpoint_event" do
      it "parses JSON endpoint data" do
        raw_event = { data: '{"url": "/messages", "last_event_id": "123"}' }

        queue = Queue.new
        transport.instance_variable_get(:@pending_requests)["endpoint"] = queue

        result_thread = Thread.new { queue.pop }

        transport.send(:process_endpoint_event, raw_event)

        result = result_thread.value
        expect(result).to be_a(Hash)
        expect(result["url"]).to eq("/messages")
        expect(result["last_event_id"]).to eq("123")
      end

      it "falls back to string for non-JSON data" do
        raw_event = { data: "/messages" }

        queue = Queue.new
        transport.instance_variable_get(:@pending_requests)["endpoint"] = queue

        result_thread = Thread.new { queue.pop }

        transport.send(:process_endpoint_event, raw_event)

        result = result_thread.value
        expect(result).to eq("/messages")
      end

      it "removes endpoint from pending requests after processing" do
        raw_event = { data: "/messages" }

        queue = Queue.new
        transport.instance_variable_get(:@pending_requests)["endpoint"] = queue

        result_thread = Thread.new { queue.pop }

        transport.send(:process_endpoint_event, raw_event)
        result_thread.value

        expect(transport.instance_variable_get(:@pending_requests)).not_to have_key("endpoint")
      end
    end
  end

  describe "event processing improvements" do
    let(:coordinator) { instance_double(RubyLLM::MCP::Adapters::MCPTransports::CoordinatorStub) }
    let(:transport) do
      RubyLLM::MCP::Native::Transports::SSE.new(
        url: "http://localhost:3000/sse",
        coordinator: coordinator,
        request_timeout: 5000
      )
    end

    before do
      allow(RubyLLM::MCP.logger).to receive(:debug)
      allow(RubyLLM::MCP.logger).to receive(:info)
      allow(RubyLLM::MCP.logger).to receive(:error)
    end

    describe "#process_message_event" do
      it "logs at debug level for parse errors when messages_url is set" do
        transport.instance_variable_set(:@messages_url, "http://test.com/messages")
        raw_event = { data: "invalid json" }

        transport.send(:process_message_event, raw_event)

        expect(RubyLLM::MCP.logger).to have_received(:debug).with(/Failed to parse SSE event data/)
      end

      it "does not log parse errors when messages_url is not set" do
        transport.instance_variable_set(:@messages_url, nil)
        raw_event = { data: "invalid json" }

        transport.send(:process_message_event, raw_event)

        # Should not log the specific parse error message
        expect(RubyLLM::MCP.logger).not_to have_received(:debug).with(/Failed to parse SSE event data/)
      end

      it "processes valid JSON events" do
        raw_event = { data: '{"jsonrpc": "2.0", "id": "123", "result": {"success": true}}' }
        result = instance_double(RubyLLM::MCP::Result)

        allow(RubyLLM::MCP::Result).to receive(:new).and_return(result)
        allow(result).to receive(:matching_id?).with("123").and_return(true)
        allow(coordinator).to receive(:process_result).and_return(result)

        queue = Queue.new
        transport.instance_variable_get(:@pending_requests)["123"] = queue

        result_thread = Thread.new { queue.pop }

        transport.send(:process_message_event, raw_event)

        received = result_thread.value
        expect(received).to eq(result)
      end
    end
  end

  describe "#parse_event" do
    let(:transport) do
      RubyLLM::MCP::Native::Transports::SSE.new(
        url: "http://localhost:3000/sse",
        coordinator: instance_double(RubyLLM::MCP::Adapters::MCPTransports::CoordinatorStub),
        request_timeout: 5000
      )
    end

    context "with a single event" do
      it "parses a simple SSE event" do
        raw_event = "data: {\"message\": \"hello\"}\nevent: message\nid: 123"
        events = transport.send(:parse_event, raw_event)

        expect(events).to be_an(Array)
        expect(events.length).to eq(1)
        expect(events[0][:data]).to eq("{\"message\": \"hello\"}")
        expect(events[0][:event]).to eq("message")
        expect(events[0][:id]).to eq("123")
      end

      it "parses multi-line data" do
        raw_event = "data: line1\ndata: line2\ndata: line3\nevent: test"
        events = transport.send(:parse_event, raw_event)

        expect(events.length).to eq(1)
        expect(events[0][:data]).to eq("line1\nline2\nline3")
        expect(events[0][:event]).to eq("test")
      end

      it "handles events with only data" do
        raw_event = "data: {\"content\": \"test\"}"
        events = transport.send(:parse_event, raw_event)

        expect(events.length).to eq(1)
        expect(events[0][:data]).to eq("{\"content\": \"test\"}")
        expect(events[0][:event]).to be_nil
        expect(events[0][:id]).to be_nil
      end
    end

    context "with multiple events in one payload" do
      it "parses two events separated by double newlines" do
        raw_events = <<~EVENTS.strip
          data: {"message": "first"}
          event: message
          id: 1


          data: {"message": "second"}
          event: message
          id: 2
        EVENTS

        events = transport.send(:parse_event, raw_events)

        expect(events.length).to eq(2)

        expect(events[0][:data]).to eq("{\"message\": \"first\"}")
        expect(events[0][:event]).to eq("message")
        expect(events[0][:id]).to eq("1")

        expect(events[1][:data]).to eq("{\"message\": \"second\"}")
        expect(events[1][:event]).to eq("message")
        expect(events[1][:id]).to eq("2")
      end

      it "parses three events with different formats" do
        raw_events = <<~EVENTS.strip
          data: {"type": "start"}
          event: start


          data: line1
          data: line2
          event: multiline
          id: middle


          data: {"type": "end"}
        EVENTS

        events = transport.send(:parse_event, raw_events)

        expect(events.length).to eq(3)

        expect(events[0][:data]).to eq("{\"type\": \"start\"}")
        expect(events[0][:event]).to eq("start")

        expect(events[1][:data]).to eq("line1\nline2")
        expect(events[1][:event]).to eq("multiline")
        expect(events[1][:id]).to eq("middle")

        expect(events[2][:data]).to eq("{\"type\": \"end\"}")
        expect(events[2][:event]).to be_nil
      end

      it "handles events separated by newlines with whitespace" do
        raw_events = "data: first\n \t \n\ndata: second"
        events = transport.send(:parse_event, raw_events)

        expect(events.length).to eq(2)
        expect(events[0][:data]).to eq("first")
        expect(events[1][:data]).to eq("second")
      end
    end

    it "filters out empty events" do
      raw_events = "data: valid\n\n\n\n\ndata: also_valid"
      events = transport.send(:parse_event, raw_events)

      expect(events.length).to eq(2)
      expect(events[0][:data]).to eq("valid")
      expect(events[1][:data]).to eq("also_valid")
    end

    it "filters out events without data" do
      raw_events = "event: no_data\n\n\ndata: has_data\nevent: valid"
      events = transport.send(:parse_event, raw_events)

      expect(events.length).to eq(1)
      expect(events[0][:data]).to eq("has_data")
      expect(events[0][:event]).to eq("valid")
    end

    it "handles empty input" do
      events = transport.send(:parse_event, "")
      expect(events).to eq([])
    end

    it "handles input with only whitespace" do
      events = transport.send(:parse_event, "   \n\n\t\n   ")
      expect(events).to eq([])
    end
  end

  describe "OAuth integration" do
    let(:server_url) { "http://localhost:3000/sse" }
    let(:storage) { RubyLLM::MCP::Auth::MemoryStorage.new }
    let(:oauth_provider) do
      RubyLLM::MCP::Auth::OAuthProvider.new(
        server_url: server_url,
        storage: storage
      )
    end
    let(:coordinator) { instance_double(RubyLLM::MCP::Adapters::MCPTransports::CoordinatorStub) }
    let(:transport_with_oauth) do
      RubyLLM::MCP::Native::Transports::SSE.new(
        url: server_url,
        coordinator: coordinator,
        request_timeout: 5000,
        options: { oauth_provider: oauth_provider }
      )
    end

    it "accepts OAuth provider in initialization" do
      expect(transport_with_oauth.instance_variable_get(:@oauth_provider)).to eq(oauth_provider)
    end

    it "applies OAuth authorization header to requests" do
      token = RubyLLM::MCP::Auth::Token.new(
        access_token: "test_token",
        expires_in: 3600
      )
      storage.set_token(server_url, token)

      headers = transport_with_oauth.send(:build_request_headers)

      expect(headers["Authorization"]).to eq("Bearer test_token")
    end

    it "does not apply OAuth header when no token available" do
      headers = transport_with_oauth.send(:build_request_headers)

      expect(headers["Authorization"]).to be_nil
    end

    it "applies OAuth authorization header to SSE stream connection requests" do
      token = RubyLLM::MCP::Auth::Token.new(
        access_token: "stream_token",
        expires_in: 3600
      )
      storage.set_token(server_url, token)

      stream_plugin = instance_double(HTTPX::Session)
      allow(HTTPX).to receive(:plugin).and_call_original
      allow(HTTPX).to receive(:plugin).with(:stream).and_return(stream_plugin)
      allow(stream_plugin).to receive(:with).and_return(stream_plugin)

      transport_with_oauth.send(:create_sse_client)

      expect(stream_plugin).to have_received(:with).with(
        headers: hash_including("Authorization" => "Bearer stream_token")
      )
    end

    context "with authentication challenges" do
      let(:mock_response) { instance_double(HTTPX::Response) }

      before do
        allow(mock_response).to receive_messages(headers: {
                                                   "www-authenticate" => 'Bearer scope="mcp:read"',
                                                   "mcp-resource-metadata-url" => "https://example.com/meta"
                                                 }, status: 401)
      end

      it "handles 401 during message POST" do
        transport_with_oauth.instance_variable_set(:@messages_url, "http://localhost:3000/messages")

        allow(oauth_provider).to receive(:handle_authentication_challenge).and_raise(
          RubyLLM::MCP::Errors::AuthenticationRequiredError.new(message: "Auth required")
        )

        expect do
          transport_with_oauth.send(:handle_authentication_challenge, mock_response, {}, 1)
        end.to raise_error(RubyLLM::MCP::Errors::AuthenticationRequiredError)

        expect(oauth_provider).to have_received(:handle_authentication_challenge)
      end

      it "retries request after successful authentication" do
        transport_with_oauth.instance_variable_set(:@messages_url, "http://localhost:3000/messages")

        new_token = RubyLLM::MCP::Auth::Token.new(
          access_token: "new_token",
          expires_in: 3600
        )
        storage.set_token(server_url, new_token)

        allow(oauth_provider).to receive(:handle_authentication_challenge).and_return(true)

        # Mock the retry to succeed by stubbing send_request
        allow(transport_with_oauth).to receive(:send_request).and_return(nil)

        expect do
          transport_with_oauth.send(:handle_authentication_challenge, mock_response, { "method" => "test" }, 1)
        end.not_to raise_error
      end

      it "handles 403 insufficient_scope during message POST" do
        transport_with_oauth.instance_variable_set(:@messages_url, "http://localhost:3000/messages")
        forbidden_response = instance_double(
          HTTPX::Response,
          headers: {
            "www-authenticate" => 'Bearer error="insufficient_scope", scope="mcp:write"',
            "mcp-resource-metadata-url" => "https://example.com/meta"
          },
          status: 403,
          body: "forbidden"
        )

        allow(oauth_provider).to receive(:handle_authentication_challenge).and_return(true)
        allow(transport_with_oauth).to receive(:send_request).and_return(nil)

        expect do
          transport_with_oauth.send(:handle_authorization_challenge, forbidden_response, { "method" => "test" }, 1)
        end.not_to raise_error

        expect(oauth_provider).to have_received(:handle_authentication_challenge).with(
          hash_including(www_authenticate: /insufficient_scope/, resource_metadata: "https://example.com/meta")
        )
      end

      it "prevents infinite retry loop" do
        transport_with_oauth.instance_variable_set(:@messages_url, "http://localhost:3000/messages")
        transport_with_oauth.instance_variable_set(:@auth_retry_attempted, true)

        expect do
          transport_with_oauth.send(:handle_authentication_challenge, mock_response, {}, 1)
        end.to raise_error(RubyLLM::MCP::Errors::AuthenticationRequiredError, /retry failed/)
      end

      it "handles SSE stream 401 authentication" do
        allow(oauth_provider).to receive(:handle_authentication_challenge).and_return(true)

        expect do
          transport_with_oauth.send(:handle_sse_authentication_challenge, mock_response)
        end.not_to raise_error

        expect(oauth_provider).to have_received(:handle_authentication_challenge)
      end

      it "raises error when SSE auth fails" do
        allow(oauth_provider).to receive(:handle_authentication_challenge).and_raise(
          RubyLLM::MCP::Errors::AuthenticationRequiredError.new(message: "Auth failed")
        )

        expect do
          transport_with_oauth.send(:handle_sse_authentication_challenge, mock_response)
        end.to raise_error(RubyLLM::MCP::Errors::AuthenticationRequiredError)
      end

      it "routes SSE stream 403 with OAuth challenge through authentication handler" do
        forbidden_response = instance_double(
          HTTPX::Response,
          status: 403,
          headers: { "www-authenticate" => 'Bearer error="insufficient_scope", scope="mcp:write"' }
        )
        allow(transport_with_oauth).to receive(:handle_sse_authentication_challenge)

        transport_with_oauth.send(:validate_sse_response!, forbidden_response)

        expect(transport_with_oauth).to have_received(:handle_sse_authentication_challenge).with(forbidden_response)
      end
    end
  end
end
