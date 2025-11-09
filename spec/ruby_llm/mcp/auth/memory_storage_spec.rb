# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::MemoryStorage do
  let(:storage) { described_class.new }
  let(:server_url) { "https://mcp.example.com/api" }

  describe "token storage" do
    let(:token) do
      RubyLLM::MCP::Auth::Token.new(access_token: "test_token")
    end

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
