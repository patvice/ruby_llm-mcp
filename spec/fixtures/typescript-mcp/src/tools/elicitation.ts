import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function setupElicitationTools(server: McpServer) {
  // Tool that simulates elicitation requests for testing
  server.tool(
    "user_preference_elicitation",
    "Collects user preferences through MCP elicitation (simulation)",
    {
      scenario: z
        .string()
        .describe("The scenario for which to collect preferences"),
    },
    async ({ scenario }: { scenario: string }) => {
      // Real elicitation call to the client
      const elicitationResponse = await server.server.elicitInput({
        message: `Please provide your user preferences for scenario: ${scenario}`,
        requestedSchema: {
          type: "object",
          properties: {
            preference: {
              type: "string",
              enum: ["option_a", "option_b", "option_c"],
              description: "User's preferred option",
            } as const,
            confidence: {
              type: "number",
              minimum: 0,
              maximum: 1,
              description: "Confidence level in the preference",
            } as const,
            reasoning: {
              type: "string",
              description: "Reasoning behind the preference",
            } as const,
          },
          required: ["preference"],
        },
      });

      // Use the actual response from the client
      const userInput = elicitationResponse || { preference: "no_response" };

      return {
        content: [
          {
            type: "text",
            text: `Collected user preferences for ${scenario}: ${JSON.stringify(
              userInput
            )}`,
          },
        ],
        _meta: {
          elicitation_completed: true,
          user_input: userInput,
        },
      };
    }
  );

  // Tool for testing elicitation with complex schemas
  server.tool(
    "complex_elicitation",
    "Tests elicitation with complex validation schemas (simulation)",
    {
      data_type: z
        .enum(["user_profile", "settings", "feedback"])
        .describe("Type of data to collect"),
    },
    async ({ data_type }: { data_type: string }) => {
      const schemas = {
        user_profile: {
          type: "object",
          properties: {
            name: { type: "string", minLength: 1 },
            age: { type: "number", minimum: 18, maximum: 120 },
            email: { type: "string", format: "email" },
            preferences: {
              type: "object",
              properties: {
                theme: { type: "string" },
                language: { type: "string" },
              },
            },
          },
          required: ["name", "email"],
        },
        settings: {
          type: "object",
          properties: {
            auto_save: { type: "boolean" },
            backup_frequency: {
              type: "string",
              enum: ["daily", "weekly", "monthly"],
            },
            max_history: { type: "number", minimum: 10, maximum: 1000 },
          },
          required: ["auto_save"],
        },
        feedback: {
          type: "object",
          properties: {
            rating: { type: "number", minimum: 1, maximum: 5 },
            comments: { type: "string", maxLength: 500 },
            recommend: { type: "boolean" },
          },
          required: ["rating"],
        },
      };

      const schema = (schemas as any)[data_type];

      // Real elicitation call to the client
      const elicitationResponse = await server.server.elicitInput({
        message: `Please provide ${data_type} information`,
        requestedSchema: schema,
      });

      const userInput = elicitationResponse || { error: "no_response" };

      return {
        content: [
          {
            type: "text",
            text: `Complex elicitation completed for ${data_type}: ${JSON.stringify(
              userInput
            )}`,
          },
        ],
        _meta: {
          elicitation_completed: true,
          user_input: userInput,
          data_type,
        },
      };
    }
  );

  // Tool for testing elicitation rejection scenarios
  server.tool(
    "rejectable_elicitation",
    "Tests elicitation that can be rejected by the client (simulation)",
    {
      request_type: z
        .enum(["sensitive", "optional", "required"])
        .describe("Type of request"),
    },
    async ({ request_type }: { request_type: string }) => {
      const messages = {
        sensitive:
          "This tool requires access to sensitive user data. Please confirm.",
        optional: "Would you like to provide optional additional information?",
        required:
          "This operation requires mandatory user confirmation to proceed.",
      };

      const schema = {
        type: "object" as const,
        properties: {
          confirmed: { type: "boolean" as const },
          additional_info: { type: "string" as const },
        },
        required: request_type === "required" ? ["confirmed"] : [],
      };

      try {
        // Real elicitation call to the client - may be rejected
        const elicitationResponse = await server.server.elicitInput({
          message: (messages as any)[request_type],
          requestedSchema: schema,
        });

        const userInput = elicitationResponse || { confirmed: false };

        return {
          content: [
            {
              type: "text",
              text: `${request_type} elicitation completed: ${JSON.stringify(
                userInput
              )}`,
            },
          ],
          _meta: {
            elicitation_completed: true,
            user_input: userInput,
            request_type,
          },
        };
      } catch (error) {
        // Handle rejection
        return {
          content: [
            {
              type: "text",
              text: `${request_type} elicitation was rejected by the client`,
            },
          ],
          _meta: {
            elicitation_rejected: true,
            request_type,
          },
        };
      }
    }
  );

  // Simple tool to test basic elicitation patterns
  server.tool(
    "simple_elicitation",
    "Simple elicitation test tool",
    {
      message: z.string().describe("Custom message for elicitation"),
    },
    async ({ message }: { message: string }) => {
      const schema = {
        type: "object" as const,
        properties: {
          response: { type: "string" as const },
          confirmed: { type: "boolean" as const },
        },
        required: ["response"],
      };

      // Real elicitation call to the client
      const elicitationResponse = await server.server.elicitInput({
        message,
        requestedSchema: schema,
      });

      const userInput = elicitationResponse || { response: "no_response" };

      return {
        content: [
          {
            type: "text",
            text: `Simple elicitation completed: ${JSON.stringify(userInput)}`,
          },
        ],
        _meta: {
          elicitation_completed: true,
          user_input: userInput,
        },
      };
    }
  );
}
