---
layout: default
title: Elicitation
parent: Client Interactions
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
Elicitation is a new feature in MCP Protocol 2025-06-18.

## Basic Elicitation Configuration

### Global Configuration

Configure elicitation handling globally for all clients:

```ruby
RubyLLM::MCP.configure do |config|
  config.elicitation = lambda do |elicitation|
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

## Response Actions

Your elicitation handler should return one of these values to indicate the action:

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

## Advanced Patterns

### Interactive User Input

```ruby
client.on_elicitation do |elicitation|
  puts "\n#{elicitation.message}"

  schema = elicitation.requested_schema
  response = {}

  # Collect input based on schema properties
  schema["properties"].each do |key, property|
    print "#{key.capitalize}: "
    value = gets.chomp

    # Convert based on type
    case property["type"]
    when "number"
      response[key] = value.to_f
    when "boolean"
      response[key] = ["true", "yes", "y"].include?(value.downcase)
    else
      response[key] = value
    end
  end

  elicitation.structured_response = response
  true
end
```

### Conditional Logic

```ruby
client.on_elicitation do |elicitation|
  case elicitation.message
  when /approval required/i
    # Handle approval requests
    elicitation.structured_response = { "approved": confirm_approval() }
    true
  when /preference/i
    # Handle preference requests
    elicitation.structured_response = { "choice": get_user_preference() }
    true
  else
    # Reject unknown requests
    false
  end
end
```

### Async Processing

```ruby
client.on_elicitation do |elicitation|
  # For complex processing, you might want to handle this asynchronously
  Thread.new do
    response = complex_processing(elicitation.message, elicitation.requested_schema)
    elicitation.structured_response = response
  end

  true  # Accept the elicitation
end
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

## Testing Elicitation

### Mock Elicitation Requests

```ruby
# In your tests
RSpec.describe "Elicitation handling" do
  it "handles user preferences" do
    client = create_test_client

    # Mock elicitation response
    client.on_elicitation do |elicitation|
      expect(elicitation.message).to include("preference")
      elicitation.structured_response = { "choice": "test_option" }
      true
    end

    # Trigger elicitation through server interaction
    result = client.tool("preference_tool").execute
    expect(result).to be_successful
  end
end
```

### Integration Tests

```ruby
# Test with real server that sends elicitation requests
def test_elicitation_workflow
  client = RubyLLM::MCP.client(
    name: "test-server",
    transport_type: :stdio,
    config: { command: "test-mcp-server" }
  )

  responses = []
  client.on_elicitation do |elicitation|
    responses << elicitation.message
    elicitation.structured_response = { "test": "response" }
    true
  end

  # Execute operation that triggers elicitation
  client.tool("interactive_tool").execute

  expect(responses).not_to be_empty
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
