---
layout: default
title: Rails Integration
parent: Guides
nav_order: 9
description: "Complete Rails integration with generators, configuration, and automatic client management"
---

# Rails Integration
{: .no_toc }

RubyLLM MCP provides seamless Rails integration through generators, automatic client management, and built-in patterns for common Rails use cases.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Installation and Setup

### Generator Installation

Generate the initial configuration files:

```bash
rails generate ruby_llm:mcp:install
```

This creates:

- `config/initializers/ruby_llm_mcp.rb` - Main configuration
- `config/mcps.yml` - MCP servers configuration

### Generated Files

#### `config/initializers/ruby_llm_mcp.rb`

```ruby
RubyLLM::MCP.configure do |config|
  # Global configuration
  config.log_level = Rails.env.production? ? Logger::WARN : Logger::INFO
  config.logger = Rails.logger

  # Enable complex parameter support
  config.support_complex_parameters!

  # Configure roots for filesystem access
  config.roots = [Rails.root] if Rails.env.development?

  # Configure sampling (optional)
  config.sampling.enabled = false # Set to true to enable
  config.sampling.preferred_model = "gpt-4"
  config.sampling.guard do |sample|
    # Add your sampling validation logic here
    true
  end
end

# Choose your client management strategy
RubyLLM::MCP.launch_control = :manual # or :automatic

# For automatic client management, uncomment:
# RubyLLM::MCP.launch_control = :automatic
# RubyLLM::MCP.start_all_clients
```

#### `config/mcps.yml`

```yaml
mcp_servers:
  filesystem:
    transport_type: stdio
    command: bunx
    args:
      - "@modelcontextprotocol/server-filesystem"
      - "<%= Rails.root %>"
    env: {}
    with_prefix: true

  # Example SSE server
  # api_server:
  #   transport_type: sse
  #   url: "https://api.example.com/mcp/sse"
  #   headers:
  #     Authorization: "Bearer <%= ENV['API_TOKEN'] %>"

  # Example streamable HTTP server
  # http_server:
  #   transport_type: streamable
  #   url: "https://api.example.com/mcp"
  #   headers:
  #     Authorization: "Bearer <%= ENV['API_TOKEN'] %>"
```

## Client Management Strategies

### Automatic Client Management

For more basic use cases, you can run MCP clients and sub-processes directly along side your Rails application. Automatically starting clients is a good choice for most basic use cases, development, testing and getting started.

```ruby
# config/initializers/ruby_llm_mcp.rb
RubyLLM::MCP.launch_control = :automatic
RubyLLM::MCP.start_all_clients

# Clients are automatically available throughout the application
clients = RubyLLM::MCP.clients
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*clients.tools)
```

### Manual Client Management

Due to the performace of LLMs, it's likely that for production workloads you would want to that you will want to use LLM requests inside background job or streamable endpoints. Manual controller will give you more control over client connections and where they run.

```ruby
# config/initializers/ruby_llm_mcp.rb
RubyLLM::MCP.launch_control = :manual

# In your application code
RubyLLM::MCP.establish_connection do |clients|
  chat = RubyLLM.chat(model: "gpt-4")
  chat.with_tools(*clients.tools)

  response = chat.ask("Analyze the project structure")
  puts response
end
```

## Examples

### Background Job Integration

```ruby
class MCPAnalysisJob < ApplicationJob
  queue_as :default

  def perform(project_path)
    RubyLLM::MCP.establish_connection do |clients|
      # Add filesystem root for the project
      clients.each { |client| client.roots.add(project_path) }

      # Create chat with tools
      chat = RubyLLM.chat(model: "gpt-4")
      chat.with_tools(*clients.tools)

      # Analyze the project
      analysis = chat.ask("Analyze the code structure and provide recommendations")

      # Store results
      AnalysisResult.create!(
        project_path: project_path,
        analysis: analysis,
        completed_at: Time.current
      )
    end
  end
end

# Usage
MCPAnalysisJob.perform_later("/path/to/project")
```

### Advanced Job with Progress Tracking

```ruby
class AdvancedMCPJob < ApplicationJob
  include Rails.application.routes.url_helpers

  def perform(user_id, task_params)
    user = User.find(user_id)

    RubyLLM::MCP.establish_connection do |clients|
      # Setup progress tracking
      setup_progress_tracking(clients, user)

      # Configure roots based on user permissions
      configure_user_roots(clients, user)

      # Execute the task
      result = execute_mcp_task(clients, task_params)

      # Notify user of completion
      notify_completion(user, result)
    end
  end

  private

  def setup_progress_tracking(clients, user)
    clients.each do |client|
      client.on_progress do |progress|
        # Broadcast progress via ActionCable
        ActionCable.server.broadcast(
          "user_#{user.id}_progress",
          { progress: progress.progress, message: progress.message }
        )
      end
    end
  end

  def configure_user_roots(clients, user)
    # Only allow access to user's projects
    user.projects.each do |project|
      clients.each { |client| client.roots.add(project.path) }
    end
  end

  def execute_mcp_task(clients, params)
    chat = RubyLLM.chat(model: params[:model] || "gpt-4")
    chat.with_tools(*clients.tools)

    # Add user-specific context
    chat.with_resource(get_user_context_resource(clients))

    chat.ask(params[:query])
  end

  def get_user_context_resource(clients)
    # Get a user-specific resource
    clients.first.resource("user_preferences")
  end

  def notify_completion(user, result)
    UserMailer.mcp_task_completed(user, result).deliver_now
  end
end
```

### Controller Integration for Basic Controller Usage

```ruby
class AnalysisController < ApplicationController
  def create
    authorize_mcp_access!

    result = RubyLLM::MCP.establish_connection do |clients|
      chat = RubyLLM.chat(model: params[:model] || "gpt-4")
      chat.with_tools(*clients.tools)

      # Add project context if specified
      if params[:project_id]
        project = current_user.projects.find(params[:project_id])
        clients.each { |client| client.roots.add(project.path) }
      end

      chat.ask(params[:query])
    end

    render json: { analysis: result }
  rescue RubyLLM::MCP::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def authorize_mcp_access!
    unless current_user.can_use_mcp?
      render json: { error: "MCP access not authorized" }, status: :forbidden
    end
  end
end
```

### Streaming Controller

```ruby
class StreamingAnalysisController < ApplicationController
  include ActionController::Live

  def create
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'

    begin
      RubyLLM::MCP.establish_connection do |clients|
        chat = RubyLLM.chat(model: "gpt-4")
        chat.with_tools(*clients.tools)

        chat.ask(params[:query]) do |chunk|
          if chunk.tool_call?
            # Send tool usage information
            chunk.tool_calls.each do |key, tool_call|
              response.stream.write("data: #{json_event(:tool_call, {
                name: tool_call.name,
                parameters: tool_call.parameters
              })}\n\n")
            end
          else
            # Send content chunk
            response.stream.write("data: #{json_event(:content, {
              text: chunk.content
            })}\n\n")
          end
        end

        response.stream.write("data: #{json_event(:complete, {})}\n\n")
      end
    rescue => e
      response.stream.write("data: #{json_event(:error, {
        message: e.message
      })}\n\n")
    ensure
      response.stream.close
    end
  end

  private

  def json_event(type, data)
    { type: type, data: data }.to_json
  end
end
```

## Next Steps

Now that you have comprehensive Rails integration set up:

1. **Configure your MCP servers** in `config/mcps.yml`
2. **Choose your client management strategy** (manual vs automatic)
3. **Implement MCP services** for your specific use cases
4. **Add proper error handling and monitoring**
5. **Set up tests** for your MCP integrations

For more detailed information on specific topics:

- **[Configuration]({% link configuration.md %})** - Advanced client configuration
- **[Tools]({% link server/tools.md %})** - Working with MCP tools
- **[Resources]({% link server/resources.md %})** - Managing resources and templates
- **[Notifications]({% link server/notifications.md %})** - Handling real-time updates
