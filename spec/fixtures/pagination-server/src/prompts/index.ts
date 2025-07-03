import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { ListPromptsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

export function setupPrompts(server: McpServer) {
  // Prompt 1: Code Review - will appear on page 1
  server.prompt(
    "code_review",
    "Review code for best practices and potential issues",
    {
      code: z.string().describe("The code to review"),
      language: z.string().optional().describe("Programming language"),
    },
    async ({ code, language }) => ({
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text: `Please review the following ${
              language || "code"
            } and provide feedback on best practices, potential issues, and improvements:\n\n${code}`,
          },
        },
      ],
    })
  );

  // Prompt 2: Summary Generator - will appear on page 2
  server.prompt(
    "summarize_text",
    "Generate a concise summary of the provided text",
    {
      text: z.string().describe("The text to summarize"),
      length: z
        .enum(["short", "medium", "long"])
        .optional()
        .describe("Desired summary length"),
    },
    async ({ text, length = "medium" }) => {
      const lengthInstructions = {
        short: "in 1-2 sentences",
        medium: "in 3-4 sentences",
        long: "in a detailed paragraph",
      };

      return {
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: `Please provide a ${length} summary ${lengthInstructions[length]} of the following text:\n\n${text}`,
            },
          },
        ],
      };
    }
  );

  // Override the default prompts/list handler to implement pagination
  const rawServer = server.server;
  rawServer.setRequestHandler(ListPromptsRequestSchema, async (request) => {
    const cursor = request.params?.cursor;
    const prompts = [
      {
        name: "code_review",
        description: "Review code for best practices and potential issues",
        arguments: [
          {
            name: "code",
            description: "The code to review",
            required: true,
          },
          {
            name: "language",
            description: "Programming language",
            required: false,
          },
        ],
      },
      {
        name: "summarize_text",
        description: "Generate a concise summary of the provided text",
        arguments: [
          {
            name: "text",
            description: "The text to summarize",
            required: true,
          },
          {
            name: "length",
            description: "Desired summary length",
            required: false,
          },
        ],
      },
    ];

    // Pagination logic: 1 prompt per page
    if (!cursor) {
      // Page 1: Return first prompt
      return {
        prompts: [prompts[0]],
        nextCursor: "page_2",
      };
    } else if (cursor === "page_2") {
      // Page 2: Return second prompt
      return {
        prompts: [prompts[1]],
        // No nextCursor - this is the last page
      };
    } else {
      // Invalid cursor or beyond available pages
      return {
        prompts: [],
      };
    }
  });
}
