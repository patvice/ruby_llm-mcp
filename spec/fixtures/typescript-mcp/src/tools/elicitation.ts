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
      // This tool simulates what would happen with real elicitation
      // The client will need to handle the elicitation_request metadata

      const elicitationSchema = {
        type: "object",
        properties: {
          preference: {
            type: "string",
            enum: ["option_a", "option_b", "option_c"],
            description: "User's preferred option",
          },
          confidence: {
            type: "number",
            minimum: 0,
            maximum: 1,
            description: "Confidence level in the preference",
          },
          reasoning: {
            type: "string",
            description: "Reasoning behind the preference",
          },
        },
        required: ["preference"],
      };

      return {
        content: [
          {
            type: "text",
            text: `Elicitation request prepared for scenario: ${scenario}`,
          },
        ],
        _meta: {
          elicitation_request: {
            message: `Please provide your preference for scenario: ${scenario}`,
            requestedSchema: elicitationSchema,
            scenario,
          },
          requires_elicitation: true,
          test_mode: true,
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
              type: "array",
              items: { type: "string" },
              minItems: 1,
            },
          },
          required: ["name", "email"],
        },
        settings: {
          type: "object",
          properties: {
            theme: { type: "string", enum: ["light", "dark", "auto"] },
            notifications: { type: "boolean" },
            language: { type: "string", pattern: "^[a-z]{2}$" },
          },
          required: ["theme"],
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

      return {
        content: [
          {
            type: "text",
            text: `Complex elicitation prepared for ${data_type}`,
          },
        ],
        _meta: {
          elicitation_request: {
            message: `Please provide ${data_type} information`,
            requestedSchema: schema,
            data_type,
          },
          requires_elicitation: true,
          complex_schema: true,
          test_mode: true,
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
        type: "object",
        properties: {
          confirmed: { type: "boolean" },
          additional_info: { type: "string" },
        },
        required: request_type === "required" ? ["confirmed"] : [],
      };

      return {
        content: [
          {
            type: "text",
            text: `${request_type} elicitation prepared - client may accept or reject`,
          },
        ],
        _meta: {
          elicitation_request: {
            message: (messages as any)[request_type],
            requestedSchema: schema,
            request_type,
          },
          requires_elicitation: true,
          rejectable: true,
          test_mode: true,
        },
      };
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
        type: "object",
        properties: {
          response: { type: "string" },
          confirmed: { type: "boolean" },
        },
        required: ["response"],
      };

      return {
        content: [
          {
            type: "text",
            text: `Simple elicitation: ${message}`,
          },
        ],
        _meta: {
          elicitation_request: {
            message,
            requestedSchema: schema,
          },
          requires_elicitation: true,
          simple: true,
          test_mode: true,
        },
      };
    }
  );
}
