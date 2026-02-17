---
layout: default
title: Resources
parent: Server
nav_order: 2
description: "Working with MCP resources - static resources, resource templates, and content management"
---

# Resources
{: .no_toc }

MCP resources provide structured data that can be included in conversations - from static files to dynamically generated content. Resources come in two types: normal resources and resource templates.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Static Resources

Static resources are pre-defined data that doesn't change based on parameters.

### Discovering Resources

```ruby
client = RubyLLM::MCP.client(
  name: "content-server",
  transport_type: :stdio,
  config: {
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "/path/to/docs"]
  }
)

# Get all available resources
resources = client.resources
puts "Available resources:"
resources.each do |resource|
  puts "- #{resource.name}: #{resource.description}"
  puts "  URI: #{resource.uri}"
  puts "  Type: #{resource.mime_type}"
end
```

### Using Resources in Conversations

```ruby
# Get a specific resource
readme = client.resource("project_readme")
puts "Resource: #{readme.name}"
puts "Description: #{readme.description}"
puts "Content: #{readme.content}"

# Use resource in a chat
chat = RubyLLM.chat(model: "gpt-4")
chat.with_resource(readme)

response = chat.ask("Summarize the README file")
puts response
```

### Adding Multiple Resources

```ruby
# Add multiple resources to a conversation
chat = RubyLLM.chat(model: "gpt-4")

# Method 1: Add resources individually
chat.with_resource(client.resource("project_readme"))
chat.with_resource(client.resource("api_documentation"))
chat.with_resource(client.resource("changelog"))

# Method 2: Add multiple resources at once
chat.with_resources(
  client.resource("project_readme"),
  client.resource("api_documentation"),
  client.resource("changelog")
)

response = chat.ask("Analyze the project documentation")
puts response
```

### Resource Content Types

Resources can contain different types of content:

```ruby
# Text resource
text_resource = client.resource("config_file")
puts "Text content: #{text_resource.content}"

# JSON resource
json_resource = client.resource("api_schema")
schema = JSON.parse(json_resource.content)
puts "API endpoints: #{schema['endpoints']}"

# Binary resource (images, files)
image_resource = client.resource("diagram")
puts "Image data: #{image_resource.content.bytesize} bytes"
puts "MIME type: #{image_resource.mime_type}"
```

## Resource Templates

Resource templates are parameterized resources that generate content dynamically based on arguments.

### Discovering Resource Templates

```ruby
# Get all resource templates
templates = client.resource_templates
puts "Available templates:"
templates.each do |template|
  puts "- #{template.name}: #{template.description}"
  puts "  URI template: #{template.uri_template}"

  # Show required arguments
  template.arguments.each do |arg|
    required = arg.required ? " (required)" : ""
    puts "  - #{arg.name}: #{arg.description}#{required}"
  end
end
```

### Using Resource Templates

```ruby
# Get a specific template
log_template = client.resource_template("application_logs")

# Use template with arguments in a chat
chat = RubyLLM.chat(model: "gpt-4")
chat.with_resource_template(log_template, arguments: {
  date: "2024-01-15",
  level: "error",
  service: "api"
})

response = chat.ask("What errors occurred in the API service?")
puts response
```

### Template Content Generation

```ruby
# Generate content from template without using in chat
user_template = client.resource_template("user_profile")
content = user_template.to_content(arguments: {
  user_id: "12345",
  include_history: true
})

puts "Generated content: #{content}"
```

### Template Argument Validation

```ruby
template = client.resource_template("report_generator")

# Check required arguments
required_args = template.arguments.select(&:required)
puts "Required arguments:"
required_args.each do |arg|
  puts "- #{arg.name}: #{arg.description}"
end

# Use with all required arguments
chat = RubyLLM.chat(model: "gpt-4")
chat.with_resource_template(template, arguments: {
  start_date: "2024-01-01",
  end_date: "2024-01-31",
  format: "summary"
})
```

## Argument Completion

Some MCP servers support argument completion for resource templates:

```ruby
# Get completion suggestions for template arguments
template = client.resource_template("user_logs")

# Complete a partial argument value
suggestions = template.complete("user_id", "123")
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

## Advanced Resource Usage

## Working with Different Content Types

### Text Resources

```ruby
# Plain text
text_resource = client.resource("plain_text_file")
puts text_resource.content

# Markdown
markdown_resource = client.resource("documentation")
puts "Markdown content: #{markdown_resource.content}"

# Code files
code_resource = client.resource("source_code")
puts "Code: #{code_resource.content}"
```

### Structured Data Resources

```ruby
# JSON resource
json_resource = client.resource("configuration")
config = JSON.parse(json_resource.content)
puts "Config: #{config}"

# YAML resource
yaml_resource = client.resource("metadata")
metadata = YAML.safe_load(yaml_resource.content)
puts "Metadata: #{metadata}"

# CSV resource
csv_resource = client.resource("data_export")
require 'csv'
data = CSV.parse(csv_resource.content, headers: true)
puts "Rows: #{data.length}"
```

### Binary Resources

```ruby
# Image resource
image_resource = client.resource("chart_image")
puts "Image size: #{image_resource.content.bytesize} bytes"
puts "MIME type: #{image_resource.mime_type}"

# Save binary content
File.binwrite("chart.png", image_resource.content)
```

### Subscribing to Resources

MCP allows you to subscribe to resources if the server has the capabilities to do so. When you subscribe to a resource, it will be marked and automatically refreshed on the next usage when the underlying content changes.

```ruby
# Check if a resource supports subscriptions
resource = client.resource("live_data")
if resource.subscribable?
  puts "Resource supports subscriptions"
else
  puts "Resource does not support subscriptions"
end

# Subscribe to a resource for automatic updates
client.subscribe_to_resource("live_data")

# Use the resource - content will be automatically refreshed if it changed
chat = RubyLLM.chat(model: "gpt-4")
chat.with_resource(resource)

# The resource content will be automatically updated on subsequent uses
response = chat.ask("What's the latest data?")
puts response
```

#### Subscription Management

```ruby
# List subscribed resources
subscriptions = client.subscribed_resources
puts "Subscribed to #{subscriptions.length} resources:"
subscriptions.each do |resource_name|
  puts "- #{resource_name}"
end

# Unsubscribe from a resource
client.unsubscribe_from_resource("live_data")

# Check subscription status
is_subscribed = client.subscribed_to?("live_data")
puts "Subscribed to live_data: #{is_subscribed}"
```

#### Handling Resource Updates

```ruby
# Set up a callback for when subscribed resources update
client.on_resource_updated do |resource_uri|
  puts "Subscribed resource updated: #{resource_uri}"

  # Optionally refresh cached data
  resource_name = extract_resource_name(resource_uri)
  updated_resource = client.resource(resource_name, refresh: true)

  puts "Updated content preview: #{updated_resource.content[0..100]}..."
end

# Subscribe to multiple resources
%w[live_metrics real_time_logs current_status].each do |resource_name|
  if client.resource(resource_name).subscribable?
    client.subscribe_to_resource(resource_name)
    puts "Subscribed to #{resource_name}"
  end
end
```

#### Best Practices for Resource Subscriptions

```ruby
# Only subscribe to resources you actively use
class SmartResourceSubscriber
  def initialize(client)
    @client = client
    @active_resources = Set.new
  end

  def use_resource_with_subscription(resource_name)
    # Subscribe on first use
    unless @active_resources.include?(resource_name)
      resource = @client.resource(resource_name)

      if resource.subscribable?
        @client.subscribe_to_resource(resource_name)
        @active_resources.add(resource_name)
        puts "Auto-subscribed to #{resource_name}"
      end
    end

    @client.resource(resource_name)
  end

  def cleanup_unused_subscriptions
    # Unsubscribe from resources not used recently
    @client.subscribed_resources.each do |resource_name|
      unless @active_resources.include?(resource_name)
        @client.unsubscribe_from_resource(resource_name)
        puts "Auto-unsubscribed from unused resource: #{resource_name}"
      end
    end
  end
end

# Usage
subscriber = SmartResourceSubscriber.new(client)
resource = subscriber.use_resource_with_subscription("live_metrics")
```

## Error Handling

### Resource Not Found

```ruby
begin
  resource = client.resource("nonexistent_resource")
rescue RubyLLM::MCP::Errors::ResourceNotFound => e
  puts "Resource not found: #{e.message}"
end
```

### Template Argument Errors

```ruby
template = client.resource_template("user_report")

begin
  content = template.to_content(arguments: {
    # Missing required argument
    start_date: "2024-01-01"
  })
rescue RubyLLM::MCP::Errors::TemplateError => e
  puts "Template error: #{e.message}"
  puts "Missing arguments: #{e.missing_arguments}"
end
```

### Resource Loading Errors

```ruby
begin
  resource = client.resource("large_file")
  content = resource.content
rescue RubyLLM::MCP::Errors::ResourceError => e
  puts "Failed to load resource: #{e.message}"
end
```

```ruby
class ContextBuilder
  def initialize(client)
    @client = client
    @resources = []
    @templates = []
  end

  def add_resource(name)
    @resources << name
    self
  end

  def add_template(name, arguments)
    @templates << { name: name, arguments: arguments }
    self
  end

  def build_for_chat(chat)
    @resources.each do |name|
      chat.with_resource(@client.resource(name))
    end

    @templates.each do |template_config|
      template = @client.resource_template(template_config[:name])
      chat.with_resource_template(template, arguments: template_config[:arguments])
    end

    chat
  end
end

# Usage
chat = RubyLLM.chat(model: "gpt-4")
context = ContextBuilder.new(client)
  .add_resource("project_overview")
  .add_resource("architecture_guide")
  .add_template("recent_commits", { days: 7 })
  .build_for_chat(chat)

response = chat.ask("Analyze the project")
puts response
```

---

## Resource Links in Tool Results

{: .new }
Resource links in tool results are available in MCP Protocol 2025-06-18.

Tools can now return resource references in their results, allowing dynamic resource creation and enhanced tool-resource integration.

### Dynamic Resource Creation

When tools execute and return resource references, these become automatically available as resources:

```ruby
# Execute a tool that creates or references resources
file_tool = client.tool("create_file")
result = file_tool.execute(filename: "report.txt", content: "Analysis results...")

# If the tool returns a resource reference, it becomes available as a resource
if result.is_a?(RubyLLM::MCP::Content)
  # Resource content is automatically parsed and made available
  puts result.to_s

  # The resource may also be added to the client's resource list
  updated_resources = client.resources(refresh: true)
  puts "New resources: #{updated_resources.map(&:name)}"
end
```

### Tool-Generated Resources

Tools can create resources dynamically and return references to them:

```ruby
# A tool that generates a report and returns it as a resource
report_tool = client.tool("generate_report")
result = report_tool.execute(
  data_source: "sales_data",
  format: "pdf",
  timeframe: "last_quarter"
)

# The tool returns a resource reference that can be used immediately
if result.is_a?(RubyLLM::MCP::Content)
  # Use the generated resource in a conversation
  chat = RubyLLM.chat(model: "gpt-4")
  chat.with_resource(result)

  response = chat.ask("Summarize this report")
  puts response
end
```

### Resource Reference Format

Tools can return resources in their content using the `resource` type:

```json
{
  "content": [
    {
      "type": "resource",
      "resource": {
        "uri": "file:///path/to/created/file.txt",
        "name": "generated_report",
        "description": "Quarterly sales report",
        "mimeType": "text/plain",
        "text": "Report content here..."
      }
    }
  ]
}
```

The client automatically converts these references into usable `Resource` objects.

### Tool-Resource Workflows

Combine tools and resources for powerful workflows:

```ruby
# 1. Use a tool to analyze data and create a resource
analysis_tool = client.tool("analyze_data")
analysis_result = analysis_tool.execute(dataset: "user_behavior")

# 2. Use the generated resource in another tool call
if analysis_result.is_a?(RubyLLM::MCP::Content)
  chat = RubyLLM.chat(model: "gpt-4")
  chat.with_resource(analysis_result)

  # 3. Generate recommendations based on the analysis
  recommendation_tool = client.tool("generate_recommendations")
  recommendations = recommendation_tool.execute(
    analysis_resource: analysis_result.uri
  )

  puts "Recommendations: #{recommendations}"
end
```

### Temporary vs Persistent Resources

Tool-generated resources can be:

- **Temporary**: Exist only for the current session
- **Persistent**: Saved and available in future sessions

```ruby
# Check if a resource is temporary or persistent
resource = client.resource("generated_report")
if resource.uri.start_with?("temp://")
  puts "This is a temporary resource"
else
  puts "This is a persistent resource"
end
```

### Best Practices

**Resource Naming:**
- Use descriptive names for generated resources
- Include timestamps or unique identifiers when appropriate
- Consider namespacing for organization

**Content Management:**
- Clean up temporary resources when no longer needed
- Monitor resource creation to prevent storage issues
- Implement proper access controls for persistent resources

**Integration Patterns:**
- Chain tools that create and consume resources
- Use resource templates for consistent resource generation
- Combine with notifications for resource update tracking

## Next Steps

- **[Prompts]({% link server/prompts.md %})** - Using predefined prompts
- **[Notifications]({% link server/notifications.md %})** - Handling real-time updates
- **[Sampling]({% link client/sampling.md %})** - Allow servers to use your LLM
