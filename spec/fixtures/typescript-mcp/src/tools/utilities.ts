import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function setupUtilityTools(server: McpServer) {
  const rawServer = server.server;

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
      const testEnv = process.env.TEST_ENV || "Not set";
      return {
        content: [{ type: "text", text: `Test Env = ${testEnv}` }],
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
    "timeout_tool",
    "Sleeps for a given number of seconds",
    { seconds: z.number() },
    async ({ seconds }) => {
      await new Promise((resolve) => setTimeout(resolve, seconds * 1000));
      return {
        content: [{ type: "text", text: "Succesfull executed timeout tool" }],
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

        let html: string;

        // Return hardcoded response for example.com to avoid SSL certificate issues
        if (websiteUrl === "https://www.example.com/") {
          html =
            '<!doctype html><html lang="en"><head><title>Example Domain</title><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{background:#eee;width:60vw;margin:15vh auto;font-family:system-ui,sans-serif}h1{font-size:1.5em}div{opacity:0.8}a:link,a:visited{color:#348}</style><body><div><h1>Example Domain</h1><p>This domain is for use in documentation examples without needing permission. Avoid use in operations.<p><a href="https://iana.org/domains/example">Learn more</a></div></body></html>';
        } else {
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

          html = await response.text();
        }

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
