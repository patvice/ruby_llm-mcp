import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { setupMediaTools } from "./media.js";
import { setupMessagingTools } from "./messaging.js";
import { setupWeatherTools } from "./weather.js";
import { setupUtilityTools } from "./utilities.js";
import { setupNotificationTools } from "./notifications.js";

export function setupTools(server: McpServer) {
  // Setup different categories of tools
  setupUtilityTools(server);
  setupMediaTools(server);
  setupMessagingTools(server);
  setupWeatherTools(server);
  setupNotificationTools(server);
}
