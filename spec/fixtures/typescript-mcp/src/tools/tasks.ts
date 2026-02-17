import { randomUUID } from "node:crypto";

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { notifyTaskStatus } from "../tasks/protocol.js";
import { taskStore } from "../tasks/task-store.js";

function extractTextContent(content: unknown): string {
  if (!content || typeof content !== "object") return "";
  const data = content as Record<string, unknown>;
  if (data.type === "text" && typeof data.text === "string") return data.text;
  return "";
}

export function setupTaskTools(server: McpServer) {
  server.tool(
    "start_background_task",
    "Create a background task that can be polled with tasks/* APIs",
    {
      prompt: z.string().optional(),
      delay_ms: z.number().optional(),
    },
    async ({ prompt = "Task finished", delay_ms = 200 }) => {
      const taskId = `task-${randomUUID()}`;
      const task = taskStore.createTask({
        taskId,
        status: "working",
        statusMessage: "Task started",
        pollInterval: 50,
      });
      await notifyTaskStatus(server, task);

      setTimeout(() => {
        const completed = taskStore.setTaskStatus(taskId, "completed", "Task completed");
        taskStore.setTaskPayload(taskId, {
          content: [{ type: "text", text: prompt }],
        });
        if (completed) void notifyTaskStatus(server, completed);
      }, delay_ms);

      return {
        content: [{ type: "text", text: `task_id:${taskId}` }],
      };
    }
  );

  server.tool(
    "start_llm_background_task",
    "Create a background task that resolves using sampling/createMessage",
    {
      prompt: z.string(),
    },
    async ({ prompt }) => {
      const taskId = `task-${randomUUID()}`;
      const task = taskStore.createTask({
        taskId,
        status: "working",
        statusMessage: "Waiting for client sampling",
        pollInterval: 50,
      });
      await notifyTaskStatus(server, task);

      try {
        const result = await server.server.createMessage({
          messages: [
            {
              role: "user",
              content: { type: "text", text: prompt },
            },
          ],
          model: "gpt-4o",
          modelPreferences: {
            hints: [{ name: "gpt-4o" }],
          },
          maxTokens: 80,
          task: { ttl: 60_000 },
        } as never);

        const text = extractTextContent(result.content);

        taskStore.setTaskPayload(taskId, {
          content: [{ type: "text", text: text || "No text returned" }],
          model: result.model,
          stopReason: result.stopReason,
        });
        const completed = taskStore.setTaskStatus(taskId, "completed", "Sampling completed");
        if (completed) void notifyTaskStatus(server, completed);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        taskStore.setTaskPayload(taskId, {
          isError: true,
          content: [{ type: "text", text: message }],
        });
        const failed = taskStore.setTaskStatus(taskId, "failed", message);
        if (failed) void notifyTaskStatus(server, failed);
      }

      return {
        content: [{ type: "text", text: `task_id:${taskId}` }],
      };
    }
  );
}
