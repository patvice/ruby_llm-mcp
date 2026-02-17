---
layout: default
title: Upgrading from 0.6 to 0.7
parent: Advanced
nav_order: 10
description: "Guide for upgrading from RubyLLM MCP 0.6 to 0.7"
nav_exclude: true
---

# Upgrading from 0.6 to 0.7
{: .no_toc }

This guide covers the changes and migration steps when upgrading from RubyLLM MCP version 0.6.x to 0.7.x.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Breaking Changes

### RubyLLM 1.9 Requirement

Version 0.7 requires RubyLLM 1.9 or higher. Make sure to update your `ruby_llm` dependency:

```ruby
# Gemfile
gem 'ruby_llm', '~> 1.9'
gem 'ruby_llm-mcp', '~> 0.7'
```

Then run:

```bash
bundle update ruby_llm ruby_llm-mcp
```

## Deprecated Features

### Complex Parameters Support (Now Default)

{: .warning }
The `support_complex_parameters!` method is deprecated and will be removed in version 0.8.0.

**What Changed:**

In version 0.6.x and earlier, you had to explicitly enable complex parameter support for MCP tools to handle arrays and nested objects:

```ruby
# Version 0.6.x (OLD - deprecated)
RubyLLM::MCP.configure do |config|
  config.support_complex_parameters!
end
```

**In version 0.7.x, complex parameters are supported by default.** You no longer need to call this method.

## Getting Help

If you encounter issues during the upgrade:

1. Check the [GitHub Issues](https://github.com/patvice/ruby_llm-mcp/issues) for similar problems
2. Review the [Configuration Guide]({% link configuration.md %}) for updated examples
3. Open a new issue with details about your setup and the error message

## Next Steps

After upgrading:

- Review the [Configuration Guide]({% link configuration.md %}) for new features
- Check out [Tools Documentation]({% link server/tools.md %}) for updated examples
- Explore any new features in the [Release Notes](https://github.com/patvice/ruby_llm-mcp/releases)
