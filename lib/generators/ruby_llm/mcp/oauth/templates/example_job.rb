# frozen_string_literal: true

# Example background job using MCP with per-user OAuth
class AiResearchJob < ApplicationJob
  queue_as :default

  # Retry on authentication errors (user might reconnect)
  retry_on McpClientFactory::NotAuthenticatedError,
           wait: 1.hour,
           attempts: 3 do |job, _exception|
    # After retries exhausted, notify user
    user = User.find(job.arguments.first)
    UserMailer.mcp_auth_required(user).deliver_now
  end

  # Retry on transient network errors
  retry_on RubyLLM::MCP::Errors::TransportError,
           wait: :exponentially_longer,
           attempts: 5

  # Perform AI research using user's MCP connection
  # @param user_id [Integer] ID of the user
  # @param query [String] research query
  # @param options [Hash] additional options
  def perform(user_id, query, options = {})
    user = User.find(user_id)

    # Create MCP client with user's OAuth token
    client = McpClientFactory.for_user(user)

    begin
      # Get tools with user's permissions
      tools = client.tools
      Rails.logger.info "Loaded #{tools.count} MCP tools for user #{user_id}"

      # Create AI chat with user's MCP context
      chat = RubyLLM.chat(provider: options[:provider] || "anthropic/claude-sonnet-4")
                    .with_tools(*tools)

      # Execute research
      response = chat.ask(query)

      # Save results
      save_research_results(user, query, response)

      # Notify user of completion
      notify_completion(user, query)

      Rails.logger.info "Completed AI research for user #{user_id}"
    ensure
      # Always close client connection
      client&.stop
    end
  end

  private

  def save_research_results(user, query, response)
    # Customize based on your schema
    user.research_results.create!(
      query: query,
      result: response.text,
      completed_at: Time.current
    )
  end

  def notify_completion(user, query)
    # Notify via email, ActionCable, or other mechanism
    ActionCable.server.broadcast(
      "user_#{user.id}_notifications",
      {
        type: "research_complete",
        message: "Research completed: #{query.truncate(50)}"
      }
    )
  end
end
