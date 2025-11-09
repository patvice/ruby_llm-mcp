# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::OAuthProvider do
  let(:server_url) { "https://mcp.example.com/api" }
  let(:redirect_uri) { "http://localhost:8080/callback" }
  let(:scope) { "mcp:read mcp:write" }
  let(:storage) { RubyLLM::MCP::Auth::OAuthProvider::MemoryStorage.new }

  let(:provider) do
    described_class.new(
      server_url: server_url,
      redirect_uri: redirect_uri,
      scope: scope,
      storage: storage
    )
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
      custom_storage = instance_double(RubyLLM::MCP::Auth::OAuthProvider::MemoryStorage)
      provider = described_class.new(
        server_url: server_url,
        redirect_uri: redirect_uri,
        storage: custom_storage
      )

      expect(provider.storage).to eq(custom_storage)
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

    it "removes default ports" do
      provider = described_class.new(
        server_url: "https://mcp.example.com:443",
        redirect_uri: redirect_uri
      )

      expect(provider.server_url).to eq("https://mcp.example.com")
    end

    it "keeps non-default ports" do
      provider = described_class.new(
        server_url: "https://mcp.example.com:8443",
        redirect_uri: redirect_uri
      )

      expect(provider.server_url).to eq("https://mcp.example.com:8443")
    end

    it "removes trailing slashes" do
      provider = described_class.new(
        server_url: "https://mcp.example.com/api/",
        redirect_uri: redirect_uri
      )

      expect(provider.server_url).to eq("https://mcp.example.com/api")
    end
  end

  describe "#build_authorization_url" do
    let(:server_metadata) do
      RubyLLM::MCP::Auth::ServerMetadata.new(
        issuer: "https://auth.example.com",
        authorization_endpoint: "https://auth.example.com/authorize",
        token_endpoint: "https://auth.example.com/token",
        options: { registration_endpoint: "https://auth.example.com/register" }
      )
    end

    let(:client_info) do
      RubyLLM::MCP::Auth::ClientInfo.new(
        client_id: "test_client_id",
        metadata: RubyLLM::MCP::Auth::ClientMetadata.new(
          redirect_uris: [redirect_uri]
        )
      )
    end

    let(:pkce) { RubyLLM::MCP::Auth::PKCE.new }
    let(:state) { "test_state" }

    it "builds valid authorization URL with correct endpoint" do
      url = provider.send(:build_authorization_url, server_metadata, client_info, pkce, state)
      uri = URI.parse(url)

      expect(uri.scheme).to eq("https")
      expect(uri.host).to eq("auth.example.com")
      expect(uri.path).to eq("/authorize")
    end

    it "includes all required OAuth parameters in authorization URL" do
      url = provider.send(:build_authorization_url, server_metadata, client_info, pkce, state)
      uri = URI.parse(url)
      params = URI.decode_www_form(uri.query).to_h

      expect(params["response_type"]).to eq("code")
      expect(params["client_id"]).to eq("test_client_id")
      expect(params["redirect_uri"]).to eq(redirect_uri)
      expect(params["scope"]).to eq(scope)
      expect(params["state"]).to eq(state)
      expect(params["code_challenge"]).to eq(pkce.code_challenge)
      expect(params["code_challenge_method"]).to eq("S256")
      expect(params["resource"]).to eq(server_url)
    end
  end

  describe "#access_token" do
    it "returns nil when no token stored" do
      expect(provider.access_token).to be_nil
    end

    it "returns valid token" do
      token = RubyLLM::MCP::Auth::Token.new(
        access_token: "test_token",
        expires_in: 3600
      )
      storage.set_token(server_url, token)

      expect(provider.access_token).to eq(token)
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
  end

  describe "MemoryStorage" do
    let(:storage) { described_class::MemoryStorage.new }
    let(:token) do
      RubyLLM::MCP::Auth::Token.new(access_token: "test_token")
    end

    describe "token storage" do
      it "stores and retrieves tokens" do
        storage.set_token(server_url, token)

        expect(storage.get_token(server_url)).to eq(token)
      end

      it "returns nil for non-existent tokens" do
        expect(storage.get_token("https://other.example.com")).to be_nil
      end
    end

    describe "client info storage" do
      let(:client_info) do
        RubyLLM::MCP::Auth::ClientInfo.new(client_id: "test_id")
      end

      it "stores and retrieves client info" do
        storage.set_client_info(server_url, client_info)

        expect(storage.get_client_info(server_url)).to eq(client_info)
      end
    end

    describe "server metadata storage" do
      let(:metadata) do
        RubyLLM::MCP::Auth::ServerMetadata.new(
          issuer: "https://auth.example.com",
          authorization_endpoint: "https://auth.example.com/authorize",
          token_endpoint: "https://auth.example.com/token",
          options: {}
        )
      end

      it "stores and retrieves server metadata" do
        storage.set_server_metadata(server_url, metadata)

        expect(storage.get_server_metadata(server_url)).to eq(metadata)
      end
    end

    describe "PKCE storage" do
      let(:pkce) { RubyLLM::MCP::Auth::PKCE.new }

      it "stores, retrieves, and deletes PKCE" do
        storage.set_pkce(server_url, pkce)

        expect(storage.get_pkce(server_url)).to eq(pkce)

        storage.delete_pkce(server_url)

        expect(storage.get_pkce(server_url)).to be_nil
      end
    end

    describe "state storage" do
      let(:state) { "test_state" }

      it "stores, retrieves, and deletes state" do
        storage.set_state(server_url, state)

        expect(storage.get_state(server_url)).to eq(state)

        storage.delete_state(server_url)

        expect(storage.get_state(server_url)).to be_nil
      end
    end
  end
end

def freeze_time(&block)
  time = Time.now
  allow(Time).to receive(:now).and_return(time)
  block.call
  allow(Time).to receive(:now).and_call_original
end

def travel_to(time)
  allow(Time).to receive(:now).and_return(time)
end
