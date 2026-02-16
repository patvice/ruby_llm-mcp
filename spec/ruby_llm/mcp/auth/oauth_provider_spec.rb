# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::OAuthProvider do # rubocop:disable RSpec/SpecFilePathFormat
  let(:server_url) { "https://mcp.example.com/api" }
  let(:redirect_uri) { "http://localhost:8080/callback" }
  let(:scope) { "mcp:read mcp:write" }
  let(:storage) { RubyLLM::MCP::Auth::MemoryStorage.new }
  let(:logger) { instance_double(Logger) }
  let(:provider) do
    described_class.new(
      server_url: server_url,
      redirect_uri: redirect_uri,
      scope: scope,
      storage: storage
    )
  end

  before do
    # Reset global config to avoid test pollution
    RubyLLM::MCP.config.reset!

    allow(RubyLLM::MCP).to receive(:logger).and_return(logger)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe "#initialize" do
    it "normalizes server URL" do
      provider = described_class.new(
        server_url: "HTTPS://MCP.EXAMPLE.COM:443/api/",
        redirect_uri: redirect_uri
      )

      expect(provider.server_url).to eq("https://mcp.example.com/api")
    end

    it "accepts custom storage" do
      custom_storage = instance_double(RubyLLM::MCP::Auth::MemoryStorage)
      provider = described_class.new(
        server_url: server_url,
        redirect_uri: redirect_uri,
        storage: custom_storage
      )

      expect(provider.storage).to eq(custom_storage)
    end

    it "configures HTTPX with request_timeout" do
      session = instance_double(HTTPX::Session)
      allow(HTTPX).to receive(:plugin).with(:follow_redirects).and_return(session)
      allow(session).to receive(:with).and_return(session)

      described_class.new(
        server_url: server_url,
        redirect_uri: redirect_uri
      )

      expect(session).to have_received(:with) do |options|
        expect(options[:timeout]).to eq(request_timeout: RubyLLM::MCP::Auth::DEFAULT_OAUTH_TIMEOUT)
        expect(options[:headers]["Accept"]).to eq("application/json")
        expect(options[:headers]["MCP-Protocol-Version"]).to eq(RubyLLM::MCP.config.protocol_version)
        expect(options[:headers]["User-Agent"]).to match(%r{\ARubyLLM-MCP/})
      end
    end
  end

  describe ".normalize_url (class method)" do
    it "normalizes URLs without creating an instance" do
      normalized = described_class.normalize_url("HTTPS://MCP.EXAMPLE.COM:443/api/")
      expect(normalized).to eq("https://mcp.example.com/api")
    end

    it "can be used for URL comparison" do
      url1 = "HTTP://localhost:80/mcp"
      url2 = "http://LOCALHOST/mcp/"

      expect(described_class.normalize_url(url1)).to eq(described_class.normalize_url(url2))
    end
  end

  describe "#normalize_server_url" do
    it "lowercases scheme and host" do
      provider = described_class.new(
        server_url: "HTTPS://MCP.EXAMPLE.COM",
        redirect_uri: redirect_uri
      )

      expect(provider.server_url).to eq("https://mcp.example.com")
    end

    it "removes default HTTPS port (443)" do
      provider = described_class.new(
        server_url: "https://mcp.example.com:443",
        redirect_uri: redirect_uri
      )

      expect(provider.server_url).to eq("https://mcp.example.com")
    end

    it "removes default HTTP port (80)" do
      provider = described_class.new(
        server_url: "http://example.com:80/mcp",
        storage: storage
      )

      expect(provider.server_url).to eq("http://example.com/mcp")
    end

    it "preserves non-default HTTPS port (8443)" do
      provider = described_class.new(
        server_url: "https://mcp.example.com:8443",
        redirect_uri: redirect_uri
      )

      expect(provider.server_url).to eq("https://mcp.example.com:8443")
    end

    it "preserves non-default HTTP port (8080)" do
      provider = described_class.new(
        server_url: "http://example.com:8080/mcp",
        storage: storage
      )

      expect(provider.server_url).to eq("http://example.com:8080/mcp")
    end

    it "removes trailing slashes" do
      provider = described_class.new(
        server_url: "https://mcp.example.com/api/",
        redirect_uri: redirect_uri
      )

      expect(provider.server_url).to eq("https://mcp.example.com/api")
    end

    it "normalizes server URL consistently with mixed case" do
      provider = described_class.new(
        server_url: "HTTP://LOCALHOST:3000/api/mcp/",
        storage: storage
      )

      # URL should be normalized to lowercase, no trailing slash
      expect(provider.server_url).to eq("http://localhost:3000/api/mcp")
    end
  end

  describe "#access_token" do
    let(:provider) do
      described_class.new(
        server_url: server_url,
        storage: storage,
        logger: logger
      )
    end

    context "when no token stored" do
      it "returns nil" do
        expect(provider.access_token).to be_nil
      end

      it "logs warning about missing token" do
        result = provider.access_token

        expect(result).to be_nil
        expect(logger).to have_received(:warn).with(/No token found in storage/)
        expect(logger).to have_received(:warn).with(/Check that authentication completed/)
      end
    end

    context "when token exists in storage" do
      let(:token) do
        RubyLLM::MCP::Auth::Token.new(
          access_token: "test_token_123",
          expires_in: 3600
        )
      end

      before do
        storage.set_token(server_url, token)
      end

      it "returns valid token" do
        expect(provider.access_token).to eq(token)
      end

      it "logs debug information about token lookup" do
        provider.access_token

        expect(logger).to have_received(:debug).with(/Looking up token for server_url/)
        expect(logger).to have_received(:debug).with(/Storage returned token=present/)
        expect(logger).to have_received(:debug).with(/Token expires_at:/)
        expect(logger).to have_received(:debug).with(/Token expired\?:/)
        expect(logger).to have_received(:debug).with(/Token expires_soon\?:/)
      end

      it "returns the token when valid" do
        result = provider.access_token
        expect(result).to eq(token)
        expect(result.access_token).to eq("test_token_123")
      end

      it "logs token expiration details" do
        provider.access_token

        expect(logger).to have_received(:debug).with(/expires_at:/)
        expect(logger).to have_received(:debug).with(/expired\?: false/)
        expect(logger).to have_received(:debug).with(/expires_soon\?: false/)
      end
    end

    context "when token is expired" do
      let(:expired_token) do
        token = RubyLLM::MCP::Auth::Token.new(
          access_token: "expired_token",
          expires_in: 1
        )
        # Force expiration by setting expires_at in the past
        token.instance_variable_set(:@expires_at, Time.now - 3600)
        token
      end

      before do
        storage.set_token(server_url, expired_token)
      end

      it "returns nil for expired token without refresh" do
        freeze_time do
          token = RubyLLM::MCP::Auth::Token.new(
            access_token: "test_token",
            expires_in: 3600
          )
          storage.set_token(server_url, token)

          travel_to(Time.now + 3601)

          expect(provider.access_token).to be_nil
        end
      end

      it "attempts to refresh when refresh_token present" do
        expired_token.instance_variable_set(:@refresh_token, "refresh_123")
        allow(provider).to receive(:refresh_token).and_return(nil)

        provider.access_token

        expect(logger).to have_received(:debug).with(/Token expired or expiring soon, attempting refresh/)
        expect(provider).to have_received(:refresh_token).with(expired_token)
      end

      it "returns nil when no refresh_token available" do
        result = provider.access_token
        expect(result).to be_nil
      end
    end
  end

  describe "#authenticate" do
    let(:provider) do
      described_class.new(
        server_url: server_url,
        storage: storage,
        logger: logger
      )
    end

    context "when token is available" do
      let(:token) do
        RubyLLM::MCP::Auth::Token.new(
          access_token: "valid_token",
          expires_in: 3600
        )
      end

      before do
        storage.set_token(server_url, token)
      end

      it "returns the token" do
        result = provider.authenticate

        expect(result).to eq(token)
        expect(result.access_token).to eq("valid_token")
      end
    end

    context "when no token is available" do
      it "raises TransportError" do
        expect do
          provider.authenticate
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Not authenticated/)
      end

      it "provides helpful error message" do
        expect do
          provider.authenticate
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /complete OAuth authorization flow first/)
      end

      it "mentions standard OAuth flow in error" do
        expect do
          provider.authenticate
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /standard OAuth.*authorize externally/)
      end
    end
  end

  describe "MCP OAuth 2.1 Compliance Features" do
    describe "#initialize with grant_type" do
      it "accepts grant_type parameter" do
        provider = described_class.new(
          server_url: server_url,
          redirect_uri: redirect_uri,
          grant_type: :client_credentials
        )

        expect(provider.grant_type).to eq(:client_credentials)
      end

      it "defaults to authorization_code grant type" do
        provider = described_class.new(
          server_url: server_url,
          redirect_uri: redirect_uri
        )

        expect(provider.grant_type).to eq(:authorization_code)
      end
    end

    describe "redirect URI validation" do
      it "accepts HTTPS redirect URIs" do
        expect do
          described_class.new(
            server_url: server_url,
            redirect_uri: "https://app.example.com/callback"
          )
        end.not_to raise_error
      end

      it "accepts localhost redirect URIs with http" do
        expect do
          described_class.new(
            server_url: server_url,
            redirect_uri: "http://localhost:8080/callback"
          )
        end.not_to raise_error
      end

      it "accepts 127.0.0.1 redirect URIs with http" do
        expect do
          described_class.new(
            server_url: server_url,
            redirect_uri: "http://127.0.0.1:8080/callback"
          )
        end.not_to raise_error
      end

      it "rejects non-HTTPS, non-localhost redirect URIs" do
        expect do
          described_class.new(
            server_url: server_url,
            redirect_uri: "http://example.com/callback"
          )
        end.to raise_error(ArgumentError, /Redirect URI must be localhost or HTTPS/)
      end

      it "rejects invalid redirect URIs" do
        expect do
          described_class.new(
            server_url: server_url,
            redirect_uri: "not a valid uri"
          )
        end.to raise_error(ArgumentError, /Invalid redirect URI/)
      end
    end

    describe "HTTPS endpoint validation" do
      it "warns when authorization endpoint is not HTTPS (non-localhost)" do
        allow(logger).to receive(:warn)

        provider.send(:validate_https_endpoint, "http://example.com/authorize", "Authorization endpoint")

        expect(logger).to have_received(:warn).with(/Authorization endpoint is not using HTTPS/)
        expect(logger).to have_received(:warn).with(/OAuth endpoints SHOULD use HTTPS/)
      end

      it "does not warn for HTTPS endpoints" do
        allow(logger).to receive(:warn)

        provider.send(:validate_https_endpoint, "https://example.com/authorize", "Authorization endpoint")

        expect(logger).not_to have_received(:warn)
      end

      it "does not warn for localhost HTTP endpoints" do
        allow(logger).to receive(:warn)

        provider.send(:validate_https_endpoint, "http://localhost:8080/authorize", "Authorization endpoint")

        expect(logger).not_to have_received(:warn)
      end

      it "does not warn for 127.0.0.1 HTTP endpoints" do
        allow(logger).to receive(:warn)

        provider.send(:validate_https_endpoint, "http://127.0.0.1:8080/authorize", "Authorization endpoint")

        expect(logger).not_to have_received(:warn)
      end
    end

    # NOTE: State parameter validation is now tested in SessionManager specs
    # These tests were testing internal implementation details
  end

  describe "#handle_authentication_challenge" do
    let(:provider) do
      described_class.new(
        server_url: server_url,
        storage: storage,
        logger: logger,
        grant_type: :authorization_code
      )
    end

    context "when token can be refreshed" do
      let(:expired_token) do
        token = RubyLLM::MCP::Auth::Token.new(
          access_token: "expired_token",
          refresh_token: "refresh_token_123",
          expires_in: 1
        )
        token.instance_variable_set(:@expires_at, Time.now - 3600)
        token
      end

      let(:new_token) do
        RubyLLM::MCP::Auth::Token.new(
          access_token: "new_token",
          expires_in: 3600
        )
      end

      before do
        storage.set_token(server_url, expired_token)
        allow(provider).to receive(:refresh_token).with(expired_token).and_return(new_token)
      end

      it "refreshes token and returns true" do
        result = provider.handle_authentication_challenge

        expect(result).to be true
        expect(provider).to have_received(:refresh_token)
      end

      it "logs debug information" do
        provider.handle_authentication_challenge

        expect(logger).to have_received(:debug).with(/Handling authentication challenge/)
        expect(logger).to have_received(:debug).with(/Attempting token refresh/)
      end
    end

    context "when using client credentials grant" do
      let(:provider) do
        described_class.new(
          server_url: server_url,
          storage: storage,
          logger: logger,
          grant_type: :client_credentials
        )
      end

      let(:new_token) do
        RubyLLM::MCP::Auth::Token.new(
          access_token: "client_creds_token",
          expires_in: 3600
        )
      end

      before do
        allow(provider).to receive(:client_credentials_flow).and_return(new_token)
      end

      it "attempts client credentials flow" do
        result = provider.handle_authentication_challenge

        expect(result).to be true
        expect(provider).to have_received(:client_credentials_flow)
      end

      it "passes requested scope to client credentials flow" do
        provider.handle_authentication_challenge(requested_scope: "custom:scope")

        expect(provider).to have_received(:client_credentials_flow).with(scope: "custom:scope")
      end
    end

    context "when interactive auth is required" do
      it "raises AuthenticationRequiredError" do
        expect do
          provider.handle_authentication_challenge
        end.to raise_error(RubyLLM::MCP::Errors::AuthenticationRequiredError, /interactive authorization is needed/)
      end

      it "logs warning about interactive auth requirement" do
        begin
          provider.handle_authentication_challenge
        rescue RubyLLM::MCP::Errors::AuthenticationRequiredError
          # Expected
        end

        expect(logger).to have_received(:warn).with(/Cannot automatically authenticate/)
      end
    end

    context "with WWW-Authenticate header" do
      let(:www_authenticate) { 'Bearer realm="example", scope="mcp:read mcp:write"' }

      it "parses and updates scope" do
        expect do
          provider.handle_authentication_challenge(www_authenticate: www_authenticate)
        end.to raise_error(RubyLLM::MCP::Errors::AuthenticationRequiredError)

        expect(provider.scope).to eq("mcp:read mcp:write")
      end

      it "logs WWW-Authenticate header" do
        begin
          provider.handle_authentication_challenge(www_authenticate: www_authenticate)
        rescue RubyLLM::MCP::Errors::AuthenticationRequiredError
          # Expected
        end

        expect(logger).to have_received(:debug).with(/WWW-Authenticate:/)
      end
    end

    context "with resource metadata URL" do
      let(:metadata_url) { "https://example.com/.well-known/oauth-protected-resource" }

      it "logs resource metadata URL" do
        begin
          provider.handle_authentication_challenge(resource_metadata_url: metadata_url)
        rescue RubyLLM::MCP::Errors::AuthenticationRequiredError
          # Expected
        end

        expect(logger).to have_received(:debug).with(/Resource metadata URL:/)
      end
    end
  end

  describe "#parse_www_authenticate" do
    let(:provider) do
      described_class.new(
        server_url: server_url,
        storage: storage
      )
    end

    it "parses scope from header" do
      header = 'Bearer realm="example", scope="mcp:read mcp:write"'
      result = provider.parse_www_authenticate(header)

      expect(result[:scope]).to eq("mcp:read mcp:write")
    end

    it "parses resource_metadata_url from header" do
      header = 'Bearer resource_metadata_url="https://example.com/.well-known/oauth"'
      result = provider.parse_www_authenticate(header)

      expect(result[:resource_metadata_url]).to eq("https://example.com/.well-known/oauth")
    end

    it "parses realm from header" do
      header = 'Bearer realm="example.com"'
      result = provider.parse_www_authenticate(header)

      expect(result[:realm]).to eq("example.com")
    end

    it "parses all parameters together" do
      header = 'Bearer realm="example", scope="mcp:read", resource_metadata_url="https://example.com/meta"'
      result = provider.parse_www_authenticate(header)

      expect(result[:realm]).to eq("example")
      expect(result[:scope]).to eq("mcp:read")
      expect(result[:resource_metadata_url]).to eq("https://example.com/meta")
    end

    it "returns empty hash for non-Bearer header" do
      header = 'Basic realm="example"'
      result = provider.parse_www_authenticate(header)

      expect(result).to eq({})
    end

    it "handles case-insensitive Bearer" do
      header = 'bearer scope="test"'
      result = provider.parse_www_authenticate(header)

      expect(result[:scope]).to eq("test")
    end
  end
end
