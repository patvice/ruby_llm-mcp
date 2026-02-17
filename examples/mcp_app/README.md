# mcp_app

A runnable Rails example that integrates with a local TypeScript MCP server over stdio.

## What this demonstrates

- Rails app calling MCP tools through `ruby_llm-mcp`
- Local TypeScript MCP server with deterministic tools
- End-to-end integration with no external API dependency
- TailwindCSS-driven UI with explicit bordered MCP payload panels
- Two completion paths:
  - Rails-rendered list that calls MCP `mark_done`
  - MCP iframe list with hover `Done` buttons that post a completion request to the parent page

## Tools exposed by the MCP test server

- `list_items` (supports `include_completed` filter)
- `render_items_embed` (returns isolated iframe HTML + JS UI)
- `create_item`
- `mark_done`

The server persists state to `test_server/data/items.json`.

## Quick start

```bash
cd examples/mcp_app
./bin/setup
./bin/reset-data
cd rails_app
bin/rails server
```

Open [http://localhost:3000](http://localhost:3000).

## Run tests

```bash
cd examples/mcp_app
./bin/setup
cd rails_app
bin/rails test
```

## How it works

- Rails MCP config: `rails_app/config/mcps.yml`
- Rails service using tools: `rails_app/app/services/mcp_app_client.rb`
- Rails UI: `rails_app/app/controllers/mcp_items_controller.rb` and `rails_app/app/views/mcp_items/index.html.erb`
- TypeScript MCP server: `test_server/src/server.ts`

When Rails handles a request, it opens an MCP stdio connection, executes the requested tool, then closes the connection.

## Manual MCP server run (optional)

```bash
cd examples/mcp_app/test_server
npm install
npm run start:stdio
```

Rails starts it automatically via `npm --prefix ... run start:stdio` when MCP tools are called, so manual startup is usually unnecessary.
