import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { logger as log } from "../logging.ts";
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

export function setupUtilityTools(server: McpServer) {
  const raw_server = server.server;

  server.tool(
    "add",
    "Addes two numbers together",
    { a: z.number(), b: z.number() },
    async ({ a, b }) => ({
      content: [{ type: "text", text: String(a + b) }],
    })
  );

  server.tool(
    "return_set_evn",
    "Returns the set environment variable",
    {},
    async () => {
      const env = process.env;

      const test_env = env.TEST_ENV;
      return {
        content: [{ type: "text", text: `Test Env = ${test_env}` }],
      };
    }
  );

  server.tool(
    "malformed_tool",
    "A malformed tool",
    { locations: { test: z.string() } },
    async ({ locations }) => ({
      content: [
        {
          type: "text",
          text: `Weather for ${locations.join(", ")} is great!`,
        },
      ],
    })
  );

  server.tool(
    "log_message",
    "Logs a message",
    {
      message: z.string(),
      level: z.string(),
      logger: z.string().optional(),
    },
    async ({ message, level, logger }) => {
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

      log(raw_server).log(message, logLevel, logger || "mcp");

      return {
        content: [{ type: "text", text: "Success!" }],
      };
    }
  );

  server.tool(
    "tool_error",
    "Returns an error",
    {
      shouldError: z.boolean().optional(),
    },
    async ({ shouldError }) => {
      if (shouldError) {
        const error = Error("Tool error");
        return {
          content: [
            {
              type: "text",
              text: `Error: ${error.message}`,
            },
          ],
          isError: true,
        };
      }

      return {
        content: [{ type: "text", text: "No error" }],
      };
    }
  );

  server.tool(
    "fetch_site",
    "Fetches website content and returns it as text",
    {
      website: z.union([
        z.string(),
        z.object({
          url: z.string(),
          headers: z.array(
            z.object({
              name: z.string(),
              value: z.string(),
            })
          ),
        }),
      ]),
    },
    async ({ website }) => {
      try {
        // Handle both string and object website parameters
        const websiteUrl = typeof website === "string" ? website : website.url;
        const customHeaders =
          typeof website === "object" ? website.headers : undefined;

        // Validate URL
        const url = new URL(websiteUrl);
        if (!["http:", "https:"].includes(url.protocol)) {
          throw new Error("Only HTTP and HTTPS URLs are supported");
        }

        // Fetch the website content with timeout
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 second timeout

        const headers = {
          "User-Agent": "Mozilla/5.0 (compatible; MCP-Tool/1.0)",
          ...customHeaders,
        };

        const headersArray = Object.entries(headers).map(([key, value]) => [
          key,
          value,
        ]);

        const response = await fetch(url.href, {
          headers: Object.fromEntries(headersArray),
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const html = await response.text();

        // Basic HTML content extraction (remove script, style, and HTML tags)
        const cleanText = html
          .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "") // Remove scripts
          .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "") // Remove styles
          .replace(/<[^>]*>/g, " ") // Remove HTML tags
          .replace(/\s+/g, " ") // Normalize whitespace
          .trim();

        // Limit content length to prevent excessive output
        const maxLength = 5000;
        const content =
          cleanText.length > maxLength
            ? cleanText.substring(0, maxLength) + "...[truncated]"
            : cleanText;

        return {
          content: [
            {
              type: "text",
              text: `Website content from ${websiteUrl}:\n\n${content}`,
            },
          ],
        };
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : String(error);
        return {
          content: [
            {
              type: "text",
              text: `Error fetching website content: ${errorMessage}`,
            },
          ],
          isError: true,
        };
      }
    }
  );
}
