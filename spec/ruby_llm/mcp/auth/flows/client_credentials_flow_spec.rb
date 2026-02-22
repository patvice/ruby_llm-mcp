# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::Flows::ClientCredentialsFlow do
  let(:discoverer) { instance_double(RubyLLM::MCP::Auth::Discoverer) }
  let(:client_registrar) { instance_double(RubyLLM::MCP::Auth::ClientRegistrar) }
  let(:token_manager) { instance_double(RubyLLM::MCP::Auth::TokenManager) }
  let(:storage) { RubyLLM::MCP::Auth::MemoryStorage.new }
  let(:logger) { instance_double(Logger) }

  let(:flow) do
    described_class.new(discoverer: discoverer, client_registrar: client_registrar, token_manager: token_manager,
                        storage: storage, logger: logger)
  end

  let(:server_url) { "https://mcp.example.com/api" }
  let(:redirect_uri) { "http://localhost:8080/callback" }
  let(:scope) { "mcp:read mcp:write" }

  let(:server_metadata) do
    RubyLLM::MCP::Auth::ServerMetadata.new(
      issuer: "https://mcp.example.com",
      authorization_endpoint: "https://mcp.example.com/authorize",
      token_endpoint: "https://mcp.example.com/token"
    )
  end

  let(:client_metadata) do
    RubyLLM::MCP::Auth::ClientMetadata.new(
      redirect_uris: [redirect_uri],
      token_endpoint_auth_method: "client_secret_post"
    )
  end

  let(:client_info) do
    RubyLLM::MCP::Auth::ClientInfo.new(
      client_id: "test_client_id",
      client_secret: "test_secret",
      metadata: client_metadata
    )
  end

  let(:token) do
    RubyLLM::MCP::Auth::Token.new(
      access_token: "test_access_token",
      expires_in: 3600
    )
  end

  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
  end

  describe "#execute" do
    before do
      allow(discoverer).to receive(:discover).and_return(server_metadata)
      allow(client_registrar).to receive(:get_or_register).and_return(client_info)
      allow(token_manager).to receive(:exchange_client_credentials).and_return(token)
    end

    it "returns access token" do
      result = flow.execute(server_url, redirect_uri, scope)

      expect(result).to eq(token)
    end

    it "discovers authorization server" do
      flow.execute(server_url, redirect_uri, scope)

      expect(discoverer).to have_received(:discover).with(server_url, resource_metadata_url: nil)
    end

    it "registers client with client_credentials grant type" do
      flow.execute(server_url, redirect_uri, scope)

      expect(client_registrar).to have_received(:get_or_register).with(
        server_url,
        server_metadata,
        :client_credentials,
        redirect_uri,
        scope
      )
    end

    it "exchanges client credentials for token" do
      flow.execute(server_url, redirect_uri, scope)

      expect(token_manager).to have_received(:exchange_client_credentials).with(
        server_metadata,
        client_info,
        scope,
        server_url
      )
    end

    it "stores token" do
      flow.execute(server_url, redirect_uri, scope)

      expect(storage.get_token(server_url)).to eq(token)
    end

    context "when discovery fails" do
      before do
        allow(discoverer).to receive(:discover).and_return(nil)
      end

      it "raises error" do
        expect do
          flow.execute(server_url, redirect_uri, scope)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /OAuth server discovery failed/)
      end
    end

    context "when client_secret is missing" do
      let(:client_info_no_secret) do
        RubyLLM::MCP::Auth::ClientInfo.new(
          client_id: "test_client_id",
          client_secret: nil,
          metadata: client_metadata
        )
      end

      before do
        allow(client_registrar).to receive(:get_or_register).and_return(client_info_no_secret)
      end

      it "raises error" do
        expect do
          flow.execute(server_url, redirect_uri, scope)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Client credentials flow requires client_secret/)
      end
    end

    context "with nil scope" do
      it "handles nil scope" do
        flow.execute(server_url, redirect_uri, nil)

        expect(token_manager).to have_received(:exchange_client_credentials).with(
          server_metadata,
          client_info,
          nil,
          server_url
        )
      end
    end

    it "passes resource metadata hint to discovery when provided" do
      hint = "https://example.com/.well-known/oauth-protected-resource"

      flow.execute(server_url, redirect_uri, scope, resource_metadata: hint)

      expect(discoverer).to have_received(:discover).with(server_url, resource_metadata_url: hint)
    end
  end
end
