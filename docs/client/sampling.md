---
layout: default
title: Sampling
parent: Client Interactions
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

## Handler Classes

{: .label .label-green }
1.0+

Handler classes provide a powerful, object-oriented way to handle sampling requests with better testability and reusability.

### Why Use Handler Classes?

- **Reusable**: Define once, use across multiple clients
- **Testable**: Easy to unit test without full MCP setup
- **Composable**: Use hooks, guards, and options for complex logic
- **Maintainable**: Clearer separation of concerns

### Basic Handler Class

```ruby
class MySamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
  def execute
    model = sample.model_preferences.model || "gpt-4"
    response = default_chat_completion(model)
    accept(response)
  end
end

# Sampling handlers are configured per-client
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
end

client.on_sampling(MySamplingHandler)
```

### Handler with Guards

```ruby
class SecureSamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
  guard :check_message_length
  guard :check_content_safety

  def execute
    model = sample.model_preferences.model || "gpt-4"
    response = default_chat_completion(model)
    accept(response)
  end

  private

  def check_message_length
    return true if sample.message.length < 10_000
    "Message too long: #{sample.message.length} characters"
  end

  def check_content_safety
    return true unless sample.message.include?("jailbreak")
    "Unsafe content detected"
  end
end
```

### Handler with Options

```ruby
class ConfigurableSamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
  option :default_model, default: "gpt-4"
  option :max_tokens, default: 4000
  option :allowed_models, default: []

  guard :check_allowed_models

  def execute
    model = select_model
    response = default_chat_completion(model)
    accept(response)
  end

  private

  def select_model
    sample.model_preferences.model || options[:default_model]
  end

  def check_allowed_models
    return true if options[:allowed_models].empty?
    return true if options[:allowed_models].include?(select_model)

    "Model '#{select_model}' not allowed"
  end
end

# Use with custom options
client.on_sampling(
  ConfigurableSamplingHandler,
  default_model: "gpt-3.5-turbo",
  allowed_models: ["gpt-3.5-turbo", "gpt-4"]
)
```

### Handler with Hooks

```ruby
class LoggingSamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
  before_execute do
    logger.info("Sampling request from: #{sample.model_preferences.model}")
    @start_time = Time.now
  end

  after_execute do |result|
    duration = Time.now - @start_time
    logger.info("Sampling completed in #{duration}s")
    metrics.record("sampling.duration", duration)
  end

  def execute
    model = sample.model_preferences.model || "gpt-4"
    response = default_chat_completion(model)
    accept(response)
  end
end
```

### Reusable Default Handler

```ruby
class DefaultSamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
  option :default_model, default: "gpt-4"

  def execute
    response = default_chat_completion(options[:default_model])
    accept(response)
  end
end

client.on_sampling(DefaultSamplingHandler, default_model: "gpt-4o")
```

### Testing Handler Classes

```ruby
RSpec.describe MySamplingHandler do
  let(:sample) do
    double(
      RubyLLM::MCP::Sample,
      message: "Test message",
      model_preferences: double(model: "gpt-4"),
      system_prompt: "You are helpful",
      raw_messages: []
    )
  end

  let(:coordinator) { double("Coordinator") }
  let(:handler) { described_class.new(sample: sample, coordinator: coordinator) }

  it "accepts valid requests" do
    # Mock chat completion
    allow(handler).to receive(:default_chat_completion).and_return("Response")

    result = handler.call

    expect(result[:accepted]).to be true
    expect(result[:response]).to eq("Response")
  end
end
```

### Backward Compatibility

Handler classes are fully backward compatible with block-based callbacks:

```ruby
# Old way (still works)
client.on_sampling do |sample|
  sample.message.length < 10_000
end

# New way (preferred)
client.on_sampling(MySamplingHandler)
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
class RequestAwareSamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
  def execute
    model = choose_model(sample.message)
    response = default_chat_completion(model)
    accept(response)
  end

  private

  def choose_model(text)
    if text.include?("code")
      "gpt-4"
    elsif text.length > 2_000
      "gpt-3.5-turbo"
    else
      "gpt-4"
    end
  end
end

client.on_sampling(RequestAwareSamplingHandler)
```

## Guards and Filtering

### Basic Guards

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4"

  # Only allow samples that contain "Hello"
  config.sampling.guard do |sample|
    sample.message.include?("Hello")
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
    # Don't allow requests containing sensitive keywords
    sensitive_keywords = ["password", "secret", "private_key"]
    sensitive_keywords.none? { |keyword| sample.message.include?(keyword) }
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

### Context-Aware Guards with Handler Options

```ruby
class TenantSamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
  option :allowed_tenants, default: []
  option :tenant_id, required: true

  def execute
    return reject("Tenant not authorized") unless allowed_tenant?

    response = default_chat_completion("gpt-4")
    accept(response)
  end

  private

  def allowed_tenant?
    options[:allowed_tenants].include?(options[:tenant_id])
  end
end

client.on_sampling(
  TenantSamplingHandler,
  tenant_id: current_tenant.id,
  allowed_tenants: ["tenant_a", "tenant_b"]
)
```

## Next Steps

- **[Roots]({% link client/roots.md %})** - Provide filesystem access to servers
- **[Rails Integration]({% link guides/rails-integration.md %})** - Complete Rails integration guide
