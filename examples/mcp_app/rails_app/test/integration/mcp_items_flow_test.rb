# frozen_string_literal: true

require "test_helper"

class McpItemsFlowTest < ActionDispatch::IntegrationTest
  FakeClient = Struct.new(:items_response, :embed_response, :created_response, :completed_response, :error, keyword_init: true) do
    def list_items(include_completed: true)
      raise(error) if error

      include_completed ? items_response : items_response.reject { |item| item["done"] }
    end

    def render_items_embed
      raise(error) if error

      embed_response
    end

    def create_item(_description)
      raise(error) if error

      created_response
    end

    def mark_done(_id)
      raise(error) if error

      completed_response
    end
  end

  setup do
    @original_factory = McpItemsController.client_factory
  end

  teardown do
    McpItemsController.client_factory = @original_factory
  end

  test "index renders MCP iframe embed" do
    fake = FakeClient.new(
      items_response: [{ "id" => 7, "description" => "From MCP", "done" => false }],
      embed_response: {
        "html" => "<html><body><button data-action='done' data-id='7'>Done</button></body></html>",
        "item_count" => 1,
        "completed_count" => 0
      },
      created_response: {},
      completed_response: {}
    )

    McpItemsController.client_factory = -> { fake }

    get root_path
    assert_response :success
    assert_includes response.body, "from mcp iframe"
    assert_includes response.body, "MCP items embed"
    assert_includes response.body, "render_items_embed"
    assert_includes response.body, "MCP Toggle Buttons"
    assert_includes response.body, "#7"
    assert_includes response.body, "&quot;item_count&quot;: 1"
  end

  test "create stores last MCP mutation payload and displays it" do
    created = {
      "item" => { "id" => 1, "description" => "alpha", "done" => false },
      "items" => [{ "id" => 1, "description" => "alpha", "done" => false }]
    }
    fake = FakeClient.new(
      items_response: created.fetch("items"),
      embed_response: {
        "html" => "<html><body>#1 · alpha</body></html>",
        "item_count" => 1,
        "completed_count" => 0
      },
      created_response: created,
      completed_response: created
    )

    McpItemsController.client_factory = -> { fake }

    post mcp_items_path, params: { description: "alpha" }
    follow_redirect!

    assert_response :success
    assert_includes response.body, "From MCP: last mutation"
    assert_includes response.body, "&quot;tool&quot;: &quot;create_item&quot;"
    assert_includes response.body, "&quot;description&quot;: &quot;alpha&quot;"
  end

  test "index surfaces MCP fetch failure" do
    fake = FakeClient.new(
      items_response: [],
      embed_response: {},
      created_response: {},
      completed_response: {},
      error: "server down"
    )

    McpItemsController.client_factory = -> { fake }

    get root_path
    assert_response :success
    assert_includes response.body, "Unable to fetch items from MCP server"
    assert_includes response.body, "&quot;error&quot;: &quot;server down&quot;"
  end
end
