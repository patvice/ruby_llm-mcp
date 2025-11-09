# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::HttpResponseHandler do
  describe ".handle_response" do
    context "with successful response" do
      let(:response) do
        instance_double(
          HTTPX::Response,
          status: 200,
          body: '{"access_token": "test_token"}'
        )
      end

      it "returns parsed JSON" do
        result = described_class.handle_response(response, context: "Token exchange")
        expect(result).to eq({ "access_token" => "test_token" })
      end
    end

    context "with alternative successful status" do
      let(:response) do
        instance_double(
          HTTPX::Response,
          status: 201,
          body: '{"client_id": "test_id"}'
        )
      end

      it "accepts expected status" do
        result = described_class.handle_response(response, context: "Client registration", expected_status: 201)
        expect(result).to eq({ "client_id" => "test_id" })
      end

      it "accepts multiple expected statuses" do
        result = described_class.handle_response(response, context: "Client registration", expected_status: [200, 201])
        expect(result).to eq({ "client_id" => "test_id" })
      end
    end

    context "with error response" do
      let(:error) { StandardError.new("Connection refused") }
      let(:response) do
        instance_double(
          HTTPX::ErrorResponse,
          error: error
        )
      end

      before do
        allow(response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
      end

      it "raises TransportError with error message" do
        expect do
          described_class.handle_response(response, context: "Token exchange")
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Token exchange failed: Connection refused/)
      end
    end

    context "with error response without error object" do
      let(:response) do
        instance_double(
          HTTPX::ErrorResponse,
          error: nil
        )
      end

      before do
        allow(response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
      end

      it "raises TransportError with generic message" do
        expect do
          described_class.handle_response(response, context: "Token exchange")
        end.to raise_error(RubyLLM::MCP::Errors::TransportError, /Token exchange failed: Request failed/)
      end
    end

    context "with unexpected status code" do
      let(:response) do
        instance_double(
          HTTPX::Response,
          status: 401,
          body: '{"error": "unauthorized"}'
        )
      end

      it "raises TransportError with status code" do
        expect do
          described_class.handle_response(response, context: "Token exchange")
        end.to raise_error(RubyLLM::MCP::Errors::TransportError) do |error| # rubocop:disable Style/MultilineBlockChain
          expect(error.message).to include("Token exchange failed: HTTP 401")
          expect(error.code).to eq(401)
        end
      end
    end
  end

  describe ".extract_redirect_mismatch" do
    context "with valid redirect mismatch error" do
      let(:body) do
        {
          error: "unauthorized_client",
          error_description: "You sent http://localhost:8080/callback and we expected http://localhost:3000/callback"
        }.to_json
      end

      it "extracts mismatch details" do
        result = described_class.extract_redirect_mismatch(body)

        expect(result).to eq(
          sent: "http://localhost:8080/callback",
          expected: "http://localhost:3000/callback",
          description: "You sent http://localhost:8080/callback and we expected http://localhost:3000/callback"
        )
      end
    end

    context "with alternative error description format" do
      let(:body) do
        {
          error: "unauthorized_client",
          error_description: "You sent https://app.example.com/auth/callback, and we expected https://app.example.com/oauth/callback."
        }.to_json
      end

      it "extracts mismatch details" do
        result = described_class.extract_redirect_mismatch(body)

        expect(result[:sent]).to eq("https://app.example.com/auth/callback")
        expect(result[:expected]).to eq("https://app.example.com/oauth/callback")
      end
    end

    context "with non-redirect-mismatch error" do
      let(:body) do
        {
          error: "invalid_grant",
          error_description: "The authorization code is invalid"
        }.to_json
      end

      it "returns nil" do
        result = described_class.extract_redirect_mismatch(body)
        expect(result).to be_nil
      end
    end

    context "with unauthorized_client but no matching description" do
      let(:body) do
        {
          error: "unauthorized_client",
          error_description: "Client is not authorized"
        }.to_json
      end

      it "returns nil" do
        result = described_class.extract_redirect_mismatch(body)
        expect(result).to be_nil
      end
    end

    context "with invalid JSON" do
      let(:body) { "not valid json" }

      it "returns nil" do
        result = described_class.extract_redirect_mismatch(body)
        expect(result).to be_nil
      end
    end

    context "with symbol keys" do
      let(:body) do
        {
          error: "unauthorized_client",
          error_description: "You sent http://old.example.com and we expected http://new.example.com"
        }.to_json
      end

      it "handles both string and symbol keys" do
        result = described_class.extract_redirect_mismatch(body)
        expect(result).not_to be_nil
      end
    end
  end
end
