import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function setupProtocol2025Features(server: McpServer) {
  // Tool with structured output schema
  server.tool(
    "structured_data_analyzer",
    "Analyzes data and returns structured results",
    {
      data: z.string(),
      format: z.enum(["summary", "detailed"]).optional(),
    },
    async ({ data, format = "summary" }: { data: string; format?: string }) => {
      const analysis = {
        word_count: data.split(" ").length,
        character_count: data.length,
        analysis_type: format,
        sentiment: "neutral",
        confidence: 0.85,
      };

      return {
        content: [{ type: "text", text: "Analysis completed" }],
        // This is the structured content that should be validated
        structuredContent: analysis,
      };
    }
  );

  // Tool with invalid structured output (for testing validation)
  server.tool(
    "invalid_structured_output",
    "Tool that returns invalid structured data",
    {
      trigger_error: z.boolean().optional(),
    },
    async ({ trigger_error = true }: { trigger_error?: boolean }) => {
      if (trigger_error) {
        return {
          content: [{ type: "text", text: "Invalid structured data" }],
          // This should fail validation
          structuredContent: {
            invalid_field: "not_a_number",
            missing_required: true,
          },
        };
      }

      return {
        content: [{ type: "text", text: "Valid output" }],
        structuredContent: {
          valid_field: 123,
          required_field: "present",
        },
      };
    }
  );

  // Tool that returns resource links
  server.tool(
    "create_report",
    "Creates a report and returns it as a resource",
    {
      title: z.string(),
      content: z.string(),
      format: z.enum(["text", "json"]).optional(),
    },
    async ({ title, content, format = "text" }) => {
      const timestamp = new Date().toISOString();
      const filename = `report-${Date.now()}.${format}`;

      let resourceContent;
      let mimeType;

      if (format === "json") {
        resourceContent = JSON.stringify(
          {
            title,
            content,
            created_at: timestamp,
            metadata: { format, generated: true },
          },
          null,
          2
        );
        mimeType = "application/json";
      } else {
        resourceContent = `Title: ${title}\n\nContent: ${content}\n\nGenerated: ${timestamp}`;
        mimeType = "text/plain";
      }

      return {
        content: [
          {
            type: "text",
            text: `Report "${title}" created successfully`,
          },
          {
            type: "resource",
            resource: {
              uri: `file:///tmp/reports/${filename}`,
              name: `report_${title.toLowerCase().replace(/\s+/g, "_")}`,
              description: `Generated report: ${title}`,
              mimeType,
              text: resourceContent,
            },
          },
        ],
      };
    }
  );

  // Tool that triggers elicitation
  server.tool(
    "user_preference_collector",
    "Collects user preferences through elicitation",
    {
      scenario: z.string(),
    },
    async ({ scenario }) => {
      // Real elicitation call to the client
      const elicitationSchema = {
        type: "object" as const,
        properties: {
          theme: { type: "string" as const },
          language: { type: "string" as const },
          notifications: { type: "boolean" as const },
        },
        required: ["theme"],
      };

      const elicitationResponse = await server.server.elicitInput({
        message: `Please provide your user preferences for scenario: ${scenario}`,
        requestedSchema: elicitationSchema,
      });

      const userInput = elicitationResponse || { theme: "no_response" };

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
          scenario,
        },
      };
    }
  );

  // Tool with human-friendly title (testing annotations via metadata)
  server.tool(
    "complex_calculation",
    "🧮 Advanced Calculator - Performs complex mathematical calculations",
    {
      expression: z.string(),
      precision: z.number().optional(),
    },
    async ({
      expression,
      precision = 2,
    }: {
      expression: string;
      precision?: number;
    }) => {
      // Simple expression evaluation (unsafe in real scenarios)
      try {
        const result = eval(expression);
        return {
          content: [
            {
              type: "text",
              text: `Result: ${Number(result).toFixed(precision)}`,
            },
          ],
          _meta: {
            title: "🧮 Advanced Calculator",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false,
          },
        };
      } catch (error: unknown) {
        const errorMessage =
          error instanceof Error ? error.message : "Unknown error";
        return {
          content: [
            {
              type: "text",
              text: `Error evaluating expression: ${errorMessage}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  // Tool that supports progress tracking with metadata
  server.tool(
    "long_running_task",
    "Simulates a long-running task with progress updates",
    {
      duration: z.number().optional(),
      steps: z.number().optional(),
    },
    async ({ duration = 1000, steps = 5 }) => {
      const stepDuration = duration / steps;
      const taskId = `task-${Date.now()}`;

      // In a real implementation, this would send progress notifications
      // For testing, we'll return metadata indicating progress tracking

      return {
        content: [
          {
            type: "text",
            text: `Started long-running task with ${steps} steps`,
          },
        ],
        _meta: {
          progress_token: taskId,
          total_steps: steps,
          estimated_duration: duration,
          supports_progress: true,
        },
      };
    }
  );

  // Tool for testing context in completions (simulated)
  server.tool(
    "context_aware_suggestion",
    "Provides suggestions based on context",
    {
      query: z.string(),
      context_type: z.enum(["user", "project", "workflow"]).optional(),
    },
    async ({ query, context_type = "user" }) => {
      // This tool would typically use completion with context
      // For testing, we'll return metadata showing context awareness

      const suggestions = {
        user: ["alice", "admin", "analyst"],
        project: ["mobile_app", "web_platform", "api_service"],
        workflow: ["review", "deploy", "test"],
      };

      const contextSuggestions = suggestions[context_type] || [];
      const filtered = contextSuggestions.filter((s) =>
        s.toLowerCase().includes(query.toLowerCase())
      );

      return {
        content: [
          {
            type: "text",
            text: `Found ${filtered.length} suggestions for "${query}" in ${context_type} context`,
          },
        ],
        _meta: {
          context_type,
          suggestions: filtered,
          query,
          completion_context_used: true,
        },
      };
    }
  );
}
