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
        oauth_provider: oauth_provider
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

    context "with authentication challenges" do
      let(:mock_response) { instance_double(HTTPX::Response) }

      before do
        allow(mock_response).to receive(:headers).and_return({
          "www-authenticate" => 'Bearer scope="mcp:read"',
          "mcp-resource-metadata-url" => "https://example.com/meta"
        })
        allow(mock_response).to receive(:status).and_return(401)
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
        allow(transport_with_oauth).to receive(:send_request).and_call_original

        # Mock the retry to succeed
        allow(RubyLLM::MCP::Native::Transports::Support::HTTPClient).to receive(:connection).and_return(
          double(with: double(post: double(status: 200, headers: {})))
        )

        expect do
          transport_with_oauth.send(:handle_authentication_challenge, mock_response, { "method" => "test" }, 1)
        end.not_to raise_error
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
    end
  end
end
