# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::UrlBuilder do
  describe ".build_discovery_url" do
    it "builds authorization server discovery URL" do
      url = described_class.build_discovery_url("https://mcp.example.com/api", :authorization_server)
      expect(url).to eq("https://mcp.example.com/.well-known/oauth-authorization-server")
    end

    it "builds protected resource discovery URL" do
      url = described_class.build_discovery_url("https://mcp.example.com/api", :protected_resource)
      expect(url).to eq("https://mcp.example.com/.well-known/oauth-protected-resource")
    end

    it "preserves non-default ports" do
      url = described_class.build_discovery_url("https://mcp.example.com:8443/api", :authorization_server)
      expect(url).to eq("https://mcp.example.com:8443/.well-known/oauth-authorization-server")
    end

    it "removes default HTTPS port" do
      url = described_class.build_discovery_url("https://mcp.example.com:443/api", :authorization_server)
      expect(url).to eq("https://mcp.example.com/.well-known/oauth-authorization-server")
    end

    it "removes default HTTP port" do
      url = described_class.build_discovery_url("http://localhost:80/api", :authorization_server)
      expect(url).to eq("http://localhost/.well-known/oauth-authorization-server")
    end

    it "strips path from server URL" do
      url = described_class.build_discovery_url("https://mcp.example.com/api/v1/mcp", :authorization_server)
      expect(url).to eq("https://mcp.example.com/.well-known/oauth-authorization-server")
    end
  end

  describe ".build_authorization_url" do
    let(:pkce) { RubyLLM::MCP::Auth::PKCE.new }

    it "builds complete authorization URL with all parameters" do # rubocop:disable RSpec/MultipleExpectations
      url = described_class.build_authorization_url(
        "https://auth.example.com/authorize",
        "client123",
        "http://localhost:8080/callback",
        "mcp:read mcp:write",
        "state456",
        pkce,
        "https://mcp.example.com/api"
      )

      uri = URI.parse(url)
      params = URI.decode_www_form(uri.query).to_h

      expect(uri.scheme).to eq("https")
      expect(uri.host).to eq("auth.example.com")
      expect(uri.path).to eq("/authorize")
      expect(params["response_type"]).to eq("code")
      expect(params["client_id"]).to eq("client123")
      expect(params["redirect_uri"]).to eq("http://localhost:8080/callback")
      expect(params["scope"]).to eq("mcp:read mcp:write")
      expect(params["state"]).to eq("state456")
      expect(params["code_challenge"]).to eq(pkce.code_challenge)
      expect(params["code_challenge_method"]).to eq("S256")
      expect(params["resource"]).to eq("https://mcp.example.com/api")
    end

    it "omits nil scope parameter" do
      url = described_class.build_authorization_url(
        "https://auth.example.com/authorize",
        "client123",
        "http://localhost:8080/callback",
        nil,
        "state456",
        pkce,
        "https://mcp.example.com/api"
      )

      uri = URI.parse(url)
      params = URI.decode_www_form(uri.query).to_h

      expect(params).not_to have_key("scope")
    end
  end

  describe ".get_authorization_base_url" do
    it "extracts base URL from server URL" do
      base_url = described_class.get_authorization_base_url("https://mcp.example.com/api/v1")
      expect(base_url).to eq("https://mcp.example.com")
    end

    it "preserves non-default ports" do
      base_url = described_class.get_authorization_base_url("https://mcp.example.com:8443/api")
      expect(base_url).to eq("https://mcp.example.com:8443")
    end

    it "removes default HTTPS port" do
      base_url = described_class.get_authorization_base_url("https://mcp.example.com:443/api")
      expect(base_url).to eq("https://mcp.example.com")
    end

    it "removes default HTTP port" do
      base_url = described_class.get_authorization_base_url("http://localhost:80/api")
      expect(base_url).to eq("http://localhost")
    end
  end

  describe ".default_port?" do
    it "returns true for HTTP default port 80" do
      uri = URI.parse("http://example.com:80")
      expect(described_class.default_port?(uri)).to be true
    end

    it "returns true for HTTPS default port 443" do
      uri = URI.parse("https://example.com:443")
      expect(described_class.default_port?(uri)).to be true
    end

    it "returns false for non-default HTTP port" do
      uri = URI.parse("http://example.com:8080")
      expect(described_class.default_port?(uri)).to be false
    end

    it "returns false for non-default HTTPS port" do
      uri = URI.parse("https://example.com:8443")
      expect(described_class.default_port?(uri)).to be false
    end
  end
end
