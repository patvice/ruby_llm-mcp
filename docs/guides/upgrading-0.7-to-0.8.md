---
layout: default
title: Upgrading from 0.8 to 0.9
parent: Advanced
nav_order: 11
description: "Guide for upgrading from RubyLLM MCP 0.8 to 0.9 with breaking changes and migration steps"
nav_exclude: true
---

# Upgrading from 0.7 to 0.8
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
gem 'ruby_llm-mcp', '~> 0.8'
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

#### Before (Version 0.7.x)

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

#### After (Version 0.8.x)

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

#### ✅ Correct Pattern (Works in Both 0.7 and 0.8)

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

## Getting Help

If you encounter issues during the upgrade:

1. **Check the pattern**: Ensure you're using `establish_connection` blocks
2. **Review examples**: See [Rails Integration Guide]({% link guides/rails-integration.md %})
3. **Check GitHub Issues**: [RubyLLM MCP Issues](https://github.com/patvice/ruby_llm-mcp/issues)
4. **File a bug**: If you find migration issues, please report them

## Next Steps

After upgrading:

1. **Test thoroughly** in development and staging
2. **Review [Rails Integration Guide]({% link guides/rails-integration.md %})** for current best practices
3. **Consider OAuth** for multi-user applications: [Rails OAuth Integration]({% link guides/rails-oauth.md %})
4. **Update your team** on the new connection block pattern
5. **Monitor production** after deployment

---

**Questions?** [Open an issue](https://github.com/patvice/ruby_llm-mcp/issues) or check the [documentation]({% link index.md %}).
