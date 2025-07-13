---
layout: default
title: Client Interactions
nav_order: 5
description: "Client-side features and capabilities for MCP integration"
has_children: true
permalink: /client/
---

# Client Interactions

Client interactions cover the features and capabilities that your MCP client provides to servers and manages locally. These are client-side features that enhance the MCP experience by enabling advanced functionality like sampling, filesystem access, and custom transport implementations.

## Overview

MCP clients offer several key capabilities:

- **[Sampling]({% link client/sampling.md %})** - Allow servers to use your LLM for their own requests
- **[Roots]({% link client/roots.md %})** - Provide filesystem access to servers within specified directories

## Client Capabilities

### Sampling

Enable MCP servers to offload LLM requests to your client rather than making them directly. This allows servers to use your LLM connections and configurations while maintaining their own logic and workflows.

### Roots

Provide controlled filesystem access to MCP servers, allowing them to understand your project structure and access files within specified directories for more powerful and context-aware operations.

### Transports

Handle the communication protocol between your client and MCP servers. Use built-in transports or create custom implementations for specialized communication needs.

## Getting Started

Explore each client interaction type to understand how to configure and use client-side features:

- **[Sampling]({% link client/sampling.md %})** - Allow servers to use your LLM
- **[Roots]({% link client/roots.md %})** - Provide filesystem access to servers

## Next Steps

Once you understand client interactions, explore:

- **[Server Interactions]({% link server/index.md %})** - Working with server capabilities
- **[Configuration]({% link configuration.md %})** - Advanced client configuration options
- **[Rails Integration]({% link guides/rails-integration.md %})** - Using MCP with Rails applications
