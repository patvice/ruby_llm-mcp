import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { logMessage } from "../logging.ts";
import { z } from "zod";

import { data as textData } from "../resources/text.ts";

// Helper function to create a delay
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

type LogLevel =
  | "info"
  | "error"
  | "debug"
  | "notice"
  | "warning"
  | "critical"
  | "alert"
  | "emergency";

export function setupNotificationTools(server: McpServer) {
  const raw_server = server.server;

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
    async ({ operation = "processing", steps = 3 }, context) => {
      // Extract progress token from request metadata if available
      // The _meta field should contain the progressToken sent by the client
      const progressToken = context._meta?.progressToken;
      const { sendNotification } = context;

      // Send initial progress
      if (sendNotification && progressToken) {
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
        await sleep(100); // 0.1 second delay

        const progress = (i / steps) * 100;
        const isComplete = i === steps;

        if (sendNotification && progressToken) {
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

  // Simple single progress tool
  server.tool(
    "simple_progress",
    "Send a single progress notification",
    { progress: z.number().min(0).max(100) },
    async ({ progress }, context) => {
      // Extract progress token from request metadata if available
      const progressToken = context._meta?.progressToken;
      const { sendNotification } = context;

      if (sendNotification && progressToken) {
        try {
          await sendNotification({
            method: "notifications/progress",
            params: {
              progressToken,
              progress,
              message: `Progress: ${progress}%`,
            },
          });
        } catch (error) {
          console.error("Error sending progress notification:", error);
        }
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

  server.tool(
    "log_message",
    "Logs a message",
    {
      message: z.string(),
      level: z.string(),
      logger: z.string().optional(),
    },
    async ({ message, level, logger }, { sendNotification }) => {
      const validLevels = [
        "info",
        "error",
        "debug",
        "notice",
        "warning",
        "critical",
        "alert",
        "emergency",
      ];
      const logLevel: LogLevel = validLevels.includes(level)
        ? (level as LogLevel)
        : "info";

      // Use the centralized logging function that handles both transports
      await logMessage(
        raw_server,
        message,
        logLevel,
        logger || "mcp",
        sendNotification
      );

      return {
        content: [{ type: "text", text: "Success!" }],
      };
    }
  );

  server.tool(
    "changes_plain_text_resource",
    "Reference a resource",
    {},
    async ({}, { sendNotification }) => {
      textData.update();

      sendNotification({
        method: "notifications/resources/updated",
        params: {
          uri: "file://plain_text.txt/",
          title: "plain_text.txt",
        },
      });
      return {
        content: [{ type: "text", text: "Success!" }],
      };
    }
  );
}
