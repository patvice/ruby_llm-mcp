---
layout: default
title: Prompts
parent: Server
nav_order: 3
description: "Working with MCP prompts - predefined prompts with arguments for consistent interactions"
---

# Prompts
{: .no_toc }

MCP prompts are predefined messages with arguments that can be used to create consistent interactions with LLMs. They provide a way to standardize common queries and ensure consistent formatting across your application.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Discovering Prompts

### Listing Available Prompts

```ruby
client = RubyLLM::MCP.client(
  name: "prompt-server",
  transport_type: :stdio,
  config: {
    command: "bunx",
    args: ["@modelcontextprotocol/server-prompts", "/path/to/prompts"]
  }
)

# Get all available prompts
prompts = client.prompts
puts "Available prompts:"
prompts.each do |prompt|
  puts "- #{prompt.name}: #{prompt.description}"

  # Show arguments
  prompt.arguments.each do |arg|
    required = arg.required ? " (required)" : ""
    puts "  - #{arg.name}: #{arg.description}#{required}"
  end
end
```

### Getting a Specific Prompt

```ruby
# Get a specific prompt by name
greeting_prompt = client.prompt("daily_greeting")
puts "Prompt: #{greeting_prompt.name}"
puts "Description: #{greeting_prompt.description}"

# Show prompt arguments
greeting_prompt.arguments.each do |arg|
  puts "Argument: #{arg.name}"
  puts "  Description: #{arg.description}"
  puts "  Required: #{arg.required}"
end
```

### Refreshing Prompt Cache

```ruby
# Refresh all prompts
prompts = client.prompts(refresh: true)

# Refresh a specific prompt
prompt = client.prompt("daily_greeting", refresh: true)
```

## Using Prompts in Conversations

### Basic Prompt Usage

```ruby
# Get a prompt
greeting_prompt = client.prompt("daily_greeting")

# Use prompt in a chat
chat = RubyLLM.chat(model: "gpt-4")
chat.with_prompt(greeting_prompt, arguments: {
  name: "Alice",
  time: "morning"
})

response = chat.ask("Continue with the greeting")
puts response
```

### Direct Prompt Queries

```ruby
# Ask using a prompt directly
chat = RubyLLM.chat(model: "gpt-4")
response = chat.ask_prompt(
  client.prompt("code_review"),
  arguments: {
    language: "ruby",
    focus: "security"
  }
)

puts response
```

### Multiple Prompts

```ruby
# Use multiple prompts in a single conversation
chat = RubyLLM.chat(model: "gpt-4")

# Add context prompt
chat.with_prompt(
  client.prompt("project_context"),
  arguments: { project_type: "web_application" }
)

# Add analysis prompt
chat.with_prompt(
  client.prompt("analysis_template"),
  arguments: { focus: "performance" }
)

response = chat.ask("Analyze the project")
puts response
```

## Prompt Arguments

### Required Arguments

```ruby
prompt = client.prompt("user_report")

# Check required arguments
required_args = prompt.arguments.select(&:required)
puts "Required arguments:"
required_args.each do |arg|
  puts "- #{arg.name}: #{arg.description}"
end

# Use with all required arguments
chat = RubyLLM.chat(model: "gpt-4")
response = chat.ask_prompt(prompt, arguments: {
  user_id: "12345",
  date_range: "last_30_days"
})
```

### Optional Arguments

```ruby
prompt = client.prompt("search_query")

# Use with optional arguments
chat = RubyLLM.chat(model: "gpt-4")
response = chat.ask_prompt(prompt, arguments: {
  query: "ruby programming",
  limit: 10,           # optional
  sort_by: "relevance" # optional
})
```

### Argument Validation

```ruby
def validate_prompt_arguments(prompt, arguments)
  required_args = prompt.arguments.select(&:required).map(&:name)
  provided_args = arguments.keys.map(&:to_s)
  missing_args = required_args - provided_args

  unless missing_args.empty?
    raise ArgumentError, "Missing required arguments: #{missing_args.join(', ')}"
  end
end

# Use before calling prompt
validate_prompt_arguments(prompt, arguments)
response = chat.ask_prompt(prompt, arguments: arguments)
```

## Argument Completion

Some MCP servers support argument completion for prompts:

```ruby
# Get completion suggestions for prompt arguments
prompt = client.prompt("user_search")

# Complete a partial argument value
suggestions = prompt.complete("username", "jo")
puts "Suggestions: #{suggestions.values}"
puts "Total matches: #{suggestions.total}"
puts "Has more: #{suggestions.has_more}"

# Use suggestions in your application
if suggestions.values.any?
  puts "Did you mean:"
  suggestions.values.each_with_index do |suggestion, index|
    puts "#{index + 1}. #{suggestion}"
  end
end
```

### Context in Completion Requests

{: .new }
Context in completion requests was introduced in MCP Protocol 2025-06-18.

Completion requests now support context for previously-resolved variables, enabling more intelligent and context-aware suggestions:

```ruby
# For prompts with completion support
prompt = client.prompt("user_search")

# Provide context from previous completions or interactions
completion = prompt.complete(
  "username",
  "jo",
  context: {
    "previous_selections": ["john_doe", "jane_smith"],
    "department": "engineering",
    "project": "web_platform"
  }
)

puts completion.values # Context-aware suggestions
```

#### Context Object Format

The context object can contain any relevant information to help the server provide better suggestions:

```ruby
context = {
  # Previous user selections or completions
  "previous_selections": ["item1", "item2"],

  # User preferences or settings
  "user_preferences": {
    "sort": "date",
    "limit": 10,
    "include_archived": false
  },

  # Environmental context
  "environment": "production",
  "department": "engineering",
  "project": "mobile_app",

  # Session or workflow context
  "current_workflow": "code_review",
  "active_filters": ["ruby", "recent"],

  # Any other relevant data
  "metadata": {
    "timestamp": Time.now.iso8601,
    "session_id": "abc123"
  }
}
```

#### Examples with Different Context Types

**User-specific context:**

```ruby
# Complete usernames with department context
completion = prompt.complete(
  "assignee",
  "al",
  context: {
    "department": "engineering",
    "team": "backend",
    "project_permissions": ["read", "write"]
  }
)
```

**Workflow context:**

```ruby
# Complete with workflow-specific suggestions
completion = prompt.complete(
  "next_action",
  "deploy",
  context: {
    "current_stage": "testing",
    "available_environments": ["staging", "production"],
    "previous_actions": ["build", "test"]
  }
)
```

**Historical context:**

```ruby
# Complete with historical patterns
completion = prompt.complete(
  "bug_priority",
  "h",
  context: {
    "recent_priorities": ["high", "medium", "low"],
    "component": "authentication",
    "similar_issues": ["auth-001", "auth-002"]
  }
)
```

## Advanced Prompt Usage

### Conditional Prompts

```ruby
# Use different prompts based on conditions
def get_appropriate_prompt(client, user_role)
  case user_role
  when "admin"
    client.prompt("admin_dashboard")
  when "developer"
    client.prompt("developer_workflow")
  when "user"
    client.prompt("user_guide")
  else
    client.prompt("general_help")
  end
end

# Use in chat
prompt = get_appropriate_prompt(client, "developer")
chat = RubyLLM.chat(model: "gpt-4")
response = chat.ask_prompt(prompt, arguments: {
  project: "ruby_llm_mcp",
  task: "debugging"
})
```

### Prompt Chaining

```ruby
# Chain prompts for complex workflows
chat = RubyLLM.chat(model: "gpt-4")

# Step 1: Initial analysis
response1 = chat.ask_prompt(
  client.prompt("initial_analysis"),
  arguments: { data: "project_metrics" }
)

# Step 2: Detailed review based on initial analysis
response2 = chat.ask_prompt(
  client.prompt("detailed_review"),
  arguments: {
    initial_findings: response1,
    focus_areas: ["performance", "security"]
  }
)

# Step 3: Generate recommendations
response3 = chat.ask_prompt(
  client.prompt("recommendations"),
  arguments: { analysis: response2 }
)

puts response3
```

### Prompt Templates

```ruby
# Create reusable prompt templates
class PromptTemplate
  def initialize(client, prompt_name)
    @client = client
    @prompt_name = prompt_name
    @prompt = client.prompt(prompt_name)
  end

  def execute(chat, arguments = {})
    validate_arguments(arguments)
    chat.ask_prompt(@prompt, arguments: arguments)
  end

  private

  def validate_arguments(arguments)
    required = @prompt.arguments.select(&:required).map(&:name)
    provided = arguments.keys.map(&:to_s)
    missing = required - provided

    raise ArgumentError, "Missing: #{missing.join(', ')}" unless missing.empty?
  end
end

# Usage
template = PromptTemplate.new(client, "code_review")
chat = RubyLLM.chat(model: "gpt-4")
response = template.execute(chat, {
  language: "ruby",
  focus: "security"
})
```

## Working with Different Prompt Types

### Conversational Prompts

```ruby
# Prompts designed for ongoing conversations
chat = RubyLLM.chat(model: "gpt-4")

# Start with a conversational prompt
chat.with_prompt(
  client.prompt("friendly_assistant"),
  arguments: {
    personality: "helpful",
    expertise: "programming"
  }
)

# Continue the conversation
response = chat.ask("How do I optimize Ruby code?")
puts response
```

### System Prompts

```ruby
# System-level prompts for setting behavior
chat = RubyLLM.chat(model: "gpt-4")

# Set system behavior
chat.with_prompt(
  client.prompt("system_instructions"),
  arguments: {
    role: "code_reviewer",
    standards: "ruby_style_guide"
  }
)

# Now ask questions within that context
response = chat.ask("Review this Ruby code: #{code}")
puts response
```

### Task-Specific Prompts

```ruby
# Prompts for specific tasks
def perform_code_analysis(client, code, language)
  chat = RubyLLM.chat(model: "gpt-4")

  response = chat.ask_prompt(
    client.prompt("code_analysis"),
    arguments: {
      code: code,
      language: language,
      analysis_type: "comprehensive"
    }
  )

  response
end

# Use for different languages
ruby_analysis = perform_code_analysis(client, ruby_code, "ruby")
javascript_analysis = perform_code_analysis(client, js_code, "javascript")
```

### Prompt Not Found

```ruby
begin
  prompt = client.prompt("nonexistent_prompt")
rescue RubyLLM::MCP::Errors::PromptNotFound => e
  puts "Prompt not found: #{e.message}"
end
```

### Argument Errors

```ruby
prompt = client.prompt("user_report")

begin
  chat = RubyLLM.chat(model: "gpt-4")
  response = chat.ask_prompt(prompt, arguments: {
    # Missing required argument
    user_id: "12345"
  })
rescue RubyLLM::MCP::Errors::PromptError => e
  puts "Prompt error: #{e.message}"
  puts "Missing arguments: #{e.missing_arguments}" if e.respond_to?(:missing_arguments)
end
```

### Completion Errors

```ruby
begin
  suggestions = prompt.complete("invalid_argument", "value")
rescue RubyLLM::MCP::Errors::CompletionError => e
  puts "Completion failed: #{e.message}"
end
```

## Next Steps

- **[Notifications]({% link server/notifications.md %})** - Handle real-time updates
- **[Sampling]({% link client/sampling.md %})** - Allow servers to use your LLM
- **[Roots]({% link client/roots.md %})** - Provide filesystem access to servers
