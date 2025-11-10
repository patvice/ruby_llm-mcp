# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::ClientRegistrar do
  let(:http_client) { instance_double(HTTPX::Session) }
  let(:storage) { RubyLLM::MCP::Auth::MemoryStorage.new }
  let(:logger) { instance_double(Logger) }
  let(:config) { RubyLLM::MCP.config }
  let(:registrar) { described_class.new(http_client, storage, logger, config) }
  let(:server_url) { "https://mcp.example.com/api" }
  let(:redirect_uri) { "http://localhost:8080/callback" }
  let(:scope) { "mcp:read mcp:write" }

  let(:server_metadata) do
    RubyLLM::MCP::Auth::ServerMetadata.new(
      issuer: "https://mcp.example.com",
      authorization_endpoint: "https://mcp.example.com/authorize",
      token_endpoint: "https://mcp.example.com/token",
      options: { registration_endpoint: "https://mcp.example.com/register" }
    )
  end

  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)

    # Reset global config
    RubyLLM::MCP.config.reset!
  end

  describe "#get_or_register" do
    context "when client info is cached and valid" do
      let(:cached_client_info) do
        RubyLLM::MCP::Auth::ClientInfo.new(
          client_id: "cached_client_id",
          client_secret: "cached_secret"
        )
      end

      before do
        storage.set_client_info(server_url, cached_client_info)
      end

      it "returns cached client info without registering" do
        allow(http_client).to receive(:post) # stub for spy check
        result = registrar.get_or_register(server_url, server_metadata, :authorization_code, redirect_uri, scope)

        expect(result).to eq(cached_client_info)
        expect(http_client).not_to have_received(:post)
      end
    end

    context "when server does not support registration" do
      let(:server_metadata_no_reg) do
        RubyLLM::MCP::Auth::ServerMetadata.new(
          issuer: "https://mcp.example.com",
          authorization_endpoint: "https://mcp.example.com/authorize",
          token_endpoint: "https://mcp.example.com/token"
        )
      end

      it "raises error" do
        expect do
          registrar.get_or_register(server_url, server_metadata_no_reg, :authorization_code, redirect_uri, scope)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /does not support dynamic client registration/)
      end
    end

    context "when no cached client info exists" do
      let(:registration_response) do
        {
          "client_id" => "new_client_id",
          "client_secret" => "new_secret",
          "redirect_uris" => [redirect_uri]
        }
      end

      before do
        response = instance_double(HTTPX::Response, status: 201, body: registration_response.to_json)
        allow(http_client).to receive(:post).and_return(response)
      end

      it "registers new client" do
        result = registrar.get_or_register(server_url, server_metadata, :authorization_code, redirect_uri, scope)

        expect(result).to be_a(RubyLLM::MCP::Auth::ClientInfo)
        expect(result.client_id).to eq("new_client_id")
      end
    end
  end

  describe "#register" do
    let(:registration_response) do
      {
        "client_id" => "test_client_id",
        "client_secret" => "test_secret",
        "client_id_issued_at" => 1_234_567_890,
        "redirect_uris" => [redirect_uri],
        "token_endpoint_auth_method" => "none",
        "grant_types" => %w[authorization_code refresh_token],
        "response_types" => ["code"]
      }
    end

    before do
      response = instance_double(HTTPX::Response, status: 201, body: registration_response.to_json)
      allow(http_client).to receive(:post).and_return(response)
    end

    it "registers client with authorization code grant" do
      result = registrar.register(server_url, server_metadata, :authorization_code, redirect_uri, scope)

      expect(result).to be_a(RubyLLM::MCP::Auth::ClientInfo)
      expect(result.client_id).to eq("test_client_id")
      expect(result.client_secret).to eq("test_secret")
      expect(result.metadata.token_endpoint_auth_method).to eq("none")
    end

    it "caches the registered client info" do
      registrar.register(server_url, server_metadata, :authorization_code, redirect_uri, scope)

      cached = storage.get_client_info(server_url)
      expect(cached).to be_a(RubyLLM::MCP::Auth::ClientInfo)
      expect(cached.client_id).to eq("test_client_id")
    end

    context "with client credentials grant" do
      let(:registration_response) do
        {
          "client_id" => "test_client_id",
          "client_secret" => "test_secret",
          "token_endpoint_auth_method" => "client_secret_post",
          "grant_types" => %w[client_credentials refresh_token],
          "response_types" => []
        }
      end

      it "registers client with client credentials grant" do
        result = registrar.register(server_url, server_metadata, :client_credentials, redirect_uri, scope)

        expect(result.metadata.token_endpoint_auth_method).to eq("client_secret_post")
        expect(result.metadata.grant_types).to eq(%w[client_credentials refresh_token])
        expect(result.metadata.response_types).to eq([])
      end
    end

    context "when server changes redirect_uri" do
      let(:registration_response) do
        {
          "client_id" => "test_client_id",
          "redirect_uris" => ["http://localhost:3000/callback"]
        }
      end

      it "warns about mismatch" do
        registrar.register(server_url, server_metadata, :authorization_code, redirect_uri, scope)

        expect(logger).to have_received(:warn).with(/OAuth server changed redirect_uri/)
        expect(logger).to have_received(:warn).with(/Requested:  #{redirect_uri}/)
        expect(logger).to have_received(:warn).with(%r{Registered: http://localhost:3000/callback})
      end
    end
  end

  describe "#build_client_metadata" do
    it "builds metadata for authorization code grant" do
      metadata = registrar.send(:build_client_metadata, :authorization_code, redirect_uri, scope)

      expect(metadata).to be_a(RubyLLM::MCP::Auth::ClientMetadata)
      expect(metadata.redirect_uris).to eq([redirect_uri])
      expect(metadata.token_endpoint_auth_method).to eq("none")
      expect(metadata.grant_types).to eq(%w[authorization_code refresh_token])
      expect(metadata.response_types).to eq(["code"])
      expect(metadata.scope).to eq(scope)
    end

    it "builds metadata for client credentials grant" do
      metadata = registrar.send(:build_client_metadata, :client_credentials, redirect_uri, scope)

      expect(metadata.token_endpoint_auth_method).to eq("client_secret_post")
      expect(metadata.grant_types).to eq(%w[client_credentials refresh_token])
      expect(metadata.response_types).to eq([])
    end

    it "includes config values" do
      RubyLLM::MCP.configure do |c|
        c.oauth.client_name = "Test Client"
        c.oauth.client_uri = "https://example.com"
      end

      metadata = registrar.send(:build_client_metadata, :authorization_code, redirect_uri, scope)

      expect(metadata.client_name).to eq("Test Client")
      expect(metadata.client_uri).to eq("https://example.com")
    end
  end
end
