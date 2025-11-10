# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth do
  describe ".create_oauth" do
    let(:server_url) { "https://mcp.example.com" }
    let(:scope) { "mcp:read mcp:write" }
    let(:callback_port) { 8080 }

    context "with type: :standard" do
      it "creates an OAuthProvider instance" do
        provider = described_class.create_oauth(server_url, type: :standard, scope: scope)

        expect(provider).to be_a(RubyLLM::MCP::Auth::OAuthProvider)
        expect(provider.server_url).to eq(server_url)
        expect(provider.scope).to eq(scope)
      end

      it "passes additional options to OAuthProvider" do
        redirect_uri = "http://localhost:9000/callback"
        provider = described_class.create_oauth(
          server_url,
          type: :standard,
          scope: scope,
          redirect_uri: redirect_uri
        )

        expect(provider).to be_a(RubyLLM::MCP::Auth::OAuthProvider)
        expect(provider.redirect_uri).to eq(redirect_uri)
      end
    end

    context "with type: :browser" do
      it "creates a BrowserOAuthProvider instance" do
        provider = described_class.create_oauth(
          server_url,
          type: :browser,
          callback_port: callback_port,
          scope: scope
        )

        expect(provider).to be_a(RubyLLM::MCP::Auth::BrowserOAuthProvider)
        expect(provider.server_url).to eq(server_url)
        expect(provider.scope).to eq(scope)
        expect(provider.callback_port).to eq(callback_port)
      end

      it "passes additional options to BrowserOAuthProvider" do
        custom_page = "<html><body>Custom</body></html>"
        provider = described_class.create_oauth(
          server_url,
          type: :browser,
          callback_port: 9090,
          scope: scope,
          pages: { success_page: custom_page }
        )

        expect(provider).to be_a(RubyLLM::MCP::Auth::BrowserOAuthProvider)
        expect(provider.callback_port).to eq(9090)
        expect(provider.custom_success_page).to eq(custom_page)
      end
    end

    context "with no type specified" do
      it "defaults to :standard type" do
        provider = described_class.create_oauth(server_url)

        expect(provider).to be_a(RubyLLM::MCP::Auth::OAuthProvider)
      end
    end

    context "with invalid type" do
      it "raises ArgumentError" do
        expect do
          described_class.create_oauth(server_url, type: :invalid)
        end.to raise_error(ArgumentError, /Unknown OAuth type.*invalid/)
      end

      it "provides helpful error message" do
        expect do
          described_class.create_oauth(server_url, type: :custom)
        end.to raise_error(ArgumentError, /Must be :standard or :browser/)
      end
    end
  end
end
