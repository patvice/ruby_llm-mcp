RubyLLM MCP has been successfully installed!

The following files have been created:

  config/initializers/ruby_llm_mcp.rb - Main configuration file
  config/mcps.json                    - MCP servers configuration

Next steps:

1. Edit config/initializers/ruby_llm_mcp.rb to configure your MCP settings
2. Edit config/mcps.json to define your MCP servers
3. Install any MCP servers you want to use (e.g., npm install @modelcontextprotocol/server-filesystem) or use remote MCPs
4. Update environment variables for any MCP servers that require authentication

Example usage in your Rails application:

  # With Ruby::MCP installed in a controller or service
  clients = RubyLLM::MCP.clients

  # Get all tools use the configured client
  tools = RubyLLM::MCP.tools

  # Or use the configured client
  client = RubyLLM::MCP.clients["file-system"]

  # Or use the configured client
  tools = client.tools


For more information, visit: https://github.com/patvice/ruby_llm-mcp

===============================================================================
