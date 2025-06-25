import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

const messages: { channel: string; message: string }[] = [
  {
    channel: "general",
    message: "Hello, world!",
  },
  {
    channel: "general",
    message:
      "Welcome to the general channel! Feel free to share your thoughts and ideas here.",
  },
  {
    channel: "ruby",
    message:
      "Ruby is a great language for web development. It's easy to learn and has a large community.",
  },
];

async function listMessages(channel: string) {
  return messages
    .filter((message) => message.channel === channel)
    .map((message) => message.message)
    .join("\n");
}

let permission = "read";
const permissions = ["read", "write", "admin"];

async function upgradeAuthAndStoreToken(new_permission: string) {
  const previous = permission;
  if (!permissions.includes(new_permission)) {
    return { ok: false, err: "Invalid permission", previous: previous };
  }

  permission = new_permission;
  return { ok: true, err: null, previous: previous };
}

async function putMessage(channel: string, message: string) {
  messages.push({ channel, message });
  return message;
}

export function setupMessagingTools(server: McpServer) {
  server.tool(
    "list_messages",
    { channel: z.string() },
    async ({ channel }) => ({
      content: [{ type: "text", text: await listMessages(channel) }],
    })
  );

  const putMessageTool = server.tool(
    "put_message",
    { channel: z.string(), message: z.string() },
    async ({ channel, message }) => ({
      content: [{ type: "text", text: await putMessage(channel, message) }],
    })
  );
  // Until we upgrade auth, `putMessage` is disabled (won't show up in listTools)
  putMessageTool.disable();

  const upgradeAuthTool = server.tool(
    "upgrade_auth",
    "Upgrade authentication permissions",
    { permission: z.enum(["read", "write"]) },
    // Any mutations here will automatically emit `listChanged` notifications
    async ({ permission }, { sendNotification }) => {
      const { ok, err, previous } = await upgradeAuthAndStoreToken(permission);
      if (!ok) return { content: [{ type: "text", text: `Error: ${err}` }] };

      // If we previously had read-only access, 'putMessage' is now available
      if (previous === "read") {
        putMessageTool.enable();
        sendNotification({
          method: "notifications/tools/list_changed",
          params: {},
        });
      } else if (previous === "write") {
        // If we've just upgraded to 'write' permissions, we can still call 'upgradeAuth'
        // but can only upgrade to 'admin'.
        upgradeAuthTool.update({
          paramsSchema: { permission: z.enum(["read", "write", "admin"]) }, // change validation rules
        });
      } else {
        // If we're now an admin, we no longer have anywhere to upgrade to, so fully remove that tool
        upgradeAuthTool.remove();
      }

      return {
        content: [
          { type: "text", text: `Upgraded from ${previous} to ${permission}` },
        ],
      };
    }
  );
}
