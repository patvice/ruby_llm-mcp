import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { setupMediaTools } from "./media.js";
import { setupMessagingTools } from "./messaging.js";
import { setupWeatherTools } from "./weather.js";
import { setupUtilityTools } from "./utilities.js";
import { setupNotificationTools } from "./notifications.js";
import { setupClientInteractionTools } from "./client-interaction.js";
import { setupProtocol2025Features } from "./protocol-2025-06-18.js";
import { setupElicitationTools } from "./elicitation.js";

export function setupTools(server: McpServer) {
  // Setup different categories of tools
  setupUtilityTools(server);
  setupMediaTools(server);
  setupMessagingTools(server);
  setupWeatherTools(server);
  setupNotificationTools(server);
  setupClientInteractionTools(server);
  setupProtocol2025Features(server);
  setupElicitationTools(server);
}
