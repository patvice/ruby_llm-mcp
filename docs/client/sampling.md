---
layout: default
title: Sampling
parent: Client
nav_order: 7
description: "MCP sampling - allow servers to use your LLM for their own requests"
---

# Sampling
{: .no_toc }

MCP sampling allows servers to offload LLM requests to your client rather than making them directly. This enables servers to use your LLM connections and configurations while maintaining their own logic and workflows.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

When sampling is enabled, MCP servers can send "sample" requests to your client, which will:

1. Execute the LLM request using your configured model
2. Return the response back to the server
3. Allow the server to continue its processing

This is useful for servers that need LLM capabilities but don't want to manage API keys or model connections directly.

## Basic Sampling Configuration

### Enable Sampling

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4"
end

# Create client with sampling enabled
client = RubyLLM::MCP.client(
  name: "sampling-server",
  transport_type: :stdio,
  config: {
    command: "bunx",
    args: ["@example/mcp-server-with-sampling"]
  }
)
```

### Basic Usage

```ruby
# The server can now make sampling requests
# These will be automatically handled by your client
tool = client.tool("analyze_data")
result = tool.execute(data: "some data to analyze")

# Behind the scenes, the server may have made LLM requests
# using your configured model and API credentials
puts result
```

## Model Selection

### Static Model Selection

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4"
end

# All sampling requests will use GPT-4
```

### Dynamic Model Selection

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true

  # Use a block for dynamic model selection
  config.sampling.preferred_model do |model_preferences|
    # The server can send model preferences/hints
    server_preference = model_preferences.hints.first

    # You can use server preferences or override them
    case server_preference
    when "fast"
      "gpt-3.5-turbo"
    when "smart"
      "gpt-4"
    when "coding"
      "gpt-4"
    else
      "gpt-4" # Default fallback
    end
  end
end
```

### Model Selection Based on Request

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true

  config.sampling.preferred_model do |model_preferences|
    # Access the full sampling request context
    messages = model_preferences.messages

    # Choose model based on message content
    if messages.any? { |msg| msg.content.include?("code") }
      "gpt-4" # Use GPT-4 for code-related tasks
    elsif messages.length > 10
      "gpt-3.5-turbo" # Use faster model for long conversations
    else
      "gpt-4" # Default for other cases
    end
  end
end
```

## Guards and Filtering

### Basic Guards

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4"

  # Only allow samples that contain "Hello"
  config.sampling.guard do |sample|
    sample.messages.any? { |msg| msg.content.include?("Hello") }
  end
end
```

### Content-Based Guards

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4"

  # Filter based on message content
  config.sampling.guard do |sample|
    messages = sample.messages

    # Don't allow requests containing sensitive keywords
    sensitive_keywords = ["password", "secret", "private_key"]

    messages.none? do |message|
      sensitive_keywords.any? { |keyword| message.content.include?(keyword) }
    end
  end
end
```

### Rate Limiting Guards

```ruby
class SamplingRateLimiter
  def initialize(max_requests: 100, window: 3600)
    @max_requests = max_requests
    @window = window
    @requests = []
  end

  def allow_request?
    now = Time.now

    # Remove old requests outside the window
    @requests.reject! { |timestamp| now - timestamp > @window }

    # Check if we're under the limit
    if @requests.length < @max_requests
      @requests << now
      true
    else
      false
    end
  end
end

rate_limiter = SamplingRateLimiter.new(max_requests: 50, window: 3600)

RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4"

  config.sampling.guard do |sample|
    rate_limiter.allow_request?
  end
end
```

### User-Based Guards

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4"

  config.sampling.guard do |sample|
    # Check if user is authorized (if server provides user context)
    user_id = sample.metadata&.dig("user_id")

    if user_id
      # Check user permissions
      authorized_users = ["user1", "user2", "admin"]
      authorized_users.include?(user_id)
    else
      # Allow anonymous requests
      true
    end
  end
end
```

## Next Steps

- **[Roots]({% link client/roots.md %})** - Provide filesystem access to servers
- **[Rails Integration]({% link guides/rails-integration.md %})** - Complete Rails integration guide
