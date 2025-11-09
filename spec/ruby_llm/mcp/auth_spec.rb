# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth do
  describe RubyLLM::MCP::Auth::Token do
    let(:access_token) { "test_access_token" }
    let(:expires_in) { 3600 }
    let(:refresh_token) { "test_refresh_token" }

    describe "#initialize" do
      it "creates a token with required parameters" do
        token = described_class.new(access_token: access_token)

        expect(token.access_token).to eq(access_token)
        expect(token.token_type).to eq("Bearer")
      end

      it "calculates expires_at from expires_in" do
        freeze_time do
          token = described_class.new(access_token: access_token, expires_in: expires_in)

          expect(token.expires_at).to be_within(1).of(Time.now + expires_in)
        end
      end

      it "stores optional parameters" do
        token = described_class.new(
          access_token: access_token,
          expires_in: expires_in,
          scope: "read write",
          refresh_token: refresh_token
        )

        expect(token.scope).to eq("read write")
        expect(token.refresh_token).to eq(refresh_token)
      end
    end

    describe "#expired?" do
      it "returns false for fresh token" do
        token = described_class.new(access_token: access_token, expires_in: 3600)

        expect(token.expired?).to be(false)
      end

      it "returns true for expired token" do
        freeze_time do
          token = described_class.new(access_token: access_token, expires_in: 3600)
          travel_to(Time.now + 3601)

          expect(token.expired?).to be(true)
        end
      end

      it "returns false when no expiration" do
        token = described_class.new(access_token: access_token)

        expect(token.expired?).to be(false)
      end
    end

    describe "#expires_soon?" do
      it "returns false for fresh token" do
        token = described_class.new(access_token: access_token, expires_in: 3600)

        expect(token.expires_soon?).to be(false)
      end

      it "returns true when token expires within 5 minutes" do
        freeze_time do
          token = described_class.new(access_token: access_token, expires_in: 3600)
          travel_to(Time.now + 3400) # 200 seconds left

          expect(token.expires_soon?).to be(true)
        end
      end

      it "returns false when no expiration" do
        token = described_class.new(access_token: access_token)

        expect(token.expires_soon?).to be(false)
      end
    end

    describe "#to_header" do
      it "formats authorization header" do
        token = described_class.new(access_token: access_token)

        expect(token.to_header).to eq("Bearer #{access_token}")
      end

      it "uses custom token type" do
        token = described_class.new(access_token: access_token, token_type: "Custom")

        expect(token.to_header).to eq("Custom #{access_token}")
      end
    end

    describe "#to_h and .from_h" do
      it "serializes and deserializes token" do
        original = described_class.new(
          access_token: access_token,
          expires_in: expires_in,
          scope: "read write",
          refresh_token: refresh_token
        )

        hash = original.to_h
        restored = described_class.from_h(hash)

        expect(restored.access_token).to eq(original.access_token)
        expect(restored.refresh_token).to eq(original.refresh_token)
        expect(restored.scope).to eq(original.scope)
      end
    end
  end

  describe RubyLLM::MCP::Auth::ClientMetadata do
    describe "#initialize" do
      it "creates metadata with defaults" do
        metadata = described_class.new(redirect_uris: ["http://localhost:8080/callback"])

        expect(metadata.redirect_uris).to eq(["http://localhost:8080/callback"])
        expect(metadata.token_endpoint_auth_method).to eq("none")
        expect(metadata.grant_types).to eq(%w[authorization_code refresh_token])
        expect(metadata.response_types).to eq(["code"])
      end
    end

    describe "#to_h" do
      it "converts to hash" do
        metadata = described_class.new(
          redirect_uris: ["http://localhost:8080/callback"],
          scope: "read write"
        )

        hash = metadata.to_h

        expect(hash[:redirect_uris]).to eq(["http://localhost:8080/callback"])
        expect(hash[:scope]).to eq("read write")
      end
    end
  end

  describe RubyLLM::MCP::Auth::ClientInfo do
    let(:client_id) { "test_client_id" }
    let(:client_secret) { "test_client_secret" }
    let(:metadata) { RubyLLM::MCP::Auth::ClientMetadata.new(redirect_uris: ["http://localhost:8080/callback"]) }

    describe "#initialize" do
      it "creates client info" do
        info = described_class.new(
          client_id: client_id,
          client_secret: client_secret,
          metadata: metadata
        )

        expect(info.client_id).to eq(client_id)
        expect(info.client_secret).to eq(client_secret)
        expect(info.metadata).to eq(metadata)
      end
    end

    describe "#client_secret_expired?" do
      it "returns false when no expiration" do
        info = described_class.new(client_id: client_id, client_secret: client_secret)

        expect(info.client_secret_expired?).to be(false)
      end

      it "returns true when expired" do
        freeze_time do
          expires_at = Time.now.to_i + 3600
          info = described_class.new(
            client_id: client_id,
            client_secret: client_secret,
            client_secret_expires_at: expires_at
          )

          travel_to(Time.at(expires_at + 1))

          expect(info.client_secret_expired?).to be(true)
        end
      end
    end

    describe "#to_h and .from_h" do
      it "serializes and deserializes client info" do
        original = described_class.new(
          client_id: client_id,
          client_secret: client_secret,
          metadata: metadata
        )

        hash = original.to_h
        restored = described_class.from_h(hash)

        expect(restored.client_id).to eq(original.client_id)
        expect(restored.client_secret).to eq(original.client_secret)
      end
    end
  end

  describe RubyLLM::MCP::Auth::ServerMetadata do
    let(:issuer) { "https://auth.example.com" }
    let(:authorization_endpoint) { "https://auth.example.com/authorize" }
    let(:token_endpoint) { "https://auth.example.com/token" }
    let(:registration_endpoint) { "https://auth.example.com/register" }

    describe "#initialize" do
      it "creates server metadata" do
        metadata = described_class.new(
          issuer: issuer,
          authorization_endpoint: authorization_endpoint,
          token_endpoint: token_endpoint,
          options: { registration_endpoint: registration_endpoint }
        )

        expect(metadata.issuer).to eq(issuer)
        expect(metadata.authorization_endpoint).to eq(authorization_endpoint)
      end
    end

    describe "#supports_registration?" do
      it "returns true when registration endpoint exists" do
        metadata = described_class.new(
          issuer: issuer,
          authorization_endpoint: authorization_endpoint,
          token_endpoint: token_endpoint,
          options: { registration_endpoint: registration_endpoint }
        )

        expect(metadata.supports_registration?).to be(true)
      end

      it "returns false when no registration endpoint" do
        metadata = described_class.new(
          issuer: issuer,
          authorization_endpoint: authorization_endpoint,
          token_endpoint: token_endpoint,
          options: {}
        )

        expect(metadata.supports_registration?).to be(false)
      end
    end
  end

  describe RubyLLM::MCP::Auth::PKCE do
    describe "#initialize" do
      it "generates code verifier and challenge" do
        pkce = described_class.new

        expect(pkce.code_verifier).to be_a(String)
        expect(pkce.code_challenge).to be_a(String)
        expect(pkce.code_challenge_method).to eq("S256")
      end

      it "generates unique values each time" do
        pkce1 = described_class.new
        pkce2 = described_class.new

        expect(pkce1.code_verifier).not_to eq(pkce2.code_verifier)
        expect(pkce1.code_challenge).not_to eq(pkce2.code_challenge)
      end
    end

    describe "#to_h and .from_h" do
      it "serializes and deserializes PKCE" do
        original = described_class.new

        hash = original.to_h
        restored = described_class.from_h(hash)

        expect(restored.code_verifier).to eq(original.code_verifier)
        expect(restored.code_challenge).to eq(original.code_challenge)
        expect(restored.code_challenge_method).to eq(original.code_challenge_method)
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
