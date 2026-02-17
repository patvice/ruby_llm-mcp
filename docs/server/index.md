---
layout: default
title: Server
parent: Core Features
nav_order: 1
description: "Understanding and working with MCP server capabilities"
has_children: true
permalink: /server/
---

# Server
{: .no_toc }

Server capabilities encompass all the features MCP servers provide to enhance your applications through tools, resources, prompts, and real-time notifications.

## Overview

MCP servers offer five main types of interactions:

- **[Tools]({% link server/tools.md %})** - Server-side operations that can be executed by LLMs
- **[Resources]({% link server/resources.md %})** - Static and dynamic data that can be included in conversations
- **[Prompts]({% link server/prompts.md %})** - Pre-defined prompts with arguments for consistent interactions
- **[Tasks]({% link server/tasks.md %})** - Pollable background work with lifecycle state and cancellation (experimental)
- **[Notifications]({% link server/notifications.md %})** - Real-time updates from servers about ongoing operations

## Table of contents

1. TOC
{:toc}

## Server Capabilities

### Tools

Execute server-side operations like reading files, making API calls, or running calculations. Tools are automatically converted into RubyLLM-compatible tools for seamless LLM integration.

### Resources

Access structured data from files, databases, or dynamic sources. Resources can be static content or parameterized templates that generate content based on arguments.

### Prompts

Use pre-defined prompts with arguments to ensure consistent interactions across your application. Prompts help standardize common queries and maintain formatting consistency.

### Tasks

Track and manage long-running server operations with task lifecycle endpoints (`tasks/list`, `tasks/get`, `tasks/result`, `tasks/cancel`). This surface is experimental and may change in both the MCP spec and this gem implementation.

### Notifications

Handle real-time updates from servers including logging messages, progress tracking, and resource change notifications during long-running operations.

## Getting Started

Explore each server interaction type to understand how to leverage MCP server capabilities:

- **[Tools]({% link server/tools.md %})** - Execute server-side operations
- **[Resources]({% link server/resources.md %})** - Access and include data in conversations
- **[Prompts]({% link server/prompts.md %})** - Use predefined prompts with arguments
- **[Tasks]({% link server/tasks.md %})** - Poll and manage long-running background operations (experimental)
- **[Notifications]({% link server/notifications.md %})** - Handle real-time server updates

## Next Steps

Once you understand server interactions, explore:

- **[Client]({% link client/index.md %})** - Client-side features like sampling and roots
- **[Configuration]({% link configuration.md %})** - Advanced client configuration options
- **[Rails Integration]({% link guides/rails-integration.md %})** - Using MCP with Rails applications
