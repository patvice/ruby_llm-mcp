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
        allow(http_client).to receive(:get) # stub for spy check
        result = discoverer.discover(server_url)

        expect(result).to eq(cached_metadata)
        expect(http_client).not_to have_received(:get)
      end
    end

    context "when authorization server discovery succeeds" do
      let(:metadata_response) do
        {
          "issuer" => "https://mcp.example.com",
          "authorization_endpoint" => "https://mcp.example.com/authorize",
          "token_endpoint" => "https://mcp.example.com/token",
          "registration_endpoint" => "https://mcp.example.com/register"
        }
      end

      before do
        response = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-authorization-server")
          .and_return(response)
      end

      it "fetches and returns server metadata" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://mcp.example.com")
        expect(result.authorization_endpoint).to eq("https://mcp.example.com/authorize")
        expect(result.token_endpoint).to eq("https://mcp.example.com/token")
        expect(result.registration_endpoint).to eq("https://mcp.example.com/register")
      end

      it "caches the metadata" do
        discoverer.discover(server_url)

        cached = storage.get_server_metadata(server_url)
        expect(cached).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
      end
    end

    context "when protected resource discovery succeeds" do
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
        # Authorization server discovery fails
        auth_error = instance_double(HTTPX::ErrorResponse, error: StandardError.new("Not found"))
        allow(auth_error).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-authorization-server")
          .and_return(auth_error)

        # Protected resource discovery succeeds
        resource_resp = instance_double(HTTPX::Response, status: 200, body: resource_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://mcp.example.com/.well-known/oauth-protected-resource")
          .and_return(resource_resp)

        # Delegated auth server metadata succeeds
        metadata_resp = instance_double(HTTPX::Response, status: 200, body: metadata_response.to_json)
        allow(http_client).to receive(:get)
          .with("https://auth.example.com/.well-known/oauth-authorization-server")
          .and_return(metadata_resp)
      end

      it "fetches metadata from delegated auth server" do
        result = discoverer.discover(server_url)

        expect(result).to be_a(RubyLLM::MCP::Auth::ServerMetadata)
        expect(result.issuer).to eq("https://auth.example.com")
      end
    end

    context "when all discovery methods fail" do
      before do
        error_response = instance_double(HTTPX::ErrorResponse, error: StandardError.new("Connection failed"))
        allow(error_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
        allow(http_client).to receive(:get).and_return(error_response)
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
        error_response = instance_double(HTTPX::ErrorResponse, error: StandardError.new("Not found"))
        allow(error_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
        allow(http_client).to receive(:get).and_return(error_response)
      end

      it "includes port in default metadata" do
        result = discoverer.discover(server_url)

        expect(result.issuer).to eq("https://mcp.example.com:8443")
        expect(result.authorization_endpoint).to eq("https://mcp.example.com:8443/authorize")
      end
    end
  end
end
