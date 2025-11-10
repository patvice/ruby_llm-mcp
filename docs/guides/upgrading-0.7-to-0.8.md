---
layout: default
title: Upgrading from 0.8 to 0.9
parent: Guides
nav_order: 11
description: "Guide for upgrading from RubyLLM MCP 0.8 to 0.9 with breaking changes and migration steps"
---

# Upgrading from 0.8 to 0.9
{: .no_toc }

This guide covers the breaking changes and migration steps when upgrading from RubyLLM MCP version 0.8.x to 0.9.x.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Breaking Changes

### Automatic Launch Control Removed from Rails Applications

{: .label .label-red }
Breaking Change

**What Changed:**

Version 0.8 and earlier supported automatic client management in Rails applications via `launch_control`:

```ruby
# Version 0.8.x (REMOVED - no longer supported)
RubyLLM::MCP.launch_control = :automatic
RubyLLM::MCP.start_all_clients

# Clients would automatically start with the Rails application
clients = RubyLLM::MCP.clients
```

**In version 0.9, automatic launch control has been removed** for Rails applications. This feature was problematic because:

1. **Process Management Issues**: Long-running MCP clients (especially stdio transports) don't integrate well with Rails application lifecycle
2. **Memory Leaks**: Automatically started clients could accumulate in development with code reloading
3. **Background Jobs**: Most production use cases run MCP operations in background jobs, not in the main Rails process
4. **Resource Management**: Manual connection management provides better control over when clients start/stop

### Why This Change?

Based on real-world usage patterns, we found that:

- **Development**: Automatic clients caused issues with Rails code reloading and process management
- **Production**: Background jobs are the recommended pattern, which requires manual connection management anyway
- **Testing**: Automatic clients added complexity to test environments
- **Multi-user Apps**: OAuth-based applications always need per-request client creation

The manual pattern with `establish_connection` is more reliable, predictable, and aligns with production best practices.

## What Changed in This Version

{: .label .label-yellow }
Deprecation Period

**Version 0.9 Behavior:**

In version 0.9, the `launch_control` configuration option is **deprecated but still functional**. If you use it, you'll see a warning:

```ruby
# config/initializers/ruby_llm_mcp.rb
RubyLLM::MCP.launch_control = :automatic

# Output:
# [DEPRECATION] RubyLLM::MCP.launch_control is deprecated and will be removed in version 0.10.
# Please migrate to using RubyLLM::MCP.establish_connection blocks.
# See: https://github.com/patvice/ruby_llm-mcp/blob/main/docs/guides/upgrading-0.8-to-0.9.md
```

**Version 0.10+ Behavior:**

Starting with version 0.10, the `launch_control` configuration will be **completely removed**. Attempting to use it will raise an error:

```ruby
# Version 0.10+ (future)
RubyLLM::MCP.launch_control = :automatic
# => NoMethodError: undefined method `launch_control=' for RubyLLM::MCP:Module
```

**Migration Timeline:**

| Version | Status | Action Required |
|---------|--------|-----------------|
| **0.8 and earlier** | Fully supported | None |
| **0.9.x** | Deprecated (with warnings) | Migrate during this version |
| **0.10+** | Removed | Must migrate before upgrading |

{: .warning }
**Recommended Action**: Migrate to `establish_connection` blocks **now** during version 0.9 to ensure a smooth upgrade path to future versions.

## Migration Guide

### Step 1: Update Your Gemfile

```ruby
# Gemfile
gem 'ruby_llm-mcp', '~> 0.9'
```

Then run:

```bash
bundle update ruby_llm-mcp
```

### Step 2: Remove Automatic Launch Configuration

Remove these lines from your Rails initializer:

```ruby
# config/initializers/ruby_llm_mcp.rb

# ❌ REMOVE - No longer supported
RubyLLM::MCP.launch_control = :automatic
RubyLLM::MCP.start_all_clients

# ❌ REMOVE - No longer needed
RubyLLM::MCP.launch_control = :manual
```

The `launch_control` configuration option has been completely removed.

### Step 3: Migrate to Connection Blocks

Replace automatic client access with `establish_connection` blocks:

#### Before (Version 0.8.x)

```ruby
# config/initializers/ruby_llm_mcp.rb
RubyLLM::MCP.launch_control = :automatic
RubyLLM::MCP.start_all_clients

# app/controllers/analysis_controller.rb
class AnalysisController < ApplicationController
  def create
    clients = RubyLLM::MCP.clients  # ❌ No longer works

    chat = RubyLLM.chat(model: "gpt-4")
    chat.with_tools(*clients.tools)

    result = chat.ask(params[:query])
    render json: { result: result }
  end
end
```

#### After (Version 0.9.x)

```ruby
# config/initializers/ruby_llm_mcp.rb
# No launch_control configuration needed - removed entirely

# app/controllers/analysis_controller.rb
class AnalysisController < ApplicationController
  def create
    result = RubyLLM::MCP.establish_connection do |clients|
      chat = RubyLLM.chat(model: "gpt-4")
      chat.with_tools(*clients.tools)

      chat.ask(params[:query])
    end

    render json: { result: result }
  end
end
```

### Step 4: Update Background Jobs

Background jobs should already be using `establish_connection`, but verify:

#### ✅ Correct Pattern (Works in Both 0.8 and 0.9)

```ruby
class AnalysisJob < ApplicationJob
  def perform(project_path, query)
    RubyLLM::MCP.establish_connection do |clients|
      clients.each { |client| client.roots.add(project_path) }

      chat = RubyLLM.chat(model: "gpt-4")
      chat.with_tools(*clients.tools)

      result = chat.ask(query)

      AnalysisResult.create!(
        project_path: project_path,
        result: result
      )
    end
  end
end
```

This pattern works correctly in both versions and is the recommended approach.

## Updated Configuration Example

Here's a complete example of the updated initializer for version 0.9:

```ruby
# config/initializers/ruby_llm_mcp.rb

RubyLLM::MCP.configure do |config|
  # Global configuration
  config.log_level = Rails.env.production? ? Logger::WARN : Logger::INFO
  config.logger = Rails.logger

  # Path to your MCP servers configuration
  config.config_path = Rails.root.join("config", "mcps.yml")

  # Configure roots for filesystem access (development only)
  config.roots = [Rails.root] if Rails.env.development?

  # Configure sampling (optional)
  config.sampling.enabled = false
  config.sampling.preferred_model = "gpt-4" if config.sampling.enabled
end

# ❌ DO NOT include launch_control - it has been removed
# ❌ DO NOT include start_all_clients - it has been removed
```

## Common Migration Scenarios

### Scenario 1: Simple Controller Action

**Before (0.8.x):**

```ruby
def analyze
  clients = RubyLLM::MCP.clients
  chat = RubyLLM.chat(model: "gpt-4").with_tools(*clients.tools)
  result = chat.ask(params[:query])
  render json: result
end
```

**After (0.9.x):**

```ruby
def analyze
  result = RubyLLM::MCP.establish_connection do |clients|
    chat = RubyLLM.chat(model: "gpt-4").with_tools(*clients.tools)
    chat.ask(params[:query])
  end
  render json: result
end
```

### Scenario 2: Streaming Response

**Before (0.8.x):**

```ruby
def stream
  response.headers['Content-Type'] = 'text/event-stream'

  clients = RubyLLM::MCP.clients
  chat = RubyLLM.chat(model: "gpt-4").with_tools(*clients.tools)

  chat.ask(params[:query]) do |chunk|
    response.stream.write("data: #{chunk.content}\n\n")
  end
ensure
  response.stream.close
end
```

**After (0.9.x):**

```ruby
def stream
  response.headers['Content-Type'] = 'text/event-stream'

  RubyLLM::MCP.establish_connection do |clients|
    chat = RubyLLM.chat(model: "gpt-4").with_tools(*clients.tools)

    chat.ask(params[:query]) do |chunk|
      response.stream.write("data: #{chunk.content}\n\n")
    end
  end
ensure
  response.stream.close
end
```

### Scenario 3: Service Object Pattern

**Before (0.8.x):**

```ruby
class McpAnalysisService
  def initialize(query)
    @query = query
    @clients = RubyLLM::MCP.clients
  end

  def call
    chat = RubyLLM.chat(model: "gpt-4")
    chat.with_tools(*@clients.tools)
    chat.ask(@query)
  end
end

# Usage
McpAnalysisService.new(query).call
```

**After (0.9.x):**

```ruby
class McpAnalysisService
  def initialize(query)
    @query = query
  end

  def call
    RubyLLM::MCP.establish_connection do |clients|
      chat = RubyLLM.chat(model: "gpt-4")
      chat.with_tools(*clients.tools)
      chat.ask(@query)
    end
  end
end

# Usage (unchanged)
McpAnalysisService.new(query).call
```

## Benefits of the New Pattern

The removal of automatic launch control and mandatory use of `establish_connection` provides several benefits:

### 1. **Explicit Resource Management**

```ruby
# Clear start and end of MCP client lifecycle
RubyLLM::MCP.establish_connection do |clients|
  # Clients are created here
  # ... use clients ...
end # Clients are automatically stopped and cleaned up here
```

### 2. **Better Error Handling**

```ruby
begin
  RubyLLM::MCP.establish_connection do |clients|
    # MCP operations
  end
rescue RubyLLM::MCP::Error => e
  # Handle MCP-specific errors
  Rails.logger.error("MCP error: #{e.message}")
rescue => e
  # Handle other errors
  Rails.logger.error("Unexpected error: #{e.message}")
end
```

### 3. **No Memory Leaks in Development**

Connection blocks ensure clients are properly stopped, even with Rails code reloading.

### 4. **Thread-Safe**

Each request/job gets its own isolated client instances.

### 5. **Works Perfectly with Background Jobs**

The pattern naturally extends to background job processing:

```ruby
class ProcessDocumentJob < ApplicationJob
  def perform(document_id)
    document = Document.find(document_id)

    RubyLLM::MCP.establish_connection do |clients|
      # Each job has isolated clients
      # No interference between concurrent jobs
      analyze_document(clients, document)
    end
  end
end
```

## Multi-User OAuth Applications

{: .label .label-green }
0.8+

For multi-user applications where each user needs their own MCP connection, use the new OAuth integration:

```bash
# Generate OAuth support
rails generate ruby_llm:mcp:oauth:install
```

This provides per-user OAuth tokens and automatic client management:

```ruby
class AiResearchJob < ApplicationJob
  def perform(user_id, query)
    user = User.find(user_id)

    # Each user gets their own OAuth-authenticated client
    client = user.mcp_client  # Uses user's OAuth token

    tools = client.tools
    chat = RubyLLM.chat(provider: "anthropic/claude-sonnet-4")
      .with_tools(*tools)

    response = chat.ask(query)
  end
end
```

See **[Rails OAuth Integration Guide]({% link guides/rails-oauth.md %})** for complete details.

## Testing Your Migration

### 1. Update Tests

Replace any test setup that used automatic clients:

**Before:**

```ruby
# spec/rails_helper.rb or test/test_helper.rb
RSpec.configure do |config|
  config.before(:suite) do
    RubyLLM::MCP.start_all_clients
  end

  config.after(:suite) do
    RubyLLM::MCP.stop_all_clients
  end
end
```

**After:**

```ruby
# No global setup needed!
# Tests use establish_connection blocks naturally:

RSpec.describe AnalysisController do
  it "analyzes with MCP tools" do
    # Mock or use VCR for actual MCP calls
    post :create, params: { query: "test" }
    expect(response).to be_successful
  end
end
```

### 2. Verify Background Jobs

Run your test suite, especially background job tests:

```bash
bundle exec rspec spec/jobs/
# or
bundle exec rails test test/jobs/
```

### 3. Test in Development

Start your development server and verify MCP operations work:

```bash
rails server
```

## Troubleshooting

### Error: `undefined method 'launch_control=' for RubyLLM::MCP:Module`

**Cause:** You're still trying to set `launch_control` in your initializer.

**Solution:** Remove all `launch_control` references from `config/initializers/ruby_llm_mcp.rb`.

### Error: `undefined method 'start_all_clients' for RubyLLM::MCP:Module`

**Cause:** You're still trying to call `start_all_clients`.

**Solution:** Remove `start_all_clients` calls. Use `establish_connection` instead.

### Error: `undefined method 'clients' for RubyLLM::MCP:Module`

**Cause:** You're trying to access `RubyLLM::MCP.clients` directly.

**Solution:** Wrap your code in an `establish_connection` block:

```ruby
RubyLLM::MCP.establish_connection do |clients|
  # Use clients here
end
```

### MCP Operations Work in Console but Not in Controllers

**Cause:** You might be accessing clients without `establish_connection`.

**Solution:** Ensure all MCP access is within connection blocks:

```ruby
def action
  RubyLLM::MCP.establish_connection do |clients|
    # All MCP operations here
  end
end
```

## Getting Help

If you encounter issues during the upgrade:

1. **Check the pattern**: Ensure you're using `establish_connection` blocks
2. **Review examples**: See [Rails Integration Guide]({% link guides/rails-integration.md %})
3. **Check GitHub Issues**: [RubyLLM MCP Issues](https://github.com/patvice/ruby_llm-mcp/issues)
4. **File a bug**: If you find migration issues, please report them

## What's New in 0.9

While migrating, take advantage of new features in version 0.9:

### OAuth 2.1 Support

{: .label .label-green }
New in 0.9

Complete OAuth 2.1 implementation with:
- PKCE (RFC 7636)
- Dynamic Client Registration (RFC 7591)
- Browser-based authentication
- Per-user token storage
- Automatic token refresh

See **[OAuth Guide]({% link guides/oauth.md %})** and **[Rails OAuth Integration]({% link guides/rails-oauth.md %})**.

### Rails OAuth Generator

{: .label .label-green }
New in 0.9

Generate complete OAuth setup for Rails:

```bash
rails generate ruby_llm:mcp:oauth:install
```

Creates models, migrations, controllers, and views for multi-user OAuth.

## Next Steps

After upgrading:

1. **Test thoroughly** in development and staging
2. **Review [Rails Integration Guide]({% link guides/rails-integration.md %})** for current best practices
3. **Consider OAuth** for multi-user applications: [Rails OAuth Integration]({% link guides/rails-oauth.md %})
4. **Update your team** on the new connection block pattern
5. **Monitor production** after deployment

---

**Questions?** [Open an issue](https://github.com/patvice/ruby_llm-mcp/issues) or check the [documentation]({% link index.md %}).
