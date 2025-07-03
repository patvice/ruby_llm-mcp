import {
  McpServer,
  ResourceTemplate,
} from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  ListResourcesRequestSchema,
  ListResourceTemplatesRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

export function setupResources(server: McpServer) {
  // Resource 1: Configuration Data - will appear on page 1
  server.resource(
    "config",
    "file://config.json",
    {
      name: "Configuration",
      description: "Application configuration data",
      mimeType: "application/json",
    },
    async (uri) => {
      const configData = {
        app_name: "Pagination Server",
        version: "1.0.0",
        environment: "development",
        features: {
          pagination: true,
          tools: true,
          resources: true,
        },
      };

      return {
        contents: [
          {
            uri: uri.href,
            text: JSON.stringify(configData, null, 2),
          },
        ],
      };
    }
  );

  // Resource 2: Sample Data - will appear on page 2
  server.resource(
    "data",
    "file://data.csv",
    {
      name: "Sample Data",
      description: "Sample CSV data for testing",
      mimeType: "text/csv",
    },
    async (uri) => {
      const csvData = `id,name,value
1,Item A,100
2,Item B,200
3,Item C,300
4,Item D,400`;

      return {
        contents: [
          {
            uri: uri.href,
            text: csvData,
          },
        ],
      };
    }
  );

  // Resource Template 1: User Profile - will appear on page 1
  server.resource(
    "user-profile",
    new ResourceTemplate("users://{userId}/profile", { list: undefined }),
    {
      name: "User Profile",
      description: "Dynamic user profile information",
      mimeType: "application/json",
    },
    async (uri, { userId }) => {
      const profileData = {
        userId: userId,
        name: `User ${userId}`,
        email: `user${userId}@example.com`,
        joinDate: "2024-01-01",
        preferences: {
          theme: "dark",
          notifications: true,
        },
      };

      return {
        contents: [
          {
            uri: uri.href,
            text: JSON.stringify(profileData, null, 2),
          },
        ],
      };
    }
  );

  // Resource Template 2: File Content - will appear on page 2
  server.resource(
    "file-content",
    new ResourceTemplate("files://{path}", { list: undefined }),
    {
      name: "File Content",
      description: "Access file content by path",
      mimeType: "text/plain",
    },
    async (uri, { path }) => {
      const fileContent = `This is the content of file: ${path}

File information:
- Path: ${path}
- Type: Text file
- Generated: ${new Date().toISOString()}
- Server: Pagination Test Server

Lorem ipsum content for demonstration purposes...`;

      return {
        contents: [
          {
            uri: uri.href,
            text: fileContent,
          },
        ],
      };
    }
  );

  // Override the default resources/list handler to implement pagination
  const rawServer = server.server;
  rawServer.setRequestHandler(ListResourcesRequestSchema, async (request) => {
    const cursor = request.params?.cursor;
    const resources = [
      {
        uri: "file://config.json",
        name: "Configuration",
        description: "Application configuration data",
        mimeType: "application/json",
      },
      {
        uri: "file://data.csv",
        name: "Sample Data",
        description: "Sample CSV data for testing",
        mimeType: "text/csv",
      },
    ];

    // Pagination logic: 1 resource per page
    if (!cursor) {
      // Page 1: Return first resource
      return {
        resources: [resources[0]],
        nextCursor: "page_2",
      };
    } else if (cursor === "page_2") {
      // Page 2: Return second resource
      return {
        resources: [resources[1]],
        // No nextCursor - this is the last page
      };
    } else {
      // Invalid cursor or beyond available pages
      return {
        resources: [],
      };
    }
  });

  // Add pagination for resource templates
  // Note: Using a manual schema since ListResourceTemplatesRequestSchema might not be exported
  rawServer.setRequestHandler(
    ListResourceTemplatesRequestSchema,
    async (request) => {
      const cursor = request.params?.cursor;
      const resourceTemplates = [
        {
          uriTemplate: "users://{userId}/profile",
          name: "User Profile",
          description: "Dynamic user profile information",
          mimeType: "application/json",
        },
        {
          uriTemplate: "files://{path}",
          name: "File Content",
          description: "Access file content by path",
          mimeType: "text/plain",
        },
      ];

      // Pagination logic: 1 resource template per page
      if (!cursor) {
        // Page 1: Return first resource template
        return {
          resourceTemplates: [resourceTemplates[0]],
          nextCursor: "page_2",
        };
      } else if (cursor === "page_2") {
        // Page 2: Return second resource template
        return {
          resourceTemplates: [resourceTemplates[1]],
          // No nextCursor - this is the last page
        };
      } else {
        // Invalid cursor or beyond available pages
        return {
          resourceTemplates: [],
        };
      }
    }
  );
}
