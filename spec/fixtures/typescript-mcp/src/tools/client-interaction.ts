import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

export function setupClientInteractionTools(server: McpServer) {
  server.tool(
    "client-capabilities",
    "Get the capabilities of the client and return them back",
    {},
    async ({}) => {
      const result = await server.server.getClientCapabilities();

      if (result) {
        return {
          content: [
            {
              type: "text",
              text: `Client capabilities: ${JSON.stringify(result)}`,
            },
          ],
        };
      }

      return {
        content: [{ type: "text", text: "Client capabilities not found" }],
        isError: true,
      };
    }
  );

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

  server.tool(
    "roots-test",
    "Test the roots list for a client",
    {},
    async ({}) => {
      try {
        const result = await server.server.listRoots();

        if (result.isError) {
          return {
            content: [
              { type: "text", text: `Roots test failed: ${result.error}` },
            ],
            isError: true,
          };
        }

        return {
          content: [
            {
              type: "text",
              text: `Roots test completed: ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Roots test failed: ${error}` }],
          isError: true,
        };
      }
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
          hints: [{ name: "gemini-2.0-flash" }, { name: "gpt-4o" }],
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
