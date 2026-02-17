# frozen_string_literal: true

class McpAppClient
  def list_items(include_completed: true)
    payload = with_tool_call("list_items", include_completed: include_completed)
    payload.fetch("items")
  end

  def render_items_embed
    with_tool_call("render_items_embed")
  end

  def create_item(description)
    with_tool_call("create_item", description: description)
  end

  def mark_done(id)
    with_tool_call("mark_done", id: id)
  end

  def toggle_done(id)
    with_tool_call("toggle_done", id: id)
  end

  private

  def with_tool_call(tool_name, **params)
    RubyLLM::MCP.establish_connection do |clients|
      client = clients[:mcp_app] || clients.values.first
      raise "No MCP clients configured" unless client

      tool = client.tool(tool_name, refresh: true)
      raise "Tool '#{tool_name}' not found" unless tool

      result = tool.execute(**params)
      raise result[:error] if result.is_a?(Hash) && result[:error]
      raise result.message if result.is_a?(StandardError)

      parse_json(result.to_s)
    end
  end

  def parse_json(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    { "message" => raw }
  end
end
