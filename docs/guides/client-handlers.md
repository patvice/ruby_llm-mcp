---
layout: default
title: Client Handlers
parent: Guides
nav_order: 8
description: "How client handlers work in RubyLLM MCP and what to know to get started quickly"
---

# Client Handlers
{: .no_toc }

{: .label .label-green }
1.0+

Client handlers let your MCP client make decisions when a server asks it to do something interactive:

- Sampling requests (server asks your client to run an LLM call)
- Elicitation requests (server asks for structured user input)
- Human-in-the-loop approvals (server tool calls require approval)

This guide explains how handlers work, how to register them, and the key patterns to start safely.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Handler classes are small Ruby objects with an `execute` method. At runtime, RubyLLM MCP:

1. Instantiates your handler with request context (`sample`, `elicitation`, or tool call info)
2. Runs lifecycle hooks and guards
3. Calls `execute`
4. Interprets your return value and sends the protocol response

Each handler type has a base class:

- `RubyLLM::MCP::Handlers::SamplingHandler`
- `RubyLLM::MCP::Handlers::ElicitationHandler`
- `RubyLLM::MCP::Handlers::HumanInTheLoopHandler`

## Registering Handlers

### Per-client (recommended)

Register handlers directly on a client:

```ruby
client.on_sampling(MySamplingHandler)
client.on_elicitation(MyElicitationHandler)
client.on_human_in_the_loop(MyApprovalHandler)
```

### Global defaults

Global config can provide defaults, and per-client handlers override them.

```ruby
RubyLLM::MCP.configure do |config|
  config.on_human_in_the_loop(MyApprovalHandler)
end
```

`human_in_the_loop` requires handler classes. `sampling` and `elicitation` also support legacy block callbacks, but classes are the recommended path.

## Core Handler API

All handler base classes support:

- `option` for reusable configuration
- `before_execute` and `after_execute` hooks
- `guard` checks (sampling and human-in-the-loop)
- Built-in logging/error handling

Example:

```ruby
class SafeSamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
  option :default_model, default: "gpt-4o-mini"
  guard :check_message_size

  before_execute do
    @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  after_execute do |_result|
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
    RubyLLM::MCP.logger.info("Sampling took #{duration.round(3)}s")
  end

  def execute
    response = default_chat_completion(options[:default_model])
    accept(response)
  end

  private

  def check_message_size
    return true if sample.message.length <= 10_000

    "Message too long"
  end
end
```

## Return Contracts by Handler Type

Your `execute` return value controls what gets sent to the server.

### SamplingHandler

Return one of:

- `accept(response)` -> `{ accepted: true, response: ... }`
- `reject("reason")` -> `{ accepted: false, message: "reason" }`
- `true`/`false` (legacy-compatible behavior)

### ElicitationHandler

Return one of:

- `accept(hash)` -> `{ action: :accept, response: hash }`
- `reject("reason")` -> `{ action: :reject, reason: "reason" }`
- `cancel("reason")` -> `{ action: :cancel, reason: "reason" }`
- `defer(...)`, `Promise`, or `:pending` for async flows
- `true`/`false` (legacy-compatible behavior)

Accepted responses are schema-validated before sending.

### HumanInTheLoopHandler

Return one of:

- `approve` -> `{ status: :approved }`
- `deny("reason")` -> `{ status: :denied, reason: "reason" }`
- `defer(timeout: 300)` -> `{ status: :deferred, timeout: 300 }`

For approvals, handler results must resolve to this hash contract.

## Async Patterns

Async workflows are most common in elicitation and approvals.

### Elicitation async

Use `async_execution` + `defer`, then complete later through the registry:

```ruby
class AsyncElicitationHandler < RubyLLM::MCP::Handlers::ElicitationHandler
  async_execution timeout: 300

  def execute
    notify_ui(elicitation.id, elicitation.message, elicitation.requested_schema)
    defer
  end
end

# Later, from your controller/websocket/job:
RubyLLM::MCP::Handlers::ElicitationRegistry.complete(
  elicitation_id,
  response: { "answer" => "yes" }
)
```

### Approval async

Return `defer(timeout: ...)`, then resolve later:

```ruby
class AsyncApprovalHandler < RubyLLM::MCP::Handlers::HumanInTheLoopHandler
  async_execution timeout: 120

  def execute
    notify_ui(approval_id, tool_name, parameters)
    defer
  end
end

# Later:
RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.approve(approval_id)
# or
RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.deny(approval_id, reason: "Not allowed")
```

## Starter Checklist

1. Choose a handler class per interaction type you need.
2. Keep business rules in guards and `execute`, not in transport code.
3. Use `option` for app-specific dependencies (UI adapters, tenant config, policy services).
4. Prefer explicit `accept`/`reject`/`approve`/`deny` returns over booleans.
5. Add timeouts for async handlers and define failure behavior.
6. Unit test handlers directly by instantiating them with doubles for `sample`, `elicitation`, or coordinator context.

## Related Docs

- **[Sampling]({% link client/sampling.md %})** - Sampling behavior and advanced model selection
- **[Elicitation]({% link client/elicitation.md %})** - Structured user-input workflows
- **[Tools / Human-in-the-loop]({% link server/tools.md %})** - Tool approval and policy patterns
