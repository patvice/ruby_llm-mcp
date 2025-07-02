import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function setupClientInteractionTools(server: McpServer) {
  const rawServer = server.server;

  server.tool(
    "ping_client",
    "Sends a ping to the client to test connectivity",
    {},
    async ({}) => {
      const result = await server.server.ping();

      if (result) {
        return {
          content: [{ type: "text", text: "Ping successful" }],
        };
      }

      return {
        content: [{ type: "text", text: "Ping failed" }],
        isError: true,
      };
    }
  );

  server.tool("sampling-test", "Test the sampling tool", {}, async ({}) => {
    try {
      const result = await server.server.createMessage({
        messages: [
          {
            role: "user" as const,
            content: { type: "text" as const, text: "Hello, how are you?" },
          },
        ],
        model: "gpt-4o",
        modelPreferences: {
          hints: [{ name: "gpt-4o" }],
          costPriority: 1,
          speedPriority: 1,
          intelligencePriority: 1,
        },
        systemPrompt: "You are a helpful assistant.",
        maxTokens: 100,
      });

      if (result.isError) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Sampling test failed: ${result.error}`,
            },
          ],
          isError: true,
        };
      }
      return {
        content: [
          {
            type: "text" as const,
            text: `Sampling test completed: ${JSON.stringify(result)}`,
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          { type: "text" as const, text: `Sampling test failed: ${error}` },
        ],
        isError: true,
      };
    }
  });
}
