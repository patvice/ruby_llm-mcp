import {
  McpServer,
  type RegisteredResource,
} from "@modelcontextprotocol/sdk/server/mcp.js";
import { readFile } from "node:fs/promises";

async function getFileContents(path: string) {
  const filepath = path.replace("file://", "");
  const content = await readFile(
    `./spec/fixtures/typescript-mcp/resources/${filepath}`,
    "utf-8"
  );
  return content;
}

let resource: RegisteredResource | null = null;

let message1 = "Plan text information";
let message2 = "New text information";
let text = message1;
let toggle = 0;

export let data = {
  update: () => {
    if (toggle === 0) {
      text = message2;
      toggle = 1;
    } else {
      text = message1;
      toggle = 0;
    }
  },
  enable: () => {
    if (resource) {
      resource.enable();
    }
  },
  get: () => text,
};

export function setupTextResources(server: McpServer) {
  server.resource(
    "plain_text.txt",
    "file://plain_text.txt/",
    {
      name: "plain_text.txt",
      description: "A plain text file",
      mimeType: "text/plain",
    },
    async (uri) => {
      return {
        contents: [{ uri: uri.href, text: text }],
      };
    }
  );

  server.resource(
    "test.txt",
    "file://test.txt/",
    {
      name: "test.txt",
      description: "A text file",
      mimeType: "text/plain",
    },
    async (uri) => {
      const content = await getFileContents("test.txt");
      return {
        contents: [
          {
            uri: uri.href,
            text: content,
          },
        ],
      };
    }
  );

  server.resource(
    "resource_without_metadata",
    "file://resource_without_metadata.txt/",
    async (uri) => {
      const content = await getFileContents("resource_without_metadata.txt");
      return {
        contents: [
          {
            uri: uri.href,
            text: content,
          },
        ],
      };
    }
  );

  server.resource(
    "second_file.txt",
    "file://second-file.txt/",
    {
      name: "second_file.txt",
      description: "A second text file",
      mimeType: "text/plain",
    },
    async (uri) => {
      const content = await getFileContents("second-file.txt");
      return {
        contents: [
          {
            uri: uri.href,
            text: content,
          },
        ],
      };
    }
  );

  server.resource(
    "my.md",
    "file://my.md/",
    {
      name: "my.md",
      description: "A markdown file",
      mimeType: "text/markdown",
    },
    async (uri) => {
      const content = await getFileContents("my.md");
      return {
        contents: [
          {
            uri: uri.href,
            text: content,
          },
        ],
      };
    }
  );

  resource = server.resource(
    "disabled_resource",
    "file://disabled_resource.txt/",
    {
      name: "resource_with_template.txt",
    },
    async (uri) => {
      return {
        contents: [{ uri: uri.href, text: "Disabled resource" }],
      };
    }
  );

  resource.disable();
}
