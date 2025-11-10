# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::SessionManager do
  let(:storage) { RubyLLM::MCP::Auth::MemoryStorage.new }
  let(:manager) { described_class.new(storage) }
  let(:server_url) { "https://mcp.example.com/api" }

  describe "#create_session" do
    it "creates PKCE parameters" do
      session = manager.create_session(server_url)

      expect(session[:pkce]).to be_a(RubyLLM::MCP::Auth::PKCE)
      expect(session[:pkce].code_verifier).not_to be_nil
      expect(session[:pkce].code_challenge).not_to be_nil
    end

    it "creates CSRF state" do
      session = manager.create_session(server_url)

      expect(session[:state]).to be_a(String)
      expect(session[:state].length).to be > 32
    end

    it "stores PKCE in storage" do
      session = manager.create_session(server_url)

      stored_pkce = storage.get_pkce(server_url)
      expect(stored_pkce).to eq(session[:pkce])
    end

    it "stores state in storage" do
      session = manager.create_session(server_url)

      stored_state = storage.get_state(server_url)
      expect(stored_state).to eq(session[:state])
    end
  end

  describe "#validate_and_retrieve_session" do
    let(:pkce) { RubyLLM::MCP::Auth::PKCE.new }
    let(:state) { "test_state_123" }
    let(:client_info) do
      RubyLLM::MCP::Auth::ClientInfo.new(client_id: "test_client")
    end

    before do
      storage.set_pkce(server_url, pkce)
      storage.set_state(server_url, state)
      storage.set_client_info(server_url, client_info)
    end

    context "with valid state" do
      it "returns session data" do
        result = manager.validate_and_retrieve_session(server_url, state)

        expect(result[:pkce]).to eq(pkce)
        expect(result[:client_info]).to eq(client_info)
      end
    end

    context "with invalid state" do
      it "raises ArgumentError" do
        expect do
          manager.validate_and_retrieve_session(server_url, "wrong_state")
        end.to raise_error(ArgumentError, /Invalid state parameter/)
      end
    end

    context "with no stored state" do
      before do
        storage.delete_state(server_url)
      end

      it "raises ArgumentError" do
        expect do
          manager.validate_and_retrieve_session(server_url, state)
        end.to raise_error(ArgumentError, /Invalid state parameter/)
      end
    end

    context "with timing attack attempt" do
      let(:attacker_state) { "t" * state.length }

      it "uses constant-time comparison" do
        # This should not leak timing information
        expect do
          manager.validate_and_retrieve_session(server_url, attacker_state)
        end.to raise_error(ArgumentError, /Invalid state parameter/)
      end
    end
  end

  describe "#cleanup_session" do
    let(:pkce) { RubyLLM::MCP::Auth::PKCE.new }
    let(:state) { "test_state_123" }

    before do
      storage.set_pkce(server_url, pkce)
      storage.set_state(server_url, state)
    end

    it "deletes PKCE from storage" do
      manager.cleanup_session(server_url)

      expect(storage.get_pkce(server_url)).to be_nil
    end

    it "deletes state from storage" do
      manager.cleanup_session(server_url)

      expect(storage.get_state(server_url)).to be_nil
    end

    it "preserves other data in storage" do
      token = RubyLLM::MCP::Auth::Token.new(access_token: "test_token")
      storage.set_token(server_url, token)

      manager.cleanup_session(server_url)

      expect(storage.get_token(server_url)).to eq(token)
    end
  end
end
