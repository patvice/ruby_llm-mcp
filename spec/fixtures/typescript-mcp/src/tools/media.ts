import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { readResourceFile } from "../utils/file-utils.js";
import { z } from "zod";

export function setupMediaTools(server: McpServer) {
  server.tool(
    "get_jackhammer_audio",
    "Returns the jackhammer audio file as a base64-encoded WAV",
    {},
    async () => {
      try {
        // Read the jackhammer audio file from resources
        const audioBuffer = await readResourceFile("jackhammer.wav");

        // Convert to base64
        const base64Audio = audioBuffer.toString("base64");

        return {
          content: [
            {
              type: "audio",
              data: base64Audio,
              mimeType: "audio/wav",
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
              text: `Error reading jackhammer audio file: ${errorMessage}`,
            },
          ],
        };
      }
    }
  );

  server.tool(
    "get_dog_image",
    "Returns the dog image as a base64-encoded PNG",
    {},
    async () => {
      try {
        // Read the dog image file from resources
        const imageBuffer = await readResourceFile("dog.png");

        // Convert to base64
        const base64Image = imageBuffer.toString("base64");

        return {
          content: [
            {
              type: "image",
              data: base64Image,
              mimeType: "image/png",
            },
          ],
        };
      } catch (error) {
        const currentDir = process.cwd();
        const errorMessage =
          error instanceof Error ? error.message : String(error);
        return {
          content: [
            {
              type: "text",
              text: `Error reading dog image file: ${errorMessage} - current dir: ${currentDir}`,
            },
          ],
        };
      }
    }
  );

  server.tool(
    "get_file_resource",
    "Returns a file resource reference",
    {
      filename: z.string().optional().default("example.txt"),
    },
    async ({ filename }) => {
      return {
        content: [
          {
            type: "resource",
            resource: {
              uri: `file://${filename}`,
              text: `This is the content of ${filename}`,
              mimeType: "text/plain",
            },
          },
        ],
      };
    }
  );
}
