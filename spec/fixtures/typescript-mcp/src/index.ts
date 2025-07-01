import express from "express";
import { randomUUID } from "node:crypto";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { setupTools } from "./tools/index.js";
import { setupResources } from "./resources/index.js";
import { setupPrompts } from "./prompts/index.js";
import { registerLogging } from "./logging.js";

// Check for silent flag
const isSilent =
  process.argv.includes("--silent") || process.env.SILENT === "true";

// Conditional logging function
const log = (...args: any[]) => {
  if (!isSilent) {
    console.log(...args);
  }
};

const app = express();
app.use(express.json());

// Request/Response logging middleware
app.use((req, res, next) => {
  if (isSilent) {
    // Skip all logging if silent mode is enabled
    next();
    return;
  }

  const start = Date.now();
  const timestamp = new Date().toISOString();
  let responseBody: any = null;

  // Filter sensitive headers
  const filteredHeaders = { ...req.headers };
  const sensitiveHeaders = [
    "authorization",
    "cookie",
    "x-api-key",
    "x-auth-token",
  ];
  sensitiveHeaders.forEach((header) => {
    if (filteredHeaders[header]) {
      filteredHeaders[header] = "[REDACTED]";
    }
  });

  // Log the incoming request
  log(`\n🌐 === HTTP REQUEST [${timestamp}] ===`);
  log(`📍 ${req.method} ${req.url}`);
  log(`🏠 IP: ${req.ip}`);
  log(`🤖 User-Agent: ${req.get("User-Agent") || "N/A"}`);
  log(`📝 Content-Type: ${req.get("Content-Type") || "N/A"}`);

  // Log query parameters
  if (Object.keys(req.query).length > 0) {
    log(`❓ Query Params:`, JSON.stringify(req.query, null, 2));
  }

  // Log headers (filtered)
  log(`📋 Headers:`, JSON.stringify(filteredHeaders, null, 2));

  // Log request body (limit size)
  if (req.body && Object.keys(req.body).length > 0) {
    const bodyStr = JSON.stringify(req.body, null, 2);
    if (bodyStr.length > 1000) {
      log(
        `📦 Request Body: ${bodyStr.substring(0, 1000)}... [TRUNCATED - ${
          bodyStr.length
        } chars total]`
      );
    } else {
      log(`📦 Request Body:`, req.body);
    }
  }

  // Capture response body by intercepting response methods
  const originalSend = res.send.bind(res);
  const originalJson = res.json.bind(res);
  const originalWrite = res.write.bind(res);
  const originalEnd = res.end.bind(res);

  const chunks: Buffer[] = [];

  res.send = function (body: any) {
    responseBody = body;
    return originalSend(body);
  };

  res.json = function (body: any) {
    responseBody = body;
    return originalJson(body);
  };

  res.write = function (chunk: any, encoding?: any, cb?: any) {
    if (chunk) {
      if (Buffer.isBuffer(chunk)) {
        chunks.push(chunk);
      } else {
        const enc =
          typeof encoding === "string" && encoding
            ? (encoding as BufferEncoding)
            : "utf8";
        chunks.push(Buffer.from(chunk, enc));
      }
    }
    return originalWrite(chunk, encoding, cb);
  };

  res.end = function (chunk?: any, encoding?: any, cb?: any) {
    if (chunk) {
      if (Buffer.isBuffer(chunk)) {
        chunks.push(chunk);
      } else {
        const enc =
          typeof encoding === "string" && encoding
            ? (encoding as BufferEncoding)
            : "utf8";
        chunks.push(Buffer.from(chunk, enc));
      }
    }

    // If we haven't captured response body via send/json, try to get it from chunks
    if (responseBody === null && chunks.length > 0) {
      const fullResponse = Buffer.concat(chunks).toString("utf8");
      try {
        responseBody = JSON.parse(fullResponse);
      } catch {
        responseBody = fullResponse;
      }
    }

    return originalEnd(chunk, encoding, cb);
  };

  // Log response when finished
  res.on("finish", () => {
    const duration = Date.now() - start;

    // Filter sensitive response headers
    const responseHeaders = res.getHeaders();
    const filteredResponseHeaders = { ...responseHeaders };
    const sensitiveResponseHeaders = [
      "set-cookie",
      "authorization",
      "x-api-key",
      "x-auth-token",
    ];
    sensitiveResponseHeaders.forEach((header) => {
      if (filteredResponseHeaders[header]) {
        filteredResponseHeaders[header] = "[REDACTED]";
      }
    });

    log(`\n📤 === HTTP RESPONSE [${new Date().toISOString()}] ===`);
    log(`📍 ${req.method} ${req.url} - ${res.statusCode} - ${duration}ms`);
    log(
      `📋 Response Headers:`,
      JSON.stringify(filteredResponseHeaders, null, 2)
    );

    // Log response body (limit size)
    if (responseBody !== null) {
      if (typeof responseBody === "string") {
        if (responseBody.length > 1000) {
          log(
            `📦 Response Body: ${responseBody.substring(
              0,
              1000
            )}... [TRUNCATED - ${responseBody.length} chars total]`
          );
        } else {
          log(`📦 Response Body: ${responseBody}`);
        }
      } else {
        const bodyStr = JSON.stringify(responseBody, null, 2);
        if (bodyStr.length > 1000) {
          log(
            `📦 Response Body: ${bodyStr.substring(0, 1000)}... [TRUNCATED - ${
              bodyStr.length
            } chars total]`
          );
        } else {
          log(`📦 Response Body:`, responseBody);
        }
      }
    }

    log(`🏁 === END REQUEST/RESPONSE ===\n`);
  });

  next();
});

// Store transports for session management
const transports: Record<string, StreamableHTTPServerTransport> = {};

// Function to create a new server instance
function createServer(): McpServer {
  const server = new McpServer(
    {
      name: "mcp-server",
      version: "1.0.0",
    },
    {
      capabilities: {
        completions: {},
        logging: {},
        resources: {
          subscribe: true,
        },
      },
    }
  );

  // Setup tools, resources, notifications, and prompts
  setupTools(server);
  setupResources(server);
  setupPrompts(server);
  registerLogging(server);

  return server;
}

// Main MCP endpoint - handles all HTTP methods (GET, POST, DELETE)
app.all("/mcp", async (req, res) => {
  // WORKAROUND: Custom ping handling required due to TypeScript SDK limitation
  // The MCP specification states that ping should work before initialization,
  // but the SDK's Streamable HTTP transport requires session management which
  // blocks ping requests without a session. This is a known issue similar to
  // Python SDK issue #423: https://github.com/modelcontextprotocol/python-sdk/issues/423
  //
  // VERIFIED: TypeScript SDK shows "Server not initialized" error (same issue)
  if (req.method === "POST" && req.body && req.body.method === "ping") {
    log(`🏓 Processing ping request (SDK workaround) - ID: ${req.body.id}`);

    const pingResponse = {
      jsonrpc: "2.0",
      id: req.body.id,
      result: {},
    };

    res.status(200).json(pingResponse);
    return;
  }

  const sessionId = req.headers["mcp-session-id"] as string;

  let transport = transports[sessionId];

  if (!transport) {
    // Create new transport for new session
    transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => randomUUID(),
      onsessioninitialized: (sessionId) => {
        transports[sessionId] = transport;
      },
    });

    // Clean up transport when closed
    transport.onclose = () => {
      if (transport.sessionId) {
        delete transports[transport.sessionId];
      }
    };

    // Create and connect server to transport
    const server = createServer();
    await server.connect(transport);
  }

  // Handle the request
  await transport.handleRequest(req, res, req.body);
});

// Health check endpoint
app.get("/health", (req, res) => {
  res.json({ status: "healthy", timestamp: new Date().toISOString() });
});

async function stdioServer() {
  const server = createServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
  if (!isSilent) {
    console.error("Secure MCP Server running on stdio");
  }
}

if (process.argv.includes("--stdio")) {
  stdioServer().catch((error) => {
    console.error("Fatal error running server:", error);
    process.exit(1);
  });
} else {
  const PORT = process.env.PORT || 3005;
  app.listen(PORT, () => {
    log(`🚀 MCP Streamable server running on port ${PORT}`);
    log(`📡 Endpoint: http://localhost:${PORT}/mcp`);
    log(`❤️  Health Check: http://localhost:${PORT}/health`);
  });
}
