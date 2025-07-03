import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

export function setupTools(server: McpServer) {
  // Tool 1: Add Numbers - will appear on page 1
  server.tool(
    "add_numbers",
    "Add two numbers together",
    {
      a: z.number().describe("First number"),
      b: z.number().describe("Second number"),
    },
    async ({ a, b }) => {
      const result = a + b;
      return {
        content: [
          {
            type: "text",
            text: `The sum of ${a} and ${b} is ${result}`,
          },
        ],
      };
    }
  );

  // Tool 2: Multiply Numbers - will appear on page 2
  server.tool(
    "multiply_numbers",
    "Multiply two numbers together",
    {
      a: z.number().describe("First number"),
      b: z.number().describe("Second number"),
    },
    async ({ a, b }) => {
      const result = a * b;
      return {
        content: [
          {
            type: "text",
            text: `The product of ${a} and ${b} is ${result}`,
          },
        ],
      };
    }
  );

  // Override the default tools/list handler to implement pagination
  const rawServer = server.server;
  rawServer.setRequestHandler(ListToolsRequestSchema, async (request) => {
    const cursor = request.params?.cursor;
    const tools = [
      {
        name: "add_numbers",
        description: "Add two numbers together",
        inputSchema: {
          type: "object",
          properties: {
            a: { type: "number", description: "First number" },
            b: { type: "number", description: "Second number" },
          },
          required: ["a", "b"],
        },
      },
      {
        name: "multiply_numbers",
        description: "Multiply two numbers together",
        inputSchema: {
          type: "object",
          properties: {
            a: { type: "number", description: "First number" },
            b: { type: "number", description: "Second number" },
          },
          required: ["a", "b"],
        },
      },
    ];

    // Pagination logic: 1 tool per page
    if (!cursor) {
      // Page 1: Return first tool
      return {
        tools: [tools[0]],
        nextCursor: "page_2",
      };
    } else if (cursor === "page_2") {
      // Page 2: Return second tool
      return {
        tools: [tools[1]],
        // No nextCursor - this is the last page
      };
    } else {
      // Invalid cursor or beyond available pages
      return {
        tools: [],
      };
    }
  });
}
