# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::BrowserOAuth do # rubocop:disable RSpec/SpecFilePathFormat
  let(:oauth_provider) { instance_double(RubyLLM::MCP::Auth::OAuthProvider) }
  let(:callback_port) { 8080 }
  let(:callback_path) { "/callback" }
  let(:logger) { instance_double(Logger) }
  let(:auth_url) { "https://mcp.example.com/oauth/authorize?client_id=abc&state=xyz" }
  let(:access_token) { "test_access_token" }
  let(:token) do
    RubyLLM::MCP::Auth::Token.new(
      access_token: access_token,
      expires_in: 3600
    )
  end

  before do
    allow(RubyLLM::MCP).to receive(:logger).and_return(logger)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
    allow(oauth_provider).to receive(:redirect_uri).and_return("http://localhost:8080/callback")
  end

  describe "#initialize" do
    it "initializes with oauth_provider and default settings" do
      browser_oauth = described_class.new(oauth_provider)

      expect(browser_oauth.oauth_provider).to eq(oauth_provider)
      expect(browser_oauth.callback_port).to eq(8080)
      expect(browser_oauth.callback_path).to eq("/callback")
      expect(browser_oauth.logger).to eq(logger)
    end

    it "accepts custom callback_port, callback_path, and logger" do
      custom_logger = instance_double(Logger)
      allow(oauth_provider).to receive(:redirect_uri).and_return("http://localhost:9090/auth/callback")
      browser_oauth = described_class.new(
        oauth_provider,
        callback_port: 9090,
        callback_path: "/auth/callback",
        logger: custom_logger
      )

      expect(browser_oauth.callback_port).to eq(9090)
      expect(browser_oauth.callback_path).to eq("/auth/callback")
      expect(browser_oauth.logger).to eq(custom_logger)
    end

    it "warns and updates redirect_uri if it doesn't match callback server" do
      allow(oauth_provider).to receive(:redirect_uri).and_return("http://localhost:3000/wrong")
      allow(oauth_provider).to receive(:redirect_uri=)

      described_class.new(oauth_provider, callback_port: 8080, callback_path: "/callback")

      expect(oauth_provider).to have_received(:redirect_uri=).with("http://localhost:8080/callback")
      expect(logger).to have_received(:warn).with(/doesn't match callback server/)
    end

    it "doesn't warn if redirect_uri matches callback server" do
      allow(oauth_provider).to receive(:redirect_uri).and_return("http://localhost:8080/callback")
      allow(oauth_provider).to receive(:redirect_uri=)

      described_class.new(oauth_provider, callback_port: 8080, callback_path: "/callback")

      expect(oauth_provider).not_to have_received(:redirect_uri=)
      expect(logger).not_to have_received(:warn)
    end

    it "accepts custom success page as string" do
      custom_page = "<html><body>Custom Success</body></html>"
      browser_oauth = described_class.new(oauth_provider, pages: { success_page: custom_page })

      expect(browser_oauth.custom_success_page).to eq(custom_page)
    end

    it "accepts custom success page as proc" do
      custom_page = -> { "<html><body>Custom Success</body></html>" }
      browser_oauth = described_class.new(oauth_provider, pages: { success_page: custom_page })

      expect(browser_oauth.custom_success_page).to eq(custom_page)
    end

    it "accepts custom error page as string" do
      custom_page = "<html><body>Custom Error</body></html>"
      browser_oauth = described_class.new(oauth_provider, pages: { error_page: custom_page })

      expect(browser_oauth.custom_error_page).to eq(custom_page)
    end

    it "accepts custom error page as proc" do
      custom_page = ->(msg) { "<html><body>Error: #{msg}</body></html>" }
      browser_oauth = described_class.new(oauth_provider, pages: { error_page: custom_page })

      expect(browser_oauth.custom_error_page).to eq(custom_page)
    end

    it "accepts both custom pages simultaneously" do
      custom_success = "<html><body>Success</body></html>"
      custom_error = "<html><body>Error</body></html>"
      browser_oauth = described_class.new(
        oauth_provider,
        pages: {
          success_page: custom_success,
          error_page: custom_error
        }
      )

      expect(browser_oauth.custom_success_page).to eq(custom_success)
      expect(browser_oauth.custom_error_page).to eq(custom_error)
    end
  end

  describe "#authenticate" do
    let(:browser_oauth) do
      described_class.new(oauth_provider, callback_port: callback_port, callback_path: callback_path)
    end
    let(:tcp_server) { instance_double(TCPServer, wait_readable: false, closed?: false) }

    before do
      allow(oauth_provider).to receive(:start_authorization_flow).and_return(auth_url)
      allow(TCPServer).to receive(:new).and_return(tcp_server)
      allow(tcp_server).to receive(:close)
    end

    context "with a happy path" do
      let(:client_socket) { instance_double(TCPSocket) }

      before do
        # Simulate successful OAuth callback
        allow(tcp_server).to receive(:wait_readable).and_return(true, false)
        allow(tcp_server).to receive(:accept).and_return(client_socket)
        allow(client_socket).to receive(:setsockopt)
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?code=test_code&state=test_state HTTP/1.1\r\n",
          "Host: localhost:8080\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)
        allow(client_socket).to receive(:close)
        allow(oauth_provider).to receive(:complete_authorization_flow).with("test_code", "test_state").and_return(token)
      end

      it "starts authorization flow and gets auth URL" do
        browser_oauth.authenticate(auto_open_browser: false)

        expect(oauth_provider).to have_received(:start_authorization_flow)
      end

      it "starts callback server on correct port" do
        browser_oauth.authenticate(auto_open_browser: false)

        expect(TCPServer).to have_received(:new).with("127.0.0.1", callback_port)
      end

      it "opens browser when auto_open_browser is true" do
        allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("darwin")
        allow(browser_oauth).to receive(:system).and_return(true)

        browser_oauth.authenticate(auto_open_browser: true)

        expect(browser_oauth).to have_received(:system).with("open", auth_url)
      end

      it "doesn't open browser when auto_open_browser is false" do
        allow(browser_oauth).to receive(:system)

        browser_oauth.authenticate(auto_open_browser: false)

        expect(browser_oauth).not_to have_received(:system)
      end

      it "waits for callback and completes authorization" do
        result = browser_oauth.authenticate(auto_open_browser: false)

        expect(result).to eq(token)
        expect(oauth_provider).to have_received(:complete_authorization_flow).with("test_code", "test_state")
      end

      it "returns access token on success" do
        result = browser_oauth.authenticate(auto_open_browser: false)

        expect(result).to be_a(RubyLLM::MCP::Auth::Token)
        expect(result.access_token).to eq(access_token)
      end

      it "shuts down server after completion" do
        browser_oauth.authenticate(auto_open_browser: false)

        expect(tcp_server).to have_received(:close)
      end
    end

    context "when errors occur" do
      it "raises TimeoutError when callback times out" do
        # Don't simulate any callback
        allow(tcp_server).to receive(:wait_readable).and_return(false)

        expect do
          browser_oauth.authenticate(timeout: 0.1, auto_open_browser: false)
        end.to raise_error(RubyLLM::MCP::Errors::TimeoutError, /timed out/)
      end

      it "raises TransportError when OAuth error is received" do
        client_socket = instance_double(TCPSocket)
        allow(tcp_server).to receive(:wait_readable).and_return(true, false)
        allow(tcp_server).to receive(:accept).and_return(client_socket)
        allow(client_socket).to receive(:setsockopt)
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?error=access_denied&error_description=User%20denied HTTP/1.1\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)
        allow(client_socket).to receive(:close)

        expect do
          browser_oauth.authenticate(auto_open_browser: false)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /User denied/)
      end

      it "raises TransportError when port is already in use" do
        allow(TCPServer).to receive(:new).and_raise(Errno::EADDRINUSE)

        expect do
          browser_oauth.authenticate(auto_open_browser: false)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /port.*already in use/)
      end

      it "raises TransportError for other server startup failures" do
        allow(TCPServer).to receive(:new).and_raise(StandardError.new("Network error"))

        expect do
          browser_oauth.authenticate(auto_open_browser: false)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Failed to start/)
      end

      it "shuts down server even when errors occur" do
        allow(tcp_server).to receive(:wait_readable).and_return(false)

        expect do
          browser_oauth.authenticate(timeout: 0.1, auto_open_browser: false)
        end.to raise_error(RubyLLM::MCP::Errors::TimeoutError)

        expect(tcp_server).to have_received(:close)
      end
    end
  end

  describe "#handle_http_request" do
    let(:browser_oauth) do
      described_class.new(oauth_provider, callback_port: callback_port, callback_path: callback_path)
    end
    let(:client_socket) { instance_double(TCPSocket) }
    let(:result) { { code: nil, state: nil, error: nil, completed: false } }
    let(:mutex) { Mutex.new }
    let(:condition) { ConditionVariable.new }

    before do
      allow(client_socket).to receive(:setsockopt)
      allow(client_socket).to receive(:write)
      allow(client_socket).to receive(:close)
    end

    context "with valid callback requests" do
      it "parses callback with code and state" do
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?code=test_code&state=test_state HTTP/1.1\r\n",
          "\r\n"
        )

        browser_oauth.send(:handle_http_request, client_socket, result, mutex, condition)

        expect(result[:code]).to eq("test_code")
        expect(result[:state]).to eq("test_state")
        expect(result[:completed]).to be true
      end

      it "handles URL-encoded parameters correctly" do
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?code=abc%2B123&state=xyz%3D456 HTTP/1.1\r\n",
          "\r\n"
        )

        browser_oauth.send(:handle_http_request, client_socket, result, mutex, condition)

        expect(result[:code]).to eq("abc+123")
        expect(result[:state]).to eq("xyz=456")
      end

      it "sends 200 OK with success page for valid authorization" do
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?code=test_code&state=test_state HTTP/1.1\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)

        browser_oauth.send(:handle_http_request, client_socket, result, mutex, condition)

        expect(client_socket).to have_received(:write) do |response|
          expect(response).to include("HTTP/1.1 200 OK")
          expect(response).to include("Content-Type: text/html")
          expect(response).to include("Authentication Successful")
        end
      end
    end

    context "with error responses" do
      it "returns 404 for non-callback paths" do
        allow(client_socket).to receive(:gets).and_return(
          "GET /wrong/path HTTP/1.1\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)

        browser_oauth.send(:handle_http_request, client_socket, result, mutex, condition)

        expect(result[:completed]).to be false
        expect(client_socket).to have_received(:write) do |response|
          expect(response).to include("HTTP/1.1 404 Not Found")
          expect(response).to include("Not Found")
        end
      end

      it "detects missing code or state parameters" do
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?code=test_code HTTP/1.1\r\n",
          "\r\n"
        )

        browser_oauth.send(:handle_http_request, client_socket, result, mutex, condition)

        expect(result[:error]).to include("missing code or state")
        expect(result[:completed]).to be true
      end

      it "handles OAuth error responses" do
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?error=access_denied&error_description=User%20denied%20access HTTP/1.1\r\n",
          "\r\n"
        )

        browser_oauth.send(:handle_http_request, client_socket, result, mutex, condition)

        expect(result[:error]).to eq("User denied access")
        expect(result[:completed]).to be true
      end

      it "sends 400 Bad Request with error page for OAuth errors" do
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?error=access_denied&error_description=User%20denied HTTP/1.1\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)

        browser_oauth.send(:handle_http_request, client_socket, result, mutex, condition)

        expect(client_socket).to have_received(:write) do |response|
          expect(response).to include("HTTP/1.1 400 Bad Request")
          expect(response).to include("Authentication Failed")
          expect(response).to include("User denied")
        end
      end
    end
  end

  describe "#parse_query_params" do
    let(:browser_oauth) { described_class.new(oauth_provider) }

    it "decodes URL-encoded strings" do
      params = browser_oauth.send(:parse_query_params, "key=hello%20world&other=test%2Bvalue")

      expect(params["key"]).to eq("hello world")
      expect(params["other"]).to eq("test+value")
    end

    it "handles empty values" do
      params = browser_oauth.send(:parse_query_params, "key1=&key2=value")

      expect(params["key1"]).to eq("")
      expect(params["key2"]).to eq("value")
    end

    it "handles special characters" do
      params = browser_oauth.send(:parse_query_params, "email=user%40example.com&path=%2Fapi%2Fv1")

      expect(params["email"]).to eq("user@example.com")
      expect(params["path"]).to eq("/api/v1")
    end

    it "handles empty query string" do
      params = browser_oauth.send(:parse_query_params, "")

      expect(params).to eq({})
    end

    it "handles multiple parameters" do
      params = browser_oauth.send(:parse_query_params, "a=1&b=2&c=3")

      expect(params).to eq({ "a" => "1", "b" => "2", "c" => "3" })
    end
  end

  describe "#send_http_response" do
    let(:browser_oauth) { described_class.new(oauth_provider) }
    let(:client_socket) { instance_double(TCPSocket) }

    before do
      allow(client_socket).to receive(:write)
    end

    it "sends 200 OK with correct headers" do
      allow(client_socket).to receive(:write)

      browser_oauth.send(:send_http_response, client_socket, 200, "text/plain", "Success")

      expect(client_socket).to have_received(:write) do |response|
        expect(response).to include("HTTP/1.1 200 OK")
        expect(response).to include("Content-Type: text/plain")
        expect(response).to include("Content-Length: 7")
        expect(response).to include("Connection: close")
        expect(response).to include("Success")
      end
    end

    it "sends 400 Bad Request with correct headers" do
      allow(client_socket).to receive(:write)

      browser_oauth.send(:send_http_response, client_socket, 400, "text/plain", "Error")

      expect(client_socket).to have_received(:write) do |response|
        expect(response).to include("HTTP/1.1 400 Bad Request")
        expect(response).to include("Content-Type: text/plain")
        expect(response).to include("Error")
      end
    end

    it "sends 404 Not Found with correct headers" do
      allow(client_socket).to receive(:write)

      browser_oauth.send(:send_http_response, client_socket, 404, "text/plain", "Not Found")

      expect(client_socket).to have_received(:write) do |response|
        expect(response).to include("HTTP/1.1 404 Not Found")
      end
    end

    it "handles write errors gracefully" do
      allow(client_socket).to receive(:write).and_raise(IOError)

      expect do
        browser_oauth.send(:send_http_response, client_socket, 200, "text/plain", "Success")
      end.not_to raise_error
    end
  end

  describe "#open_browser" do
    let(:browser_oauth) { described_class.new(oauth_provider) }
    let(:url) { "https://example.com/auth" }

    it "calls correct command for macOS" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("darwin")
      allow(browser_oauth).to receive(:system).and_return(true)

      result = browser_oauth.send(:open_browser, url)

      expect(result).to be true
      expect(browser_oauth).to have_received(:system).with("open", url)
    end

    it "calls correct command for Linux" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("linux")
      allow(browser_oauth).to receive(:system).and_return(true)

      result = browser_oauth.send(:open_browser, url)

      expect(result).to be true
      expect(browser_oauth).to have_received(:system).with("xdg-open", url)
    end

    it "calls correct command for Windows" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("mswin")
      allow(browser_oauth).to receive(:system).and_return(true)

      result = browser_oauth.send(:open_browser, url)

      expect(result).to be true
      expect(browser_oauth).to have_received(:system).with("start", url)
    end

    it "warns on unknown operating system" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("unknown-os")

      result = browser_oauth.send(:open_browser, url)

      expect(result).to be false
      expect(logger).to have_received(:warn).with(/Unknown operating system/)
    end

    it "handles system call failures" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("darwin")
      allow(browser_oauth).to receive(:system).and_raise(StandardError.new("Command failed"))

      result = browser_oauth.send(:open_browser, url)

      expect(result).to be false
      expect(logger).to have_received(:warn).with(/Failed to open browser/)
    end
  end

  describe "#success_page" do
    context "without custom page" do
      let(:browser_oauth) { described_class.new(oauth_provider) }

      it "includes proper HTML structure" do
        html = browser_oauth.send(:success_page)

        expect(html).to include("<html>")
        expect(html).to include("<head>")
        expect(html).to include("<body>")
        expect(html).to include("</html>")
      end

      it "includes success message" do
        html = browser_oauth.send(:success_page)

        expect(html).to include("Authentication Successful")
      end

      it "includes logo and favicon" do
        html = browser_oauth.send(:success_page)

        expect(html).to include("rubyllm-mcp-logo.svg")
        expect(html).to include("favicon.svg")
      end
    end

    context "with custom string page" do
      let(:custom_html) { "<html><body>Custom Success!</body></html>" }
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          pages: { success_page: custom_html }
        )
      end

      it "returns custom HTML string" do
        html = browser_oauth.send(:success_page)

        expect(html).to eq(custom_html)
      end

      it "doesn't include default content" do
        html = browser_oauth.send(:success_page)

        expect(html).not_to include("Authentication Successful")
      end
    end

    context "with custom proc page" do
      let(:custom_proc) { -> { "<html><body>Dynamic Success Page</body></html>" } }
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          pages: { success_page: custom_proc }
        )
      end

      it "calls proc and returns result" do
        html = browser_oauth.send(:success_page)

        expect(html).to eq("<html><body>Dynamic Success Page</body></html>")
      end

      it "doesn't include default content" do
        html = browser_oauth.send(:success_page)

        expect(html).not_to include("Authentication Successful")
      end
    end

    context "with custom lambda page" do
      let(:custom_lambda) { -> { "<html><body>Lambda Success!</body></html>" } }
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          pages: { success_page: custom_lambda }
        )
      end

      it "calls lambda and returns result" do
        html = browser_oauth.send(:success_page)

        expect(html).to eq("<html><body>Lambda Success!</body></html>")
      end
    end
  end

  describe "#error_page" do
    context "without custom page" do
      let(:browser_oauth) { described_class.new(oauth_provider) }

      it "includes proper HTML structure" do
        html = browser_oauth.send(:error_page, "Error message")

        expect(html).to include("<html>")
        expect(html).to include("<head>")
        expect(html).to include("<body>")
        expect(html).to include("</html>")
      end

      it "includes error message" do
        html = browser_oauth.send(:error_page, "Test error message")

        expect(html).to include("Authentication Failed")
        expect(html).to include("Test error message")
      end

      it "escapes HTML in error message" do
        html = browser_oauth.send(:error_page, "<script>alert('xss')</script>")

        expect(html).to include("&lt;script&gt;")
        expect(html).not_to include("<script>alert('xss')</script>")
      end

      it "includes logo and favicon" do
        html = browser_oauth.send(:error_page, "Error")

        expect(html).to include("rubyllm-mcp-logo.svg")
        expect(html).to include("favicon.svg")
      end
    end

    context "with custom string page" do
      let(:custom_html) { "<html><body>Custom Error!</body></html>" }
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          pages: { error_page: custom_html }
        )
      end

      it "returns custom HTML string" do
        html = browser_oauth.send(:error_page, "Some error")

        expect(html).to eq(custom_html)
      end

      it "doesn't include default content" do
        html = browser_oauth.send(:error_page, "Some error")

        expect(html).not_to include("Authentication Failed")
      end

      it "ignores error message parameter when using static string" do
        html = browser_oauth.send(:error_page, "Dynamic error")

        expect(html).to eq(custom_html)
        expect(html).not_to include("Dynamic error")
      end
    end

    context "with custom proc page" do
      let(:custom_proc) do
        ->(error_msg) { "<html><body>Error: #{error_msg}</body></html>" }
      end
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          pages: { error_page: custom_proc }
        )
      end

      it "calls proc with error message and returns result" do
        html = browser_oauth.send(:error_page, "Access denied")

        expect(html).to eq("<html><body>Error: Access denied</body></html>")
      end

      it "doesn't include default content" do
        html = browser_oauth.send(:error_page, "Some error")

        expect(html).not_to include("Authentication Failed")
      end

      it "passes different error messages to proc" do
        html1 = browser_oauth.send(:error_page, "Error 1")
        html2 = browser_oauth.send(:error_page, "Error 2")

        expect(html1).to include("Error 1")
        expect(html2).to include("Error 2")
      end
    end

    context "with custom lambda page" do
      let(:custom_lambda) do
        ->(error_msg) { "<html><body>Lambda Error: #{error_msg}</body></html>" }
      end
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          pages: { error_page: custom_lambda }
        )
      end

      it "calls lambda with error message and returns result" do
        html = browser_oauth.send(:error_page, "Invalid token")

        expect(html).to eq("<html><body>Lambda Error: Invalid token</body></html>")
      end
    end
  end

  describe "CallbackServer" do
    let(:tcp_server) { instance_double(TCPServer) }
    let(:thread) { instance_double(Thread) }
    let(:stop_proc) { -> {} }
    let(:callback_server) { described_class::CallbackServer.new(tcp_server, thread, stop_proc) }

    describe "#shutdown" do
      it "calls stop proc" do
        allow(stop_proc).to receive(:call)
        allow(tcp_server).to receive(:closed?).and_return(false)
        allow(tcp_server).to receive(:close)
        allow(thread).to receive(:join)

        callback_server.shutdown

        expect(stop_proc).to have_received(:call)
      end

      it "closes TCP server if not already closed" do
        allow(stop_proc).to receive(:call)
        allow(tcp_server).to receive(:closed?).and_return(false)
        allow(tcp_server).to receive(:close)
        allow(thread).to receive(:join)

        callback_server.shutdown

        expect(tcp_server).to have_received(:close)
      end

      it "doesn't close TCP server if already closed" do
        allow(stop_proc).to receive(:call)
        allow(tcp_server).to receive(:closed?).and_return(true)
        allow(tcp_server).to receive(:close)
        allow(thread).to receive(:join)

        callback_server.shutdown

        expect(tcp_server).not_to have_received(:close)
      end

      it "joins thread with timeout" do
        allow(stop_proc).to receive(:call)
        allow(tcp_server).to receive(:closed?).and_return(false)
        allow(tcp_server).to receive(:close)
        allow(thread).to receive(:join)

        callback_server.shutdown

        expect(thread).to have_received(:join).with(5)
      end

      it "handles shutdown errors gracefully" do
        allow(tcp_server).to receive(:closed?).and_raise(StandardError.new("Error"))

        expect { callback_server.shutdown }.not_to raise_error
      end

      it "returns nil on error" do
        allow(tcp_server).to receive(:closed?).and_raise(StandardError.new("Error"))

        result = callback_server.shutdown
        expect(result).to be_nil
      end
    end
  end

  describe "thread coordination" do
    let(:browser_oauth) do
      described_class.new(oauth_provider, callback_port: callback_port, callback_path: callback_path)
    end
    let(:tcp_server) { instance_double(TCPServer) }
    let(:client_socket) { instance_double(TCPSocket) }

    before do
      allow(oauth_provider).to receive(:start_authorization_flow).and_return(auth_url)
      allow(TCPServer).to receive(:new).and_return(tcp_server)
      allow(tcp_server).to receive(:close)
      allow(tcp_server).to receive(:closed?).and_return(false)
    end

    it "properly synchronizes callback result with mutex" do
      allow(tcp_server).to receive(:wait_readable).and_return(true, false)
      allow(tcp_server).to receive(:accept).and_return(client_socket)
      allow(client_socket).to receive(:setsockopt)
      allow(client_socket).to receive(:gets).and_return(
        "GET /callback?code=test&state=test HTTP/1.1\r\n",
        "\r\n"
      )
      allow(client_socket).to receive(:write)
      allow(client_socket).to receive(:close)
      allow(oauth_provider).to receive(:complete_authorization_flow).and_return(token)

      result = browser_oauth.authenticate(auto_open_browser: false)
      expect(result).to eq(token)
    end

    it "signals condition variable when callback completes" do
      # This is tested implicitly by the authentication completing successfully
      allow(tcp_server).to receive(:wait_readable).and_return(true, false)
      allow(tcp_server).to receive(:accept).and_return(client_socket)
      allow(client_socket).to receive(:setsockopt)
      allow(client_socket).to receive(:gets).and_return(
        "GET /callback?code=test&state=test HTTP/1.1\r\n",
        "\r\n"
      )
      allow(client_socket).to receive(:write)
      allow(client_socket).to receive(:close)
      allow(oauth_provider).to receive(:complete_authorization_flow).and_return(token)

      result = browser_oauth.authenticate(timeout: 1, auto_open_browser: false)
      expect(result).to eq(token)
    end

    it "waits with timeout on condition variable" do
      allow(tcp_server).to receive(:wait_readable).and_return(false)

      start_time = Time.now
      expect do
        browser_oauth.authenticate(timeout: 0.5, auto_open_browser: false)
      end.to raise_error(RubyLLM::MCP::Errors::TimeoutError)
      elapsed = Time.now - start_time

      expect(elapsed).to be >= 0.5
      expect(elapsed).to be < 1.0
    end
  end

  describe "integration scenarios" do
    let(:browser_oauth) do
      described_class.new(oauth_provider, callback_port: callback_port, callback_path: callback_path)
    end
    let(:tcp_server) { instance_double(TCPServer) }
    let(:client_socket) { instance_double(TCPSocket) }

    before do
      allow(oauth_provider).to receive(:start_authorization_flow).and_return(auth_url)
      allow(TCPServer).to receive(:new).and_return(tcp_server)
      allow(tcp_server).to receive(:close)
      allow(tcp_server).to receive(:closed?).and_return(false)
    end

    it "handles complete successful OAuth flow" do
      allow(tcp_server).to receive(:wait_readable).and_return(true, false)
      allow(tcp_server).to receive(:accept).and_return(client_socket)
      allow(client_socket).to receive(:setsockopt)
      allow(client_socket).to receive(:gets).and_return(
        "GET /callback?code=auth_code_123&state=state_xyz HTTP/1.1\r\n",
        "Host: localhost:8080\r\n",
        "\r\n"
      )
      allow(client_socket).to receive(:write)
      allow(client_socket).to receive(:close)
      allow(oauth_provider).to receive(:complete_authorization_flow)
        .with("auth_code_123", "state_xyz")
        .and_return(token)

      result = browser_oauth.authenticate(auto_open_browser: false)

      expect(result).to eq(token)
      expect(result.access_token).to eq(access_token)
    end

    it "handles OAuth error response from provider" do
      allow(tcp_server).to receive(:wait_readable).and_return(true, false)
      allow(tcp_server).to receive(:accept).and_return(client_socket)
      allow(client_socket).to receive(:setsockopt)
      allow(client_socket).to receive(:gets).and_return(
        "GET /callback?error=invalid_scope&error_description=Requested%20scope%20not%20available HTTP/1.1\r\n",
        "\r\n"
      )
      allow(client_socket).to receive(:write)
      allow(client_socket).to receive(:close)

      expect do
        browser_oauth.authenticate(auto_open_browser: false)
      end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Requested scope not available/)
    end

    it "ensures server cleanup after successful authentication" do
      allow(tcp_server).to receive(:wait_readable).and_return(true, false)
      allow(tcp_server).to receive(:accept).and_return(client_socket)
      allow(client_socket).to receive(:setsockopt)
      allow(client_socket).to receive(:gets).and_return(
        "GET /callback?code=test&state=test HTTP/1.1\r\n",
        "\r\n"
      )
      allow(client_socket).to receive(:write)
      allow(client_socket).to receive(:close)
      allow(oauth_provider).to receive(:complete_authorization_flow).and_return(token)

      browser_oauth.authenticate(auto_open_browser: false)

      expect(tcp_server).to have_received(:close)
    end

    it "ensures server cleanup after timeout" do
      allow(tcp_server).to receive(:wait_readable).and_return(false)

      expect do
        browser_oauth.authenticate(timeout: 0.1, auto_open_browser: false)
      end.to raise_error(RubyLLM::MCP::Errors::TimeoutError)

      expect(tcp_server).to have_received(:close)
    end

    it "ensures server cleanup after error" do
      allow(tcp_server).to receive(:wait_readable).and_return(true, false)
      allow(tcp_server).to receive(:accept).and_return(client_socket)
      allow(client_socket).to receive(:setsockopt)
      allow(client_socket).to receive(:gets).and_return(
        "GET /callback?error=access_denied HTTP/1.1\r\n",
        "\r\n"
      )
      allow(client_socket).to receive(:write)
      allow(client_socket).to receive(:close)

      expect do
        browser_oauth.authenticate(auto_open_browser: false)
      end.to raise_error(RubyLLM::MCP::Errors::TransportError)

      expect(tcp_server).to have_received(:close)
    end
  end

  describe "custom pages integration" do
    let(:tcp_server) { instance_double(TCPServer) }
    let(:client_socket) { instance_double(TCPSocket) }

    before do
      allow(oauth_provider).to receive(:start_authorization_flow).and_return(auth_url)
      allow(TCPServer).to receive(:new).and_return(tcp_server)
      allow(tcp_server).to receive(:close)
      allow(tcp_server).to receive(:closed?).and_return(false)
      allow(client_socket).to receive(:setsockopt)
      allow(client_socket).to receive(:close)
    end

    context "with custom success page" do
      let(:custom_success_html) { "<html><body>Custom Success Page</body></html>" }
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          callback_port: callback_port,
          callback_path: callback_path,
          pages: { success_page: custom_success_html }
        )
      end

      it "sends custom success page on successful authentication" do
        allow(tcp_server).to receive(:wait_readable).and_return(true, false)
        allow(tcp_server).to receive(:accept).and_return(client_socket)
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?code=test_code&state=test_state HTTP/1.1\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)
        allow(oauth_provider).to receive(:complete_authorization_flow).and_return(token)

        browser_oauth.authenticate(auto_open_browser: false)

        expect(client_socket).to have_received(:write) do |response|
          expect(response).to include("HTTP/1.1 200 OK")
          expect(response).to include("Custom Success Page")
          expect(response).not_to include("Authentication Successful")
        end
      end
    end

    context "with custom error page" do
      let(:custom_error_proc) do
        ->(error_msg) { "<html><body>Custom Error: #{error_msg}</body></html>" }
      end
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          callback_port: callback_port,
          callback_path: callback_path,
          pages: { error_page: custom_error_proc }
        )
      end

      it "sends custom error page with error message on OAuth error" do
        allow(tcp_server).to receive(:wait_readable).and_return(true, false)
        allow(tcp_server).to receive(:accept).and_return(client_socket)
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?error=access_denied&error_description=User%20cancelled HTTP/1.1\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)

        expect do
          browser_oauth.authenticate(auto_open_browser: false)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError)

        expect(client_socket).to have_received(:write) do |response|
          expect(response).to include("HTTP/1.1 400 Bad Request")
          expect(response).to include("Custom Error: User cancelled")
          expect(response).not_to include("Authentication Failed")
        end
      end
    end

    context "with custom proc-based success page" do
      let(:custom_success_proc) do
        -> { "<html><body>Dynamic Success - #{Time.now.to_i}</body></html>" }
      end
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          callback_port: callback_port,
          callback_path: callback_path,
          pages: { success_page: custom_success_proc }
        )
      end

      it "calls proc to generate success page dynamically" do
        allow(tcp_server).to receive(:wait_readable).and_return(true, false)
        allow(tcp_server).to receive(:accept).and_return(client_socket)
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?code=test_code&state=test_state HTTP/1.1\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)
        allow(oauth_provider).to receive(:complete_authorization_flow).and_return(token)

        browser_oauth.authenticate(auto_open_browser: false)

        expect(client_socket).to have_received(:write) do |response|
          expect(response).to include("Dynamic Success")
        end
      end
    end

    context "with both custom pages" do
      let(:custom_success_html) { "<html><body>My Success Page</body></html>" }
      let(:custom_error_html) { "<html><body>My Error Page</body></html>" }
      let(:browser_oauth) do
        described_class.new(
          oauth_provider,
          callback_port: callback_port,
          callback_path: callback_path,
          pages: {
            success_page: custom_success_html,
            error_page: custom_error_html
          }
        )
      end

      it "uses custom success page for successful auth" do
        allow(tcp_server).to receive(:wait_readable).and_return(true, false)
        allow(tcp_server).to receive(:accept).and_return(client_socket)
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?code=test&state=test HTTP/1.1\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)
        allow(oauth_provider).to receive(:complete_authorization_flow).and_return(token)

        browser_oauth.authenticate(auto_open_browser: false)

        expect(client_socket).to have_received(:write) do |response|
          expect(response).to include("My Success Page")
        end
      end

      it "uses custom error page for OAuth errors" do
        allow(tcp_server).to receive(:wait_readable).and_return(true, false)
        allow(tcp_server).to receive(:accept).and_return(client_socket)
        allow(client_socket).to receive(:gets).and_return(
          "GET /callback?error=invalid_request HTTP/1.1\r\n",
          "\r\n"
        )
        allow(client_socket).to receive(:write)

        expect do
          browser_oauth.authenticate(auto_open_browser: false)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError)

        expect(client_socket).to have_received(:write) do |response|
          expect(response).to include("My Error Page")
        end
      end
    end
  end
end
