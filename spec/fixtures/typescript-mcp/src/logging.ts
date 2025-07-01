import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

type LogLevel =
  | "info"
  | "error"
  | "debug"
  | "notice"
  | "warning"
  | "critical"
  | "alert"
  | "emergency";

const loggingLevels = {
  info: 0,
  error: 1,
  debug: 2,
  notice: 3,
  warning: 4,
  critical: 5,
  alert: 6,
  emergency: 7,
};

const LogLevelSchema = z.enum([
  "info",
  "error",
  "debug",
  "notice",
  "warning",
  "critical",
  "alert",
  "emergency",
]);

const LoggingSetLevelSchema = z.object({
  method: z.literal("logging/setLevel"),
  params: z.object({
    level: LogLevelSchema,
  }),
});

let logLevel = "info" as LogLevel;

export function registerLogging(server: McpServer) {
  const rawServer = server.server;
  rawServer.setRequestHandler(LoggingSetLevelSchema, async (request) => {
    const { level } = request.params;

    // Validate the provided log level
    if (!LogLevelSchema.options.includes(level)) {
      throw new Error(`Invalid log level: ${level}`);
    }

    // Update the current log level
    logLevel = level;

    // Respond with an empty result to acknowledge the change
    return {};
  });
}

function shouldLog(level: LogLevel) {
  if (loggingLevels[level] >= loggingLevels[logLevel]) {
    return true;
  }
  return false;
}

export function logger(server: Server) {
  return {
    logLevel,
    log: (message: string, level: LogLevel, logger: string) => {
      if (shouldLog(level)) {
        server.sendLoggingMessage({
          level: level,
          logger: logger || "mcp",
          data: {
            message: message,
          },
        });
      }
    },
    setLogLevel: (level: string) => {
      logLevel = level as LogLevel;
    },
  };
}

/**
 * Unified logging function that works for both stdio and streamable transports
 * @param server - The raw MCP server instance
 * @param message - The message to log
 * @param level - The log level
 * @param loggerName - The logger name (defaults to "mcp")
 * @param sendNotification - Optional sendNotification function from tool execution context (for streamable transport)
 */
export async function logMessage(
  server: Server,
  message: string,
  level: LogLevel,
  loggerName: string = "mcp",
  sendNotification?: (notification: any) => Promise<void>
) {
  // Only log if the level meets the threshold
  if (!shouldLog(level)) {
    return;
  }

  if (sendNotification) {
    // For Streamable HTTP transport, send notification through tool execution context
    await sendNotification({
      method: "notifications/message",
      params: {
        level: level,
        logger: loggerName,
        data: {
          message: message,
        },
      },
    });
  } else {
    // For stdio transport, use the regular server logging
    server.sendLoggingMessage({
      level: level,
      logger: loggerName,
      data: {
        message: message,
      },
    });
  }
}

/**
 * Get the current log level
 */
export function getCurrentLogLevel(): LogLevel {
  return logLevel;
}

/**
 * Check if a message should be logged at the given level
 */
export function shouldLogLevel(level: LogLevel): boolean {
  return shouldLog(level);
}
