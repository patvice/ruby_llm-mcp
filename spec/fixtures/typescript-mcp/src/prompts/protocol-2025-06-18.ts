import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { completable } from "@modelcontextprotocol/sdk/server/completable.js";
import { z } from "zod";

export function setupProtocol2025Prompts(server: McpServer) {
  // Prompt with context-aware completion
  server.prompt(
    "context_aware_search",
    "Performs context-aware search with completion support",
    {
      query: z.string().describe("Search query"),
      domain: completable(
        z.string().describe("Search domain or category"),
        (name: string, context?: any) => {
          // Use context if provided to filter suggestions
          const baseOptions = [
            "users",
            "projects",
            "documents",
            "workflows",
            "reports",
          ];

          if (context?.department === "engineering") {
            baseOptions.push("repositories", "pull-requests", "deployments");
          }

          if (context?.department === "marketing") {
            baseOptions.push("campaigns", "analytics", "content");
          }

          return baseOptions.filter((option) =>
            option.toLowerCase().includes(name.toLowerCase())
          );
        }
      ),
      limit: z.string().optional().describe("Maximum results to return"),
    },
    async ({
      query,
      domain,
      limit = "10",
    }: {
      query: string;
      domain: string;
      limit?: string;
    }) => {
      const searchPrompt = `Search for "${query}" in the ${domain} domain. Return up to ${limit} results with context and metadata.`;

      return {
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: searchPrompt,
            },
          },
        ],
        _meta: {
          completion_context_used: true,
          query,
          domain,
          limit,
        },
      };
    }
  );

  // Prompt for user selection with context
  server.prompt(
    "user_selector",
    "Select users with context-aware completion",
    {
      username_prefix: completable(
        z.string().describe("Username prefix to search for"),
        (prefix: string, context?: any) => {
          const allUsers = [
            "alice",
            "admin",
            "analyst",
            "bob",
            "charlie",
            "david",
          ];

          // Filter based on context
          let filteredUsers = allUsers;

          if (context?.department) {
            const deptUsers = {
              engineering: ["alice", "bob", "charlie"],
              marketing: ["admin", "analyst", "david"],
              support: ["alice", "admin", "david"],
            };
            filteredUsers = (deptUsers as any)[context.department] || allUsers;
          }

          if (context?.project) {
            const projectUsers = {
              web_platform: ["alice", "charlie"],
              mobile_app: ["bob", "david"],
              api_service: ["alice", "admin"],
            };
            filteredUsers = filteredUsers.filter((user) =>
              projectUsers[
                context.project as keyof typeof projectUsers
              ]?.includes(user)
            );
          }

          return filteredUsers.filter((user) =>
            user.toLowerCase().startsWith(prefix.toLowerCase())
          );
        }
      ),
      role: z.enum(["developer", "reviewer", "admin"]).optional(),
    },
    async ({
      username_prefix,
      role,
    }: {
      username_prefix: string;
      role?: string;
    }) => {
      let roleText = role ? ` with ${role} permissions` : "";
      const prompt = `Find users matching "${username_prefix}"${roleText} for assignment or collaboration.`;

      return {
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: prompt,
            },
          },
        ],
        _meta: {
          username_prefix,
          role,
          supports_context: true,
        },
      };
    }
  );

  // Simple prompt with human-friendly title
  server.prompt(
    "code_review_request",
    "📋 Code Review Assistant - Generate code review requests with context",
    {
      pull_request: z.string().describe("Pull request identifier"),
      reviewer: completable(
        z.string().describe("Reviewer to assign"),
        (name: string, context?: any) => {
          const reviewers = ["alice", "bob", "charlie", "senior_dev"];

          // Filter by expertise if context provides it
          if (context?.technology) {
            const expertiseMap = {
              javascript: ["alice", "bob"],
              ruby: ["charlie", "senior_dev"],
              python: ["alice", "senior_dev"],
              go: ["bob", "charlie"],
            };
            const experts =
              expertiseMap[context.technology as keyof typeof expertiseMap] ||
              reviewers;
            return experts.filter((r) =>
              r.toLowerCase().includes(name.toLowerCase())
            );
          }

          return reviewers.filter((r) =>
            r.toLowerCase().includes(name.toLowerCase())
          );
        }
      ),
      urgency: z.enum(["low", "medium", "high"]).optional(),
    },
    async ({
      pull_request,
      reviewer,
      urgency = "medium",
    }: {
      pull_request: string;
      reviewer: string;
      urgency?: string;
    }) => {
      const urgencyEmoji = {
        low: "🔵",
        medium: "🟡",
        high: "🔴",
      };

      const prompt = `${
        urgencyEmoji[urgency as keyof typeof urgencyEmoji]
      } Please review pull request ${pull_request}. Assigned reviewer: @${reviewer}. Priority: ${urgency}.`;

      return {
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: prompt,
            },
          },
        ],
        _meta: {
          title: "📋 Code Review Assistant",
          pull_request,
          reviewer,
          urgency,
          context_aware: true,
        },
      };
    }
  );
}
