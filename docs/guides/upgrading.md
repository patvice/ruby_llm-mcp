---
layout: default
title: Upgrading
parent: Advanced
nav_order: 3
description: "Unified upgrade guide with version-specific migration sections"
---

# Upgrading
{: .no_toc }

This page consolidates upgrade guidance across supported RubyLLM MCP version jumps.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Update to 1.0

{: .label .label-green }
✓ No Breaking Changes

Version 1.0 is a stable release with no breaking changes from 0.8.x.

### Steps

1. Update your Gemfile:

```ruby
gem 'ruby_llm-mcp', '~> 1.0'
```

Optional for MCP SDK adapter (Ruby 3.1+):

```ruby
gem 'mcp', '~> 0.7'
```

2. Run:

```bash
bundle update ruby_llm-mcp
```

3. Keep using your existing 0.8 code unchanged.

### Notable 1.0 Additions

- Stable adapter system (`:ruby_llm` and `:mcp_sdk`)
- Expanded adapter/transport documentation
- Clear custom transport namespace docs

If you use custom transports:

```ruby
RubyLLM::MCP::Native::Transport.register_transport(:custom, CustomTransport)
```

---

## Update to 0.8

{: .label .label-red }
Breaking Change

This section covers the migration from 0.7.x-style usage to 0.8-era connection management patterns.

### What Changed

Automatic Rails launch control was removed in favor of explicit connection blocks.

Removed pattern:

```ruby
RubyLLM::MCP.launch_control = :automatic
RubyLLM::MCP.start_all_clients
clients = RubyLLM::MCP.clients
```

Use this instead:

```ruby
result = RubyLLM::MCP.establish_connection do |clients|
  chat = RubyLLM.chat(model: "gpt-4")
  chat.with_tools(*clients.tools)
  chat.ask(params[:query])
end
```

### Why

- Better Rails lifecycle behavior
- More predictable process/resource management
- Better fit for background-job-first production usage
- Cleaner behavior in multi-user/OAuth application flows

### Migration Checklist

1. Remove `launch_control` and `start_all_clients` config.
2. Replace direct `RubyLLM::MCP.clients` access with `establish_connection` blocks.
3. Verify background jobs still use explicit connection blocks.

---

## Update to 0.7

This section covers upgrading from 0.6.x to 0.7.x.

### RubyLLM Dependency Requirement

Version 0.7 requires RubyLLM 1.9+

```ruby
gem 'ruby_llm', '~> 1.9'
gem 'ruby_llm-mcp', '~> 0.7'
```

Then run:

```bash
bundle update ruby_llm ruby_llm-mcp
```

### Complex Parameters Change

`support_complex_parameters!` became unnecessary because complex parameters are supported by default in 0.7.

Deprecated old pattern:

```ruby
RubyLLM::MCP.configure do |config|
  config.support_complex_parameters!
end
```

---

## Need Older Detail?

Legacy per-version guides still exist in the repository and can be referenced if needed:

- `docs/guides/upgrading-0.8-to-1.0.md`
- `docs/guides/upgrading-0.7-to-0.8.md`
- `docs/guides/upgrading-0.6-to-0.7.md`

## Next Steps

- **[Adapters & Transports]({% link guides/adapters.md %})** - Adapter behavior and compatibility
- **[Rails Integration]({% link guides/rails-integration.md %})** - Current Rails patterns
- **[Configuration]({% link configuration.md %})** - Global/per-client configuration reference
