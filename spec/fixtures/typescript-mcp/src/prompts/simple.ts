import {
  McpServer,
  type RegisteredPrompt,
} from "@modelcontextprotocol/sdk/server/mcp.js";

let prompt: RegisteredPrompt;

export const data = {
  enable: () => prompt.enable(),
};

export function setupSimplePrompts(server: McpServer) {
  server.prompt(
    "say_hello",
    "This is a simple prompt that will say hello",
    async () => ({
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text: "Hello, how are you? Can you also say Hello back?",
          },
        },
      ],
    })
  );

  server.prompt(
    "multiple_messages",
    "This is a simple prompt that will say hello with a name",
    async () => ({
      messages: [
        {
          role: "assistant",
          content: {
            type: "text",
            text: "You are great at saying hello, the best in the world at it.",
          },
        },
        {
          role: "user",
          content: {
            type: "text",
            text: "Hello, how are you?",
          },
        },
      ],
    })
  );

  server.prompt("poem_of_the_day", "Generates a poem of the day", async () => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: "Can you write me a beautiful poem about the current day? Make sure to include the word 'poem' in your response.",
        },
      },
    ],
  }));

  prompt = server.prompt(
    "disabled_prompt",
    "This is a disabled prompt",
    async () => ({
      messages: [
        {
          role: "user",
          content: { type: "text", text: "This is a disabled prompt" },
        },
      ],
    })
  );

  prompt.disable();
}
