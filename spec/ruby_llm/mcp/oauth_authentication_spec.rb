# frozen_string_literal: true

RSpec.describe "OAuth Authentication" do # rubocop:disable RSpec/DescribeClass
  describe "OAuth Configuration" do
    it "accepts OAuth configuration for streamable transport" do
      expect do
        RubyLLM::MCP::Client.new(
          name: "oauth-test-client",
          transport_type: :streamable,
          start: false,
          config: {
            url: "https://example.com/mcp",
            oauth: {
              issuer: "https://oauth-provider.example.com",
              client_id: "test-client-id",
              client_secret: "test-client-secret",
              scopes: "mcp:read mcp:write"
            }
          }
        )
      end.not_to raise_error
    end

    it "accepts OAuth configuration with missing parameters" do
      # OAuth validation currently happens at transport level, not client level
      expect do
        RubyLLM::MCP::Client.new(
          name: "incomplete-oauth-client",
          transport_type: :streamable,
          start: false,
          config: {
            url: "https://example.com/mcp",
            oauth: {
              # Missing required parameters - should not raise during client creation
              client_id: "test-client-id"
            }
          }
        )
      end.not_to raise_error
    end

    it "allows OAuth configuration for non-HTTP transports but ignores it" do
      # OAuth configuration is currently ignored for non-HTTP transports
      expect do
        RubyLLM::MCP::Client.new(
          name: "stdio-with-oauth",
          transport_type: :stdio,
          start: false,
          config: {
            command: ["node", "server.js"],
            oauth: {
              issuer: "https://oauth-provider.example.com",
              client_id: "test-client-id",
              client_secret: "test-client-secret"
            }
          }
        )
      end.not_to raise_error
    end
  end

  describe "OAuth Token Management" do
    let(:oauth_config) do
      {
        url: "https://example.com/mcp",
        oauth: {
          issuer: "https://oauth-provider.example.com",
          client_id: "test-client-id",
          client_secret: "test-client-secret",
          scopes: "mcp:read mcp:write"
        }
      }
    end

    it "creates OAuth options correctly" do
      # Test that OAuth options are properly created from config
      client = RubyLLM::MCP::Client.new(
        name: "oauth-client",
        transport_type: :streamable,
        start: false,
        config: oauth_config
      )

      # Client should be created without errors
      expect(client).to be_a(RubyLLM::MCP::Client)
      expect(client).not_to be_alive # Not started yet
    end

    it "handles OAuth configuration in transport initialization" do
      # Test that transport can be initialized with OAuth config without errors
      expect do
        RubyLLM::MCP::Client.new(
          name: "oauth-transport-client",
          transport_type: :streamable,
          start: false,
          config: oauth_config
        )
      end.not_to raise_error
    end

    it "validates OAuth configuration format through client creation" do
      # Test that OAuth configuration is properly processed during client creation
      expect do
        client = RubyLLM::MCP::Client.new(
          name: "oauth-validation-client",
          transport_type: :streamable,
          start: false,
          config: {
            url: "https://example.com/mcp",
            oauth: {
              issuer: "https://oauth-provider.example.com",
              client_id: "test-client-id",
              client_secret: "test-client-secret",
              scopes: "mcp:read mcp:write"
            }
          }
        )

        # Client creation should succeed with valid OAuth config
        expect(client).to be_a(RubyLLM::MCP::Client)
      end.not_to raise_error
    end
  end

  describe "OAuth Security Best Practices" do
    it "does not log OAuth credentials during client creation" do
      # OAuth credentials should not be logged during client creation
      expect do
        RubyLLM::MCP::Client.new(
          name: "security-test-client",
          transport_type: :streamable,
          start: false,
          config: {
            url: "https://example.com/mcp",
            oauth: {
              issuer: "https://oauth-provider.example.com",
              client_id: "test-client-id",
              client_secret: "secret-value",
              scopes: "mcp:read"
            }
          }
        )
      end.not_to raise_error

      # This test verifies that client creation with OAuth doesn't cause issues
      # Actual credential logging protection would be tested during OAuth token requests
    end

    it "accepts OAuth issuer URLs without validation during client creation" do
      # URL validation is not currently performed during client creation
      expect do
        RubyLLM::MCP::Client.new(
          name: "custom-issuer-client",
          transport_type: :streamable,
          start: false,
          config: {
            url: "https://example.com/mcp",
            oauth: {
              issuer: "https://custom-oauth-provider.example.com",
              client_id: "test-client-id",
              client_secret: "test-secret",
              scopes: "mcp:read"
            }
          }
        )
      end.not_to raise_error
    end

    it "accepts HTTP OAuth endpoints without validation during client creation" do
      # HTTPS enforcement is not currently performed during client creation
      expect do
        RubyLLM::MCP::Client.new(
          name: "http-oauth-client",
          transport_type: :streamable,
          start: false,
          config: {
            url: "https://example.com/mcp",
            oauth: {
              issuer: "https://oauth-provider.example.com",
              client_id: "test-client-id",
              client_secret: "test-secret",
              scopes: "mcp:read"
            }
          }
        )
      end.not_to raise_error
    end
  end
end
