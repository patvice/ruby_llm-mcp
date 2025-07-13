---
layout: default
title: Server Interactions
nav_order: 4
description: "Understanding and working with MCP server capabilities"
has_children: true
permalink: /server/
---

# Server Interactions
{: .no_toc }

Server interactions encompass all the capabilities that MCP servers provide to enhance your applications. These are the features that servers expose to clients, enabling rich functionality through tools, resources, prompts, and real-time notifications.

## Overview

MCP servers offer four main types of interactions:

- **[Tools]({% link server/tools.md %})** - Server-side operations that can be executed by LLMs
- **[Resources]({% link server/resources.md %})** - Static and dynamic data that can be included in conversations
- **[Prompts]({% link server/prompts.md %})** - Pre-defined prompts with arguments for consistent interactions
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

### Notifications

Handle real-time updates from servers including logging messages, progress tracking, and resource change notifications during long-running operations.

## Getting Started

Explore each server interaction type to understand how to leverage MCP server capabilities:

- **[Tools]({% link server/tools.md %})** - Execute server-side operations
- **[Resources]({% link server/resources.md %})** - Access and include data in conversations
- **[Prompts]({% link server/prompts.md %})** - Use predefined prompts with arguments
- **[Notifications]({% link server/notifications.md %})** - Handle real-time server updates

## Next Steps

Once you understand server interactions, explore:

- **[Client Interactions]({% link client/index.md %})** - Client-side features like sampling and roots
- **[Configuration]({% link configuration.md %})** - Advanced client configuration options
- **[Rails Integration]({% link guides/rails-integration.md %})** - Using MCP with Rails applications
