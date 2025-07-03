# MCP Pagination Server Test

A Model Context Protocol (MCP) server using Streamable HTTP transport to test pagination functionality in the Ruby MCP client. This server demonstrates how MCP pagination works by implementing tools, resources, prompts, and resource templates with 1 item per page.

## Pagination Implementation

This server implements **pagination support** for all MCP list operations:

### Tools Pagination

- **Page 1**: `add_numbers` tool - adds two numbers together
- **Page 2**: `multiply_numbers` tool - multiplies two numbers together

### Resources Pagination

- **Page 1**: `config` resource - application configuration (JSON)
- **Page 2**: `data` resource - sample CSV data

### Prompts Pagination

- **Page 1**: `code_review` prompt - reviews code for best practices
- **Page 2**: `summarize_text` prompt - generates text summaries

### Resource Templates Pagination

- **Page 1**: `user-profile` template - dynamic user profile information (users://{userId}/profile)
- **Page 2**: `file-content` template - access file content by path (files://{path})

## How Pagination Works

The server uses the MCP pagination protocol:

1. **First request** (no cursor): Returns first item + `nextCursor: "page_2"`
2. **Second request** (with cursor): Returns second item (no nextCursor = last page)
3. **Invalid cursor**: Returns empty array

Example API calls:

```json
// Get first page of tools
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
// Response: {"tools":[{...}], "nextCursor":"page_2"}

// Get second page of tools
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"cursor":"page_2"}}
// Response: {"tools":[{...}]} // No nextCursor = last page

// Get first page of resource templates
{"jsonrpc":"2.0","id":3,"method":"resources/templates/list","params":{}}
// Response: {"resourceTemplates":[{...}], "nextCursor":"page_2"}

// Get second page of resource templates
{"jsonrpc":"2.0","id":4,"method":"resources/templates/list","params":{"cursor":"page_2"}}
// Response: {"resourceTemplates":[{...}]} // No nextCursor = last page
```

## Testing the Server

### Method 1: Direct stdio testing

```bash
./test_stdio.sh
```

### Method 2: HTTP mode

```bash
# Start server
bun src/index.ts

# Test with Ruby client (in separate terminal)
ruby test_pagination.rb
```

### Method 3: Manual stdio

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize",...}' | bun src/index.ts --stdio
```

## Usage

### Development

```bash
# Install dependencies
bun install

# Start the server
bun start

# Start with auto-reload during development
bun run dev
```

The server will start on port 3005 (or the port specified in the `PORT` environment variable).

### Endpoints

- **MCP Protocol**: `http://localhost:3007/mcp` - Main MCP endpoint (supports GET, POST, DELETE)
- **Health Check**: `http://localhost:3007/health` - Server health status

## Implementation Details

The pagination is implemented by:

1. **Overriding list handlers** in each setup function using `server.server.setRequestHandler()`
2. **Using Zod schemas** to validate requests with optional cursor parameter
3. **Returning appropriate responses** with `nextCursor` when more pages exist
4. **Supporting all four list types**: tools, resources, prompts, and resource templates

This demonstrates how to properly implement pagination in MCP servers and helps test that MCP clients correctly handle paginated responses.
