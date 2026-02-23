# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::Discoverer do
  let(:http_client) { instance_double(HTTPX::Session) }
  let(:storage) { RubyLLM::MCP::Auth::MemoryStorage.new }
  let(:logger) { instance_double(Logger) }
  let(:discoverer) { described_class.new(http_client, storage, logger) }
  let(:server_url) { "https://mcp.example.com/api" }

  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
  end

  describe "#discover" do
    context "when metadata is cached" do
      let(:cached_metadata) do
        RubyLLM::MCP::Auth::ServerMetadata.new(
          issuer: "https://auth.example.com",
          authorization_endpoint: "https://auth.example.com/authorize",
          token_endpoint: "https://auth.example.com/token"
        )
      end

      before do
        storage.set_server_metadata(server_url, cached_metadata)
      end

      it "returns cached metadata without making requests" do
        allow(http_client).to receive(:get)

        result = discoverer.discover(server_url)

        expect(result).to eq(cached_metadata)
        expect(http_client).not_to have_received(:get)
      end
    end

    context "when authorization server discovery succeeds" do
      let(:metadata_response) do
        {
          "issuer" => "https://mcp.example.com/api",
          "authorization_endpoint" => "https://mcp.example.com/api/authorize",
          "token_endpoint" => "https://mcp.example.com/api/token",
          "registration_endpoint" => "https://mcp.example.com/api/register",
          "code_challenge_methods_supported" => ["S256"]
        }
      end

      before do
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-protected-resource/api")
          .and_return(httpx_error_response("Not found"))
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-protected-resource")
          .and_return(httpx_error_response("Not found"))

        response = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-authorization-server/api")
          .and_return(response)
      end

      it "fetches and returns server metadata" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://mcp.example.com/api")
        expect(result.authorization_endpoint).to eq("https://mcp.example.com/api/authorize")
        expect(result.token_endpoint).to eq("https://mcp.example.com/api/token")
        expect(result.registration_endpoint).to eq("https://mcp.example.com/api/register")
        expect(result.code_challenge_methods_supported).to eq(["S256"])
      end
    end

    context "when both protected resource and direct authorization metadata are available" do
      let(:resource_response) do
        {
          "resource" => "https://mcp.example.com/api",
          "authorization_servers" => ["https://auth.example.com/tenant1"]
        }
      end
      let(:delegated_metadata_response) do
        {
          "issuer" => "https://auth.example.com/tenant1",
          "authorization_endpoint" => "https://auth.example.com/tenant1/authorize",
          "token_endpoint" => "https://auth.example.com/tenant1/token"
        }
      end
      let(:direct_metadata_response) do
        {
          "issuer" => "https://mcp.example.com",
          "authorization_endpoint" => "https://mcp.example.com/authorize",
          "token_endpoint" => "https://mcp.example.com/token"
        }
      end

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))

        resource_resp = instance_double(HTTPX::Response, status: 200, body: resource_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-protected-resource/api")
          .and_return(resource_resp)

        delegated_resp = instance_double(HTTPX::Response, status: 200, body: delegated_metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/oauth-authorization-server/tenant1")
          .and_return(delegated_resp)

        direct_resp = instance_double(HTTPX::Response, status: 200, body: direct_metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-authorization-server/api")
          .and_return(direct_resp)
      end

      it "prefers protected resource metadata discovery before direct authorization server metadata" do
        result = discoverer.discover(server_url)

        expect(result.issuer).to eq("https://auth.example.com/tenant1")
        expect(http_client).not_to have_received(:get).with("https://mcp.example.com/.well-known/oauth-authorization-server/api")
      end
    end

    context "when protected resource discovery succeeds via path-based well-known URI" do
      let(:resource_response) do
        {
          "resource" => "https://mcp.example.com/api",
          "authorization_servers" => ["https://auth.example.com/tenant1"]
        }
      end

      let(:metadata_response) do
        {
          "issuer" => "https://auth.example.com/tenant1",
          "authorization_endpoint" => "https://auth.example.com/tenant1/authorize",
          "token_endpoint" => "https://auth.example.com/tenant1/token"
        }
      end

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))

        resource_resp = instance_double(HTTPX::Response, status: 200, body: resource_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-protected-resource/api")
          .and_return(resource_resp)

        metadata_resp = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/oauth-authorization-server/tenant1")
          .and_return(metadata_resp)
      end

      it "discovers delegated authorization server metadata using RFC 8414 path insertion" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://auth.example.com/tenant1")
      end
    end

    context "when resource metadata URL is explicitly provided from challenge" do
      let(:resource_metadata_url) { "https://challenge.example.com/.well-known/oauth-protected-resource" }
      let(:resource_response) do
        {
          "resource" => "https://mcp.example.com/api",
          "authorization_servers" => ["https://auth.example.com"]
        }
      end
      let(:metadata_response) do
        {
          "issuer" => "https://auth.example.com",
          "authorization_endpoint" => "https://auth.example.com/authorize",
          "token_endpoint" => "https://auth.example.com/token"
        }
      end

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))

        resource_resp = instance_double(HTTPX::Response, status: 200, body: resource_response.to_json)
        allow(http_client).to receive(:get)
          .with(resource_metadata_url)
          .and_return(resource_resp)

        metadata_resp = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/oauth-authorization-server")
          .and_return(metadata_resp)
      end

      it "uses explicit metadata URL before probing well-known endpoints" do
        result = discoverer.discover(server_url, resource_metadata_url: resource_metadata_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://auth.example.com")
      end
    end

    context "when auth server metadata requires OIDC fallback endpoint" do
      let(:resource_response) do
        {
          "resource" => "https://mcp.example.com/api",
          "authorization_servers" => ["https://auth.example.com/tenant1"]
        }
      end

      let(:metadata_response) do
        {
          "issuer" => "https://auth.example.com/tenant1",
          "authorization_endpoint" => "https://auth.example.com/oauth2/authorize",
          "token_endpoint" => "https://auth.example.com/oauth2/token"
        }
      end

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))

        resource_resp = instance_double(HTTPX::Response, status: 200, body: resource_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-protected-resource/api")
          .and_return(resource_resp)

        # Force first two URLs to fail so discovery reaches OIDC path-appending fallback.
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/oauth-authorization-server/tenant1")
          .and_return(httpx_error_response("Not found"))
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/openid-configuration/tenant1")
          .and_return(httpx_error_response("Not found"))

        metadata_resp = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/tenant1/.well-known/openid-configuration")
          .and_return(metadata_resp)
      end

      it "tries OIDC path-appending endpoint after OAuth and OIDC path-insertion endpoints" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.authorization_endpoint).to eq("https://auth.example.com/oauth2/authorize")
      end
    end

    context "when protected resource metadata resource does not match requested resource" do
      let(:resource_response) do
        {
          "resource" => "https://mcp.example.com/other",
          "authorization_servers" => ["https://auth.example.com"]
        }
      end

      let(:direct_metadata_response) do
        {
          "issuer" => "https://mcp.example.com/api",
          "authorization_endpoint" => "https://mcp.example.com/authorize",
          "token_endpoint" => "https://mcp.example.com/token"
        }
      end

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))

        resource_resp = instance_double(HTTPX::Response, status: 200, body: resource_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-protected-resource/api")
          .and_return(resource_resp)

        direct_resp = instance_double(HTTPX::Response, status: 200, body: direct_metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-authorization-server/api")
          .and_return(direct_resp)
      end

      it "rejects the mismatched resource metadata and falls back to direct discovery" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://mcp.example.com/api")
        expect(http_client).not_to have_received(:get).with("https://auth.example.com/.well-known/oauth-authorization-server")
      end
    end

    context "when authorization server metadata issuer does not match expected issuer" do
      let(:resource_response) do
        {
          "resource" => "https://mcp.example.com/api",
          "authorization_servers" => ["https://auth.example.com/tenant1"]
        }
      end
      let(:wrong_issuer_metadata_response) do
        {
          "issuer" => "https://auth.example.com",
          "authorization_endpoint" => "https://auth.example.com/oauth2/authorize",
          "token_endpoint" => "https://auth.example.com/oauth2/token"
        }
      end
      let(:valid_metadata_response) do
        {
          "issuer" => "https://auth.example.com/tenant1",
          "authorization_endpoint" => "https://auth.example.com/tenant1/authorize",
          "token_endpoint" => "https://auth.example.com/tenant1/token"
        }
      end

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))

        resource_resp = instance_double(HTTPX::Response, status: 200, body: resource_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-protected-resource/api")
          .and_return(resource_resp)

        wrong_resp = instance_double(HTTPX::Response, status: 200, body: wrong_issuer_metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/oauth-authorization-server/tenant1")
          .and_return(wrong_resp)

        valid_resp = instance_double(HTTPX::Response, status: 200, body: valid_metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/openid-configuration/tenant1")
          .and_return(valid_resp)
      end

      it "rejects mismatched issuer metadata and continues to the next discovery endpoint" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://auth.example.com/tenant1")
      end
    end

    context "when protected resource metadata uses origin resource and issuer differs only by trailing slash" do
      let(:server_url) { "http://localhost:3011/mcp" }
      let(:resource_metadata_url) { "http://localhost:3011/.well-known/oauth-protected-resource" }
      let(:resource_response) do
        {
          "resource" => "http://localhost:3011/",
          "authorization_servers" => ["https://accounts.google.com/"]
        }
      end
      let(:metadata_response) do
        {
          "issuer" => "https://accounts.google.com",
          "authorization_endpoint" => "https://accounts.google.com/o/oauth2/v2/auth",
          "token_endpoint" => "https://oauth2.googleapis.com/token"
        }
      end

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))

        resource_resp = instance_double(HTTPX::Response, status: 200, body: resource_response.to_json)
        allow(http_client).to receive(:get)
          .with(resource_metadata_url)
          .and_return(resource_resp)

        metadata_resp = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://accounts.google.com/.well-known/oauth-authorization-server")
          .and_return(metadata_resp)
      end

      it "accepts delegated resource prefix and normalized issuer identifiers" do
        result = discoverer.discover(server_url, resource_metadata_url: resource_metadata_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://accounts.google.com")
        expect(result.authorization_endpoint).to eq("https://accounts.google.com/o/oauth2/v2/auth")
        expect(result.token_endpoint).to eq("https://oauth2.googleapis.com/token")
      end
    end

    context "when resource metadata provides multiple authorization servers" do
      let(:resource_response) do
        {
          "resource" => "https://mcp.example.com/api",
          "authorization_servers" => ["https://auth1.example.com", "https://auth2.example.com"]
        }
      end
      let(:metadata_response) do
        {
          "issuer" => "https://auth2.example.com",
          "authorization_endpoint" => "https://auth2.example.com/authorize",
          "token_endpoint" => "https://auth2.example.com/token"
        }
      end

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))

        resource_resp = instance_double(HTTPX::Response, status: 200, body: resource_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-protected-resource/api")
          .and_return(resource_resp)

        auth2_resp = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://auth2.example.com/.well-known/oauth-authorization-server")
          .and_return(auth2_resp)
      end

      it "tries the next authorization server when earlier candidates fail" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://auth2.example.com")
      end
    end

    context "when direct auth server discovery requires root OIDC fallback" do
      let(:server_url) { "https://auth.example.com" }

      let(:metadata_response) do
        {
          "issuer" => "https://auth.example.com",
          "authorization_endpoint" => "https://auth.example.com/oauth2/authorize",
          "token_endpoint" => "https://auth.example.com/oauth2/token"
        }
      end

      before do
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/oauth-protected-resource")
          .and_return(httpx_error_response("Not found"))
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/oauth-authorization-server")
          .and_return(httpx_error_response("Not found"))

        metadata_resp = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/openid-configuration")
          .and_return(metadata_resp)
      end

      it "tries root OIDC discovery after root OAuth authorization server discovery" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.authorization_endpoint).to eq("https://auth.example.com/oauth2/authorize")
      end
    end

    context "when protected resource discovery fails for a path-based MCP endpoint" do
      let(:server_url) { "https://mcp.atlassian.com/v1/sse" }
      let(:metadata_response) do
        {
          "issuer" => "https://cf.mcp.atlassian.com",
          "authorization_endpoint" => "https://mcp.atlassian.com/v1/authorize",
          "token_endpoint" => "https://cf.mcp.atlassian.com/v1/token"
        }
      end

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))

        metadata_resp = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.atlassian.com/.well-known/oauth-authorization-server")
          .and_return(metadata_resp)
      end

      it "falls back to legacy base URL auth server discovery" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://cf.mcp.atlassian.com")
        expect(result.authorization_endpoint).to eq("https://mcp.atlassian.com/v1/authorize")
        expect(result.token_endpoint).to eq("https://cf.mcp.atlassian.com/v1/token")
        expect(logger).to have_received(:info).with(/Legacy OAuth discovery issuer mismatch accepted/)
      end
    end

    context "when all discovery methods fail" do
      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Connection failed"))
      end

      it "returns default metadata" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://mcp.example.com")
        expect(result.authorization_endpoint).to eq("https://mcp.example.com/authorize")
        expect(result.token_endpoint).to eq("https://mcp.example.com/token")
        expect(result.registration_endpoint).to eq("https://mcp.example.com/register")
      end

      it "logs warning about fallback" do
        discoverer.discover(server_url)

        expect(logger).to have_received(:warn).with(/OAuth discovery failed, falling back to default endpoints/)
      end
    end

    context "with non-default port" do
      let(:server_url) { "https://mcp.example.com:8443/api" }

      before do
        allow(http_client).to receive(:get).and_return(httpx_error_response("Not found"))
      end

      it "includes port in default metadata" do
        result = discoverer.discover(server_url)

        expect(result.issuer).to eq("https://mcp.example.com:8443")
        expect(result.authorization_endpoint).to eq("https://mcp.example.com:8443/authorize")
      end
    end
  end

  def httpx_error_response(message)
    error = StandardError.new(message)
    response = instance_double(HTTPX::ErrorResponse, error: error)
    allow(response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
    response
  end
end
