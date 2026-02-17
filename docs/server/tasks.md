---
layout: default
title: Tasks
parent: Server Interactions
nav_order: 4
description: "Working with MCP tasks - list, inspect, poll results, and cancel long-running operations"
---

# Tasks
{: .no_toc }

MCP tasks let servers expose long-running work through a pollable lifecycle. RubyLLM MCP provides task helpers for listing tasks, checking status, fetching task results, and cancelling in-flight work.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Protocol Support

{: .new }
Task lifecycle APIs are available in MCP Protocol `2025-11-25` and newer.

{: .warning }
Tasks are currently experimental. The MCP task spec and RubyLLM MCP task implementation are both subject to change.

To use tasks, the server must advertise the `tasks` capability.

```ruby
client = RubyLLM::MCP.client(...)

if client.capabilities.tasks?
  puts "Tasks supported"
else
  puts "Server does not support tasks"
end
```

## Listing Tasks

Use `tasks/list` via `client.tasks_list`:

```ruby
tasks = client.tasks_list

tasks.each do |task|
  puts "#{task.task_id} - #{task.status} (#{task.status_message})"
end
```

Each entry is a `RubyLLM::MCP::Task` object with status helpers:
- `working?`
- `input_required?`
- `completed?`
- `failed?`
- `cancelled?`

## Getting Task Status

Use `tasks/get` via `client.task_get(task_id)`:

```ruby
task = client.task_get("task-123")
puts task.status
puts task.status_message
puts task.poll_interval
```

You can also refresh an existing task object:

```ruby
task = task.refresh
```

## Getting Task Results

Use `tasks/result` once a task is complete:

```ruby
task = client.task_get("task-123")

if task.completed?
  payload = client.task_result(task.task_id)
  puts payload.dig("content", 0, "text")
end
```

Or directly from the task object:

```ruby
payload = task.result
```

## Cancelling Tasks

Use `tasks/cancel` for in-flight work:

```ruby
task = client.task_cancel("task-123")

if task.cancelled?
  puts "Task cancelled"
end
```

Or from an existing task object:

```ruby
task = task.cancel
```

## Polling Pattern

Most task workflows poll until a terminal status:

```ruby
task = client.task_get("task-123")

until task.completed? || task.failed? || task.cancelled?
  sleep((task.poll_interval || 250) / 1000.0)
  task = task.refresh
end

if task.completed?
  puts client.task_result(task.task_id)
else
  puts "Task ended with status: #{task.status} - #{task.status_message}"
end
```

## Task Status Notifications

Servers may send `notifications/tasks/status` updates while tasks are running. RubyLLM MCP tracks these updates internally, so subsequent `tasks/list` and `tasks/get` calls reflect the latest known status.
