# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::Flows::AuthorizationCodeFlow do
  let(:discoverer) { instance_double(RubyLLM::MCP::Auth::Discoverer) }
  let(:client_registrar) { instance_double(RubyLLM::MCP::Auth::ClientRegistrar) }
  let(:session_manager) { instance_double(RubyLLM::MCP::Auth::SessionManager) }
  let(:token_manager) { instance_double(RubyLLM::MCP::Auth::TokenManager) }
  let(:storage) { RubyLLM::MCP::Auth::MemoryStorage.new }
  let(:logger) { instance_double(Logger) }

  let(:flow) do
    described_class.new(discoverer: discoverer, client_registrar: client_registrar, session_manager: session_manager,
                        token_manager: token_manager, storage: storage, logger: logger)
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
      token_endpoint_auth_method: "none"
    )
  end

  let(:client_info) do
    RubyLLM::MCP::Auth::ClientInfo.new(
      client_id: "test_client_id",
      metadata: client_metadata
    )
  end

  let(:pkce) { RubyLLM::MCP::Auth::PKCE.new }
  let(:state) { "test_state_123" }

  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
  end

  describe "#start" do
    before do
      allow(discoverer).to receive(:discover).with(server_url).and_return(server_metadata)
      allow(client_registrar).to receive(:get_or_register).and_return(client_info)
      allow(session_manager).to receive(:create_session).and_return({ pkce: pkce, state: state })
    end

    it "returns authorization URL" do
      result = flow.start(server_url, redirect_uri, scope)

      expect(result).to be_a(String)
      expect(result).to include("https://mcp.example.com/authorize")
      expect(result).to include("client_id=test_client_id")
      expect(result).to include("state=#{state}")
    end

    it "discovers authorization server" do
      flow.start(server_url, redirect_uri, scope)

      expect(discoverer).to have_received(:discover).with(server_url)
    end

    it "registers or retrieves client" do
      flow.start(server_url, redirect_uri, scope)

      expect(client_registrar).to have_received(:get_or_register).with(
        server_url,
        server_metadata,
        :authorization_code,
        redirect_uri,
        scope
      )
    end

    it "creates session with PKCE and state" do
      flow.start(server_url, redirect_uri, scope)

      expect(session_manager).to have_received(:create_session).with(server_url)
    end

    it "includes PKCE challenge in URL" do
      result = flow.start(server_url, redirect_uri, scope)

      expect(result).to include("code_challenge=#{pkce.code_challenge}")
      expect(result).to include("code_challenge_method=S256")
    end

    it "includes scope in URL" do
      result = flow.start(server_url, redirect_uri, scope)

      expect(result).to include("scope=#{CGI.escape(scope)}")
    end

    context "with HTTPS validator" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:https_validator) { instance_double(Proc) }

      before do
        allow(https_validator).to receive(:call)
      end

      it "calls HTTPS validator" do
        flow.start(server_url, redirect_uri, scope, https_validator: https_validator)

        expect(https_validator).to have_received(:call).with(
          "https://mcp.example.com/authorize",
          "Authorization endpoint"
        )
      end
    end

    context "when discovery fails" do
      before do
        allow(discoverer).to receive(:discover).and_return(nil)
      end

      it "raises error" do
        expect do
          flow.start(server_url, redirect_uri, scope)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /OAuth server discovery failed/)
      end
    end
  end

  describe "#complete" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:code) { "auth_code_123" }
    let(:token) do
      RubyLLM::MCP::Auth::Token.new(
        access_token: "test_token",
        refresh_token: "test_refresh"
      )
    end

    before do
      allow(session_manager).to receive(:validate_and_retrieve_session).and_return({
                                                                                     pkce: pkce,
                                                                                     client_info: client_info
                                                                                   })
      allow(discoverer).to receive(:discover).and_return(server_metadata)
      allow(token_manager).to receive(:exchange_authorization_code).and_return(token)
      allow(session_manager).to receive(:cleanup_session)
    end

    it "validates state parameter" do
      flow.complete(server_url, code, state)

      expect(session_manager).to have_received(:validate_and_retrieve_session).with(server_url, state)
    end

    it "exchanges code for token" do
      flow.complete(server_url, code, state)

      expect(token_manager).to have_received(:exchange_authorization_code).with(
        server_metadata,
        client_info,
        code,
        pkce,
        server_url
      )
    end

    it "stores token" do
      result = flow.complete(server_url, code, state)

      expect(storage.get_token(server_url)).to eq(token)
      expect(result).to eq(token)
    end

    it "cleans up session" do
      flow.complete(server_url, code, state)

      expect(session_manager).to have_received(:cleanup_session).with(server_url)
    end

    context "when PKCE is missing" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before do
        allow(session_manager).to receive(:validate_and_retrieve_session).and_return({
                                                                                       pkce: nil,
                                                                                       client_info: client_info
                                                                                     })
      end

      it "raises error" do
        expect do
          flow.complete(server_url, code, state)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Missing PKCE or client info/)
      end
    end

    context "when client info is missing" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before do
        allow(session_manager).to receive(:validate_and_retrieve_session).and_return({
                                                                                       pkce: pkce,
                                                                                       client_info: nil
                                                                                     })
      end

      it "raises error" do
        expect do
          flow.complete(server_url, code, state)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Missing PKCE or client info/)
      end
    end

    context "when state validation fails" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before do
        allow(session_manager).to receive(:validate_and_retrieve_session)
          .and_raise(ArgumentError, "Invalid state parameter")
      end

      it "raises error" do
        expect do
          flow.complete(server_url, code, state)
        end.to raise_error(ArgumentError, /Invalid state parameter/)
      end
    end
  end
end
