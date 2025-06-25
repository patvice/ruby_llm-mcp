import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

// Helper function to create a delay
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function setupProgressTools(server: McpServer) {
  server.tool(
    "progress",
    "Simulate a multi-step operation with progress notifications",
    {
      operation: z
        .string()
        .optional()
        .describe("Name of the operation to simulate"),
      steps: z.number().optional().describe("Number of steps (default: 3)"),
    },
    async ({ operation = "processing", steps = 3 }, { sendNotification }) => {
      const progressToken = `progress-${Date.now()}`;

      // Send initial progress
      if (sendNotification) {
        await sendNotification({
          method: "notifications/progress",
          params: {
            progressToken,
            progress: 0,
            message: `Starting ${operation}...`,
          },
        });
      }

      // Send progress updates with 1-second delays
      for (let i = 1; i <= steps; i++) {
        await sleep(500); // 0.5 second delay

        const progress = (i / steps) * 100;
        const isComplete = i === steps;

        if (sendNotification) {
          await sendNotification({
            method: "notifications/progress",
            params: {
              progressToken,
              progress,
              message: isComplete
                ? `${operation} completed!`
                : `${operation} step ${i}/${steps} (${Math.round(progress)}%)`,
            },
          });
        }
      }

      return {
        content: [
          {
            type: "text",
            text: `Successfully completed ${operation} with ${steps} steps and progress notifications`,
          },
        ],
      };
    }
  );

  // Also create a simple single progress tool for backward compatibility
  server.tool(
    "simple_progress",
    "Send a single progress notification",
    { progress: z.number().min(0).max(100) },
    async ({ progress }, { sendNotification }) => {
      if (sendNotification) {
        await sendNotification({
          method: "notifications/progress",
          params: {
            progressToken: `simple-${Date.now()}`,
            progress,
            message: `Progress: ${progress}%`,
          },
        });
      }

      return {
        content: [
          {
            type: "text",
            text: `Sent progress notification: ${progress}%`,
          },
        ],
      };
    }
  );
}
