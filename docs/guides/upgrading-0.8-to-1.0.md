---
layout: default
title: Upgrading from 0.8 to 1.0
parent: Guides
nav_order: 12
description: "Quick guide for upgrading from RubyLLM MCP 0.8 to 1.0"
---

# Upgrading from 0.8 to 1.0
{: .no_toc }

Version 1.0 is a stable release with **no breaking changes**. Upgrade by updating your Gemfile.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Breaking Changes

{: .label .label-green }
✓ No Breaking Changes

Version 1.0 maintains full backward compatibility with 0.8.x. All existing code continues to work without modifications.

## Upgrade Steps

### 1. Update Gemfile

```ruby
gem 'ruby_llm-mcp', '~> 1.0'
```

Optional - for MCP SDK adapter (requires Ruby 3.2+):

```ruby
gem 'mcp', '~> 0.4'
```

Then run:

```bash
bundle update ruby_llm-mcp
```

### 2. Done!

Your existing 0.8 code will work without changes.

## What's New in 1.0

- **Stable adapter system** - Production-ready RubyLLM and MCP SDK adapters
- **Enhanced documentation** - Merged and improved guides
- **Custom transport clarity** - Proper namespace documentation for `RubyLLM::MCP::Native::Transport.register_transport`

## Optional: Custom Transport Registration

If you're using custom transports, ensure you use the correct namespace:

```ruby
# Correct registration (was unclear in 0.8 docs)
RubyLLM::MCP::Native::Transport.register_transport(:custom, CustomTransport)
```

## Resources

- **[Adapters & Transports]({% link guides/adapters.md %})** - Comprehensive guide
- **[OAuth 2.1 Support]({% link guides/oauth.md %})** - Production-ready OAuth
- **[Getting Started]({% link guides/getting-started.md %})** - Quick start guide

---

**Congratulations on upgrading to 1.0!** 🎉

**Questions?** [Open an issue](https://github.com/patvice/ruby_llm-mcp/issues) or check the [documentation]({% link index.md %}).
