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

  server.tool(
    "sample_with_cancellation",
    "Test cancellation by initiating a slow sampling request that can be cancelled",
    {},
    async ({}) => {
      try {
        // Start a sampling request that will take time
        // The client should have a slow sampling callback configured
        // The test will send a cancellation notification while this is in-flight
        const result = await server.server.createMessage({
          messages: [
            {
              role: "user" as const,
              content: {
                type: "text" as const,
                text: "This request should be cancelled by the client",
              },
            },
          ],
          model: "gpt-4o",
          modelPreferences: {
            hints: [{ name: "gpt-4o" }],
          },
          systemPrompt: "You are a helpful assistant.",
          maxTokens: 100,
        });

        // If we get here, the request completed (wasn't cancelled)
        return {
          content: [
            {
              type: "text" as const,
              text: `Cancellation test FAILED: Request completed when it should have been cancelled. Result: ${JSON.stringify(
                result
              )}`,
            },
          ],
          isError: true,
        };
      } catch (error: any) {
        // An error is expected if cancellation worked
        return {
          content: [
            {
              type: "text" as const,
              text: `Cancellation test PASSED: Request was cancelled (${error.message})`,
            },
          ],
        };
      }
    }
  );
}
