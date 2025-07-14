import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { setupSimplePrompts } from "./simple.js";
import { setupGreetingPrompts } from "./greetings.js";
import { setupProtocol2025Prompts } from "./protocol-2025-06-18.js";

export function setupPrompts(server: McpServer) {
  // Setup different categories of prompts
  setupSimplePrompts(server);
  setupGreetingPrompts(server);
  setupProtocol2025Prompts(server);
}
