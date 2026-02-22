# frozen_string_literal: true

require "test_helper"

class McpAppClientTest < ActiveSupport::TestCase
  DATA_FILE = Rails.root.join("..", "test_server", "data", "items.json")
  NODE_MODULES = Rails.root.join("..", "test_server", "node_modules")

  setup do
    skip("Run ../bin/setup first to install test_server dependencies") unless NODE_MODULES.directory?
    DATA_FILE.write(JSON.pretty_generate({ nextId: 1, items: [] }))
  end

  test "list, create, and complete through MCP" do
    client = McpAppClient.new

    assert_equal [], client.list_items

    created = client.create_item("from test")
    assert_equal "from test", created.dig("item", "description")
    assert_equal false, created.dig("item", "done")

    id = created.dig("item", "id")
    completed = client.mark_done(id)
    assert_equal true, completed.dig("item", "done")

    list = client.list_items
    assert_equal 1, list.length
    assert_equal true, list.first["done"]
  end

  test "render_items_embed returns html from MCP" do
    client = McpAppClient.new
    client.create_item("iframe source")

    embed = client.render_items_embed
    assert_includes embed.fetch("html"), "Hide completed (MCP iframe UI)"
    assert_equal 1, embed.fetch("item_count")
    assert_equal 0, embed.fetch("completed_count")
  end

  test "raises when MCP returns tool error payload" do
    client = McpAppClient.new
    error = assert_raises(RuntimeError) { client.mark_done(999) }
    assert_match("Item 999 not found", error.message)
  end
end
