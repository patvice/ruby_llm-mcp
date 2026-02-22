# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::TokenManager do
  let(:http_client) { instance_double(HTTPX::Session) }
  let(:logger) { instance_double(Logger) }
  let(:manager) { described_class.new(http_client, logger) }
  let(:server_url) { "https://mcp.example.com/api" }

  let(:server_metadata) do
    RubyLLM::MCP::Auth::ServerMetadata.new(
      issuer: "https://mcp.example.com",
      authorization_endpoint: "https://mcp.example.com/authorize",
      token_endpoint: "https://mcp.example.com/token"
    )
  end

  let(:client_metadata) do
    RubyLLM::MCP::Auth::ClientMetadata.new(
      redirect_uris: ["http://localhost:8080/callback"],
      token_endpoint_auth_method: "none"
    )
  end

  let(:client_info) do
    RubyLLM::MCP::Auth::ClientInfo.new(
      client_id: "test_client_id",
      metadata: client_metadata
    )
  end

  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
  end

  describe "#exchange_authorization_code" do
    let(:pkce) { RubyLLM::MCP::Auth::PKCE.new }
    let(:code) { "auth_code_123" }

    let(:token_response) do
      {
        "access_token" => "test_access_token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "refresh_token" => "test_refresh_token"
      }
    end

    before do
      response = instance_double(HTTPX::Response, status: 200, body: token_response.to_json)
      allow(http_client).to receive(:post).and_return(response)
    end

    it "exchanges authorization code for token" do
      result = manager.exchange_authorization_code(server_metadata, client_info, code, pkce, server_url)

      expect(result).to be_a(RubyLLM::MCP::Auth::Token)
      expect(result.access_token).to eq("test_access_token")
      expect(result.refresh_token).to eq("test_refresh_token")
    end

    it "includes PKCE code verifier in request" do
      manager.exchange_authorization_code(server_metadata, client_info, code, pkce, server_url)

      expect(http_client).to have_received(:post) do |_url, options|
        expect(options[:form][:code_verifier]).to eq(pkce.code_verifier)
      end
    end

    it "includes resource indicator in request" do
      manager.exchange_authorization_code(server_metadata, client_info, code, pkce, server_url)

      expect(http_client).to have_received(:post) do |_url, options|
        expect(options[:form][:resource]).to eq(server_url)
      end
    end

    context "with client secret" do
      let(:client_metadata_with_secret) do
        RubyLLM::MCP::Auth::ClientMetadata.new(
          redirect_uris: ["http://localhost:8080/callback"],
          token_endpoint_auth_method: "client_secret_post"
        )
      end

      let(:client_info_with_secret) do
        RubyLLM::MCP::Auth::ClientInfo.new(
          client_id: "test_client_id",
          client_secret: "test_secret",
          metadata: client_metadata_with_secret
        )
      end

      it "includes client secret in request" do
        manager.exchange_authorization_code(server_metadata, client_info_with_secret, code, pkce, server_url)

        expect(http_client).to have_received(:post) do |_url, options|
          expect(options[:form][:client_secret]).to eq("test_secret")
        end
      end
    end

    context "with redirect URI mismatch" do
      let(:error_response) do
        {
          "error" => "unauthorized_client",
          "error_description" => "You sent http://localhost:8080/callback and we expected http://localhost:3000/callback"
        }
      end

      let(:success_response) do
        {
          "access_token" => "test_access_token",
          "token_type" => "Bearer"
        }
      end

      before do
        error_resp = instance_double(HTTPX::Response, status: 400, body: error_response.to_json)
        success_resp = instance_double(HTTPX::Response, status: 200, body: success_response.to_json)
        allow(http_client).to receive(:post).and_return(error_resp, success_resp)
      end

      it "retries with corrected redirect URI" do
        result = manager.exchange_authorization_code(server_metadata, client_info, code, pkce, server_url)

        expect(result.access_token).to eq("test_access_token")
        expect(logger).to have_received(:warn).with(/Redirect URI mismatch/)
      end
    end
  end

  describe "#exchange_client_credentials" do
    let(:scope) { "mcp:read" }

    let(:client_info_with_secret) do
      RubyLLM::MCP::Auth::ClientInfo.new(
        client_id: "test_client_id",
        client_secret: "test_secret",
        metadata: client_metadata
      )
    end

    let(:token_response) do
      {
        "access_token" => "client_creds_token",
        "token_type" => "Bearer",
        "expires_in" => 3600
      }
    end

    before do
      response = instance_double(HTTPX::Response, status: 200, body: token_response.to_json)
      allow(http_client).to receive(:post).and_return(response)
    end

    it "exchanges client credentials for token" do
      result = manager.exchange_client_credentials(server_metadata, client_info_with_secret, scope, server_url)

      expect(result).to be_a(RubyLLM::MCP::Auth::Token)
      expect(result.access_token).to eq("client_creds_token")
    end

    it "includes client credentials in request" do
      manager.exchange_client_credentials(server_metadata, client_info_with_secret, scope, server_url)

      expect(http_client).to have_received(:post) do |_url, options|
        expect(options[:form][:grant_type]).to eq("client_credentials")
        expect(options[:form][:client_id]).to eq("test_client_id")
        expect(options[:form][:client_secret]).to eq("test_secret")
        expect(options[:form][:scope]).to eq(scope)
      end
    end

    context "when token endpoint returns OAuth error response" do
      let(:oauth_error_response) do
        {
          "error" => "invalid_request",
          "error_description" => "Missing required parameter: grant_type",
          "error_uri" => "https://example.com/docs/oauth-errors#invalid_request"
        }
      end

      before do
        response = instance_double(HTTPX::Response, status: 400, body: oauth_error_response.to_json)
        allow(http_client).to receive(:post).and_return(response)
      end

      it "raises TransportError with OAuth error details from RFC 6749 section 5.2 format" do
        expect do
          manager.exchange_client_credentials(server_metadata, client_info_with_secret, scope, server_url)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError) { |error|
          expect(error.message).to include("OAuth error 'invalid_request'")
          expect(error.message).to include("Missing required parameter: grant_type")
          expect(error.code).to eq(400)
          expect(error.error).to eq("invalid_request")
        }
      end
    end

    context "when token endpoint returns 401 invalid_client error response" do
      let(:oauth_error_response) do
        {
          "error" => "invalid_client",
          "error_description" => "Client authentication failed"
        }
      end

      before do
        response = instance_double(HTTPX::Response, status: 401, body: oauth_error_response.to_json)
        allow(http_client).to receive(:post).and_return(response)
      end

      it "raises TransportError with RFC 6749 invalid_client semantics" do
        expect do
          manager.exchange_client_credentials(server_metadata, client_info_with_secret, scope, server_url)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError) { |error|
          expect(error.message).to include("OAuth error 'invalid_client'")
          expect(error.message).to include("Client authentication failed")
          expect(error.code).to eq(401)
          expect(error.error).to eq("invalid_client")
        }
      end
    end

    context "when token endpoint returns HTTP 200 with OAuth error payload" do
      let(:oauth_error_response) do
        {
          "error" => "invalid_client",
          "error_description" => "Client authentication failed."
        }
      end

      before do
        response = instance_double(HTTPX::Response, status: 200, body: oauth_error_response.to_json)
        allow(http_client).to receive(:post).and_return(response)
      end

      it "raises TransportError instead of creating a token with missing access_token" do
        expect do
          manager.exchange_client_credentials(server_metadata, client_info_with_secret, scope, server_url)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /OAuth error 'invalid_client'/)
      end
    end

    context "when token endpoint returns success status but no access token" do
      let(:incomplete_response) do
        {
          "token_type" => "Bearer",
          "expires_in" => 3600
        }
      end

      before do
        response = instance_double(HTTPX::Response, status: 200, body: incomplete_response.to_json)
        allow(http_client).to receive(:post).and_return(response)
      end

      it "raises a clear TransportError for invalid token payload" do
        expect do
          manager.exchange_client_credentials(server_metadata, client_info_with_secret, scope, server_url)
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /missing access_token/)
      end
    end
  end

  describe "#refresh_token" do
    let(:token) do
      RubyLLM::MCP::Auth::Token.new(
        access_token: "old_token",
        refresh_token: "refresh_token_123"
      )
    end

    let(:refresh_response) do
      {
        "access_token" => "new_access_token",
        "token_type" => "Bearer",
        "expires_in" => 3600
      }
    end

    before do
      response = instance_double(HTTPX::Response, status: 200, body: refresh_response.to_json)
      allow(http_client).to receive(:post).and_return(response)
    end

    it "refreshes token" do
      result = manager.refresh_token(server_metadata, client_info, token, server_url)

      expect(result).to be_a(RubyLLM::MCP::Auth::Token)
      expect(result.access_token).to eq("new_access_token")
    end

    it "preserves old refresh token if not provided in response" do
      result = manager.refresh_token(server_metadata, client_info, token, server_url)

      expect(result.refresh_token).to eq("refresh_token_123")
    end

    context "when response includes new refresh token" do
      let(:refresh_response) do
        {
          "access_token" => "new_access_token",
          "refresh_token" => "new_refresh_token"
        }
      end

      it "uses new refresh token" do
        result = manager.refresh_token(server_metadata, client_info, token, server_url)

        expect(result.refresh_token).to eq("new_refresh_token")
      end
    end

    context "when token has no refresh token" do
      let(:token_without_refresh) do
        RubyLLM::MCP::Auth::Token.new(access_token: "token")
      end

      it "returns nil" do
        result = manager.refresh_token(server_metadata, client_info, token_without_refresh, server_url)

        expect(result).to be_nil
      end
    end

    context "when refresh fails" do
      before do
        error_response = instance_double(HTTPX::ErrorResponse, error: StandardError.new("Connection failed"))
        allow(error_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
        allow(http_client).to receive(:post).and_return(error_response)
      end

      it "returns nil and logs warning" do
        result = manager.refresh_token(server_metadata, client_info, token, server_url)

        expect(result).to be_nil
        expect(logger).to have_received(:warn).with(/Token refresh failed/)
      end
    end

    context "when response is invalid JSON" do
      before do
        response = instance_double(HTTPX::Response, status: 200, body: "invalid json")
        allow(http_client).to receive(:post).and_return(response)
      end

      it "returns nil and logs warning" do
        result = manager.refresh_token(server_metadata, client_info, token, server_url)

        expect(result).to be_nil
        expect(logger).to have_received(:warn).with(/Invalid token refresh response/)
      end
    end

    context "when refresh response contains OAuth error fields" do
      let(:oauth_error_response) do
        {
          "error" => "invalid_grant",
          "error_description" => "Refresh token is expired"
        }
      end

      before do
        response = instance_double(HTTPX::Response, status: 200, body: oauth_error_response.to_json)
        allow(http_client).to receive(:post).and_return(response)
      end

      it "returns nil and logs warning" do
        result = manager.refresh_token(server_metadata, client_info, token, server_url)

        expect(result).to be_nil
        expect(logger).to have_received(:warn).with(
          /Token refresh failed: OAuth error 'invalid_grant'/
        )
      end
    end

    context "when refresh endpoint returns non-200 with OAuth error payload" do
      let(:oauth_error_response) do
        {
          "error" => "invalid_grant",
          "error_description" => "Refresh token is expired"
        }
      end

      before do
        response = instance_double(HTTPX::Response, status: 400, body: oauth_error_response.to_json)
        allow(http_client).to receive(:post).and_return(response)
      end

      it "returns nil and logs OAuth error details" do
        result = manager.refresh_token(server_metadata, client_info, token, server_url)

        expect(result).to be_nil
        expect(logger).to have_received(:warn).with(
          /Token refresh failed: OAuth error 'invalid_grant': Refresh token is expired/
        )
      end
    end
  end
end
