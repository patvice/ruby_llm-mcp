---
layout: default
title: Elicitation
parent: Client
nav_order: 9
description: "MCP elicitation - allow servers to request additional structured information from users"
---

# Elicitation
{: .no_toc }

Elicitation allows MCP servers to request additional structured information from users during interactions. This enables dynamic workflows where servers can ask for clarification, gather additional context, or collect user preferences in real-time.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

When elicitation is enabled, MCP servers can send "elicitation" requests to your client, which will:

1. Present the server's request message to the user
2. Collect structured user input based on a JSON schema
3. Validate the response against the schema
4. Return the structured data back to the server

This is useful for servers that need user input or clarification during complex workflows.

{: .new }
Elicitation was introduced in MCP Protocol 2025-06-18.

**Note:** Elicitation is available for clients using protocol version `2025-06-18` or newer.

## Basic Elicitation Configuration

### Global Configuration

Configure elicitation handling globally for all clients:

```ruby
RubyLLM::MCP.configure do |config|
  config.on_elicitation do |elicitation|
    # Handle elicitation requests from MCP servers
    puts "Server requests: #{elicitation.message}"

    # Example: Always accept with a default response
    elicitation.structured_response = { "status": "accepted" }
    true
  end
end
```

### Per-Client Configuration

Configure elicitation handling for specific clients:

```ruby
client = RubyLLM::MCP.client(
  name: "interactive-server",
  transport_type: :streamable,
  config: { url: "https://server.com/mcp" }
)

client.on_elicitation do |elicitation|
  # Handle server's elicitation request
  puts "Server message: #{elicitation.message}"

  # The requested schema defines the expected response format
  schema = elicitation.requested_schema

  # Provide structured response matching the schema
  response_data = collect_user_input(schema)
  elicitation.structured_response = response_data

  # Return true to accept, false to reject
  true
end
```

---

## Elicitation Object

The elicitation object provides access to the server's request and allows you to set the response:

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `message` | String | Human-readable message from the server |
| `requested_schema` | Hash | JSON schema defining the expected response format |
| `structured_response` | Hash | Your structured response (set this) |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `validate_response` | Boolean | Validates the structured response against the schema |

### Example Usage

```ruby
client.on_elicitation do |elicitation|
  puts "Server says: #{elicitation.message}"

  # Examine the requested schema
  schema = elicitation.requested_schema
  puts "Expected format: #{schema}"

  # Create a response that matches the schema
  response = {
    "user_choice": "option_a",
    "confidence": 0.8,
    "reasoning": "This option seems most appropriate"
  }

  # Set the response
  elicitation.structured_response = response

  # Validation happens automatically, but you can check manually
  if elicitation.validate_response
    puts "Response is valid"
    true  # Accept the elicitation
  else
    puts "Response is invalid"
    false  # Reject the elicitation
  end
end
```

---

## Handler Classes

{: .label .label-green }
1.0+

Handler classes provide a powerful way to handle elicitation requests with better organization and async support.

### Basic Handler Class

```ruby
class MyElicitationHandler < RubyLLM::MCP::Handlers::ElicitationHandler
  def execute
    # Access elicitation details
    message = elicitation.message
    schema = elicitation.requested_schema

    # Generate response based on schema
    response = generate_response(schema)

    accept(response)
  end

  private

  def generate_response(schema)
    # Your logic to create structured response
    properties = schema.dig("properties") || {}
    properties.each_with_object({}) do |(key, spec), response|
      response[key] = default_value_for(spec)
    end
  end

  def default_value_for(spec)
    case spec["type"]
    when "string" then spec["default"] || ""
    when "number" then spec["default"] || 0
    when "boolean" then spec["default"] || false
    else nil
    end
  end
end

# Register handler classes per-client
client.on_elicitation(MyElicitationHandler)
```

Global elicitation hooks (`config.on_elicitation`) remain available for block-based callbacks.

### Handler with Options

```ruby
class ConfigurableElicitationHandler < RubyLLM::MCP::Handlers::ElicitationHandler
  option :auto_approve_simple, default: false
  option :ui_adapter, required: true

  def execute
    if options[:auto_approve_simple] && simple_schema?
      auto_approve
    else
      prompt_user
    end
  end

  private

  def simple_schema?
    properties = elicitation.requested_schema.dig("properties") || {}
    properties.keys.length <= 2
  end

  def auto_approve
    response = generate_default_response
    accept(response)
  end

  def prompt_user
    response = options[:ui_adapter].prompt_user(
      message: elicitation.message,
      schema: elicitation.requested_schema
    )

    response ? accept(response) : reject("User declined")
  end
end

# Use with options
client.on_elicitation(
  ConfigurableElicitationHandler,
  auto_approve_simple: true,
  ui_adapter: MyUIAdapter.new
)
```

---

## Async Elicitation

{: .new }
For real-world applications, you often need to ask users for input via websockets, push notifications, or other async mechanisms. The handler system fully supports async patterns.

### Why Async?

- **Websocket Integration**: Ask users via real-time connections
- **Push Notifications**: Request input on mobile devices
- **Long-Running Operations**: Don't block while waiting for user
- **Scalability**: Handle many concurrent elicitations

### Async Pattern 1: Registry Pattern

Perfect for websocket or Action Cable integration:

```ruby
class WebsocketElicitationHandler < RubyLLM::MCP::Handlers::ElicitationHandler
  async_execution timeout: 300 # 5 minutes

  option :user_id, required: true
  option :websocket_service, required: true

  def execute
    # Send to user's websocket
    options[:websocket_service].broadcast(
      "user_#{options[:user_id]}_elicitations",
      {
        type: "elicitation_request",
        id: elicitation.id,
        message: elicitation.message,
        schema: elicitation.requested_schema
      }
    )

    # Return :pending - completion happens later
    :pending
  end
end

# Configure handler
client.on_elicitation(
  WebsocketElicitationHandler,
  user_id: current_user.id,
  websocket_service: ActionCable.server
)

# When user responds via websocket:
class ElicitationChannel < ApplicationCable::Channel
  def respond(data)
    RubyLLM::MCP::Handlers::ElicitationRegistry.complete(
      data["elicitation_id"],
      response: data["response"]
    )
  end

  def cancel(data)
    RubyLLM::MCP::Handlers::ElicitationRegistry.cancel(
      data["elicitation_id"],
      reason: "User cancelled"
    )
  end
end
```

### Async Pattern 2: Promise Pattern

For more control over async operations:

```ruby
class PromiseElicitationHandler < RubyLLM::MCP::Handlers::ElicitationHandler
  async_execution timeout: 180

  option :notification_service, required: true

  def execute
    # Create a promise
    promise = create_promise

    # Send notification with callbacks
    options[:notification_service].send_notification(
      elicitation_id: elicitation.id,
      message: elicitation.message,
      schema: elicitation.requested_schema,
      on_response: ->(data) { promise.resolve(data) },
      on_cancel: ->(reason) { promise.reject(reason) }
    )

    # Return promise - framework waits for resolution
    promise
  end
end
```

### Action Cable Integration Example

Complete example with Action Cable:

```ruby
# app/handlers/action_cable_elicitation_handler.rb
class ActionCableElicitationHandler < RubyLLM::MCP::Handlers::ElicitationHandler
  async_execution timeout: 300

  option :user_id, required: true

  def execute
    # Broadcast to user's channel
    ActionCable.server.broadcast(
      "elicitation_#{options[:user_id]}",
      {
        type: "new_elicitation",
        id: elicitation.id,
        message: elicitation.message,
        schema: elicitation.requested_schema,
        expires_at: 5.minutes.from_now
      }
    )

    :pending
  end
end

# app/channels/elicitation_channel.rb
class ElicitationChannel < ApplicationCable::Channel
  def subscribed
    stream_from "elicitation_#{current_user.id}"
  end

  def respond_to_elicitation(data)
    RubyLLM::MCP::Handlers::ElicitationRegistry.complete(
      data["elicitation_id"],
      response: data["response"]
    )

    transmit success: true
  end

  def cancel_elicitation(data)
    RubyLLM::MCP::Handlers::ElicitationRegistry.cancel(
      data["elicitation_id"],
      reason: data["reason"] || "User cancelled"
    )

    transmit cancelled: true
  end
end

# Configure in your MCP client
client = RubyLLM::MCP.client(
  name: "interactive-server",
  transport_type: :streamable,
  config: { url: "https://server.com/mcp" }
)

client.on_elicitation(
  ActionCableElicitationHandler,
  user_id: current_user.id
)
```

### Frontend JavaScript Example

```javascript
// React component
import { useState, useEffect } from 'react';
import { consumer } from './consumer'; // Action Cable consumer

function ElicitationModal() {
  const [elicitation, setElicitation] = useState(null);

  useEffect(() => {
    const subscription = consumer.subscriptions.create('ElicitationChannel', {
      received(data) {
        if (data.type === 'new_elicitation') {
          setElicitation(data);
        }
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  const handleSubmit = (response) => {
    subscription.perform('respond_to_elicitation', {
      elicitation_id: elicitation.id,
      response: response
    });
    setElicitation(null);
  };

  const handleCancel = () => {
    subscription.perform('cancel_elicitation', {
      elicitation_id: elicitation.id,
      reason: 'User cancelled'
    });
    setElicitation(null);
  };

  if (!elicitation) return null;

  return (
    <div className="modal">
      <h2>{elicitation.message}</h2>
      <form onSubmit={e => {
        e.preventDefault();
        const formData = new FormData(e.target);
        const response = Object.fromEntries(formData);
        handleSubmit(response);
      }}>
        {/* Render form based on elicitation.schema */}
        <button type="submit">Submit</button>
        <button type="button" onClick={handleCancel}>Cancel</button>
      </form>
    </div>
  );
}
```

### Backward Compatibility

Handler classes are fully backward compatible:

```ruby
# Old way (still works, but synchronous only)
client.on_elicitation do |elicitation|
  elicitation.structured_response = { "confirmed" => true }
  true
end

# New way (async support)
client.on_elicitation(WebsocketElicitationHandler, user_id: current_user.id)
```

---

## Response Actions

Elicitation handlers can return synchronous or async outcomes:

### Handler class return contract

```ruby
accept({ "confirmed" => true })  # => { action: :accept, response: {...} }
reject("User declined")          # => { action: :reject, reason: "User declined" }
cancel("Cancelled by user")      # => { action: :cancel, reason: "Cancelled by user" }

# Async options:
:pending                         # Store in registry for later completion
create_promise                   # Resolve/reject later
defer                            # Return AsyncResponse
```

Use `RubyLLM::MCP::Handlers::ElicitationRegistry.complete` or `.cancel` to finish deferred requests.

### Accept (true)

Accept the elicitation and provide the structured response:

```ruby
client.on_elicitation do |elicitation|
  elicitation.structured_response = { "decision": "approved" }
  true  # Accept
end
```

### Reject (false)

Reject the elicitation request:

```ruby
client.on_elicitation do |elicitation|
  false  # Reject - don't want to provide this information
end
```

### Cancel (validation failure)

If your response doesn't match the schema, the client automatically cancels:

```ruby
client.on_elicitation do |elicitation|
  # This will fail validation and trigger a cancel
  elicitation.structured_response = { "invalid": "format" }
  true  # You accept, but validation fails
end
```

---

## Schema Examples

### Simple User Preference

```json
{
  "type": "object",
  "properties": {
    "preference": {
      "type": "string",
      "enum": ["option_a", "option_b", "option_c"]
    },
    "confidence": {
      "type": "number",
      "minimum": 0,
      "maximum": 1
    }
  },
  "required": ["preference"]
}
```

Corresponding response:

```ruby
elicitation.structured_response = {
  "preference": "option_a",
  "confidence": 0.9
}
```

### Complex Configuration

```json
{
  "type": "object",
  "properties": {
    "settings": {
      "type": "object",
      "properties": {
        "theme": {"type": "string"},
        "notifications": {"type": "boolean"},
        "advanced": {
          "type": "array",
          "items": {"type": "string"}
        }
      }
    },
    "user_info": {
      "type": "object",
      "properties": {
        "name": {"type": "string"},
        "department": {"type": "string"}
      },
      "required": ["name"]
    }
  },
  "required": ["user_info"]
}
```

Corresponding response:

```ruby
elicitation.structured_response = {
  "settings": {
    "theme": "dark",
    "notifications": true,
    "advanced": ["experimental_features", "debug_mode"]
  },
  "user_info": {
    "name": "Alice Smith",
    "department": "Engineering"
  }
}
```

---

## Error Handling

### Schema Validation Errors

```ruby
client.on_elicitation do |elicitation|
  begin
    response = build_response(elicitation.requested_schema)
    elicitation.structured_response = response

    unless elicitation.validate_response
      puts "Response validation failed"
      return false
    end

    true
  rescue StandardError => e
    puts "Error processing elicitation: #{e.message}"
    false
  end
end
```

### Timeout Handling

```ruby
client.on_elicitation do |elicitation|
  Timeout.timeout(30) do  # 30 second timeout
    response = collect_user_input(elicitation.requested_schema)
    elicitation.structured_response = response
    true
  end
rescue Timeout::Error
  puts "Elicitation timed out"
  false
end
```

---

## Best Practices

### Security Considerations

- **Validate all user input** before setting structured responses
- **Sanitize data** to prevent injection attacks
- **Limit response size** to prevent memory issues
- **Implement timeouts** for user input collection

### User Experience

- **Provide clear prompts** based on the server's message
- **Show schema information** to help users understand what's expected
- **Implement input validation** with helpful error messages
- **Support cancellation** for long-running input collection

### Error Recovery

- **Handle schema validation failures** gracefully
- **Provide fallback responses** for critical workflows
- **Log elicitation requests** for debugging
- **Implement retry logic** for temporary failures

### Performance

- **Cache frequent responses** for common schemas
- **Implement async processing** for complex input collection
- **Set reasonable timeouts** for user interactions
- **Monitor elicitation frequency** to detect issues

## Next Steps

Once you understand client interactions, explore:

- **[Server Interactions]({% link server/index.md %})** - Working with server capabilities
- **[Configuration]({% link configuration.md %})** - Advanced client configuration options
- **[Rails Integration]({% link guides/rails-integration.md %})** - Using MCP with Rails applications
