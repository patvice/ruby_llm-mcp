# frozen_string_literal: true

class McpItemsController < ApplicationController
  class_attribute :client_factory, default: -> { McpAppClient.new }

  def index
    @items = mcp_app_client.list_items
    @open_items = @items.reject { |item| item["done"] }
    @completed_items = @items.select { |item| item["done"] }

    embed = mcp_app_client.render_items_embed
    @mcp_items_iframe_html = embed.fetch("html", "")

    @mcp_list_payload = wrap_payload(
      tool: "render_items_embed",
      response: embed.except("html")
    )
    @mcp_last_action_payload = session.delete(:mcp_last_action_payload)
  rescue StandardError => e
    @items = []
    @open_items = []
    @completed_items = []
    @mcp_items_iframe_html = ""
    @mcp_list_payload = wrap_payload(tool: "render_items_embed", response: { "error" => e.message })
    @mcp_last_action_payload = session.delete(:mcp_last_action_payload)
    flash.now[:alert] = "Unable to fetch items from MCP server: #{e.message}"
  end

  def create
    description = params.fetch(:description, "").strip
    return redirect_to(root_path, alert: "Description cannot be blank") if description.empty?

    response = mcp_app_client.create_item(description)
    session[:mcp_last_action_payload] = wrap_payload(tool: "create_item", response: response)
    redirect_to root_path, notice: "Item created"
  rescue StandardError => e
    redirect_to root_path, alert: "Create failed: #{e.message}"
  end

  def complete
    id = Integer(params[:id], exception: false)
    return redirect_to(root_path, alert: "Invalid item id") unless id

    response = mcp_app_client.mark_done(id)
    session[:mcp_last_action_payload] = wrap_payload(tool: "mark_done", response: response)
    redirect_to root_path, notice: "Item marked done"
  rescue StandardError => e
    redirect_to root_path, alert: "Update failed: #{e.message}"
  end

  def toggle
    id = Integer(params[:id], exception: false)
    unless id
      return respond_to do |format|
        format.html { redirect_to root_path, alert: "Invalid item id" }
        format.json { render json: { ok: false, error: "Invalid item id" }, status: :unprocessable_entity }
      end
    end

    response = mcp_app_client.toggle_done(id)
    session[:mcp_last_action_payload] = wrap_payload(tool: "toggle_done", response: response)
    respond_to do |format|
      format.html { redirect_to root_path, notice: "Item toggled" }
      format.json { render json: { ok: true, item: response["item"] } }
    end
  rescue StandardError => e
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Toggle failed: #{e.message}" }
      format.json { render json: { ok: false, error: e.message }, status: :unprocessable_entity }
    end
  end

  private

  def mcp_app_client
    @mcp_app_client ||= self.class.client_factory.call
  end

  def wrap_payload(tool:, response:)
    {
      "tool" => tool,
      "received_at" => Time.current.iso8601,
      "response" => response
    }
  end
end
