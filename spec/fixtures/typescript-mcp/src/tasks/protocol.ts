import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { taskStore } from "./task-store.js";

const ListTasksRequestSchema = z.object({
  method: z.literal("tasks/list"),
  params: z.object({ cursor: z.string().optional() }).optional(),
});

const GetTaskRequestSchema = z.object({
  method: z.literal("tasks/get"),
  params: z.object({ taskId: z.string() }),
});

const GetTaskResultRequestSchema = z.object({
  method: z.literal("tasks/result"),
  params: z.object({ taskId: z.string() }),
});

const CancelTaskRequestSchema = z.object({
  method: z.literal("tasks/cancel"),
  params: z.object({ taskId: z.string() }),
});

export function registerTaskProtocolHandlers(server: McpServer) {
  server.server.setRequestHandler(ListTasksRequestSchema, async () => {
    return {
      tasks: taskStore.listTasks(),
    };
  });

  server.server.setRequestHandler(GetTaskRequestSchema, async (request) => {
    const task = taskStore.getTask(request.params.taskId);
    if (task) return task;

    return {
      taskId: request.params.taskId,
      status: "failed",
      statusMessage: "Task not found",
      createdAt: new Date().toISOString(),
      lastUpdatedAt: new Date().toISOString(),
      ttl: 0,
    };
  });

  server.server.setRequestHandler(GetTaskResultRequestSchema, async (request) => {
    const task = taskStore.getTask(request.params.taskId);
    const payload = taskStore.getTaskPayload(request.params.taskId);

    if (!task) {
      return {
        isError: true,
        content: [{ type: "text", text: `Task not found: ${request.params.taskId}` }],
      };
    }

    if (payload) return payload;

    return {
      isError: true,
      content: [{ type: "text", text: `Task is not complete: ${request.params.taskId}` }],
    };
  });

  server.server.setRequestHandler(CancelTaskRequestSchema, async (request) => {
    const task = taskStore.setTaskStatus(
      request.params.taskId,
      "cancelled",
      "Cancelled by client"
    );

    if (task) {
      notifyTaskStatus(server, task);
      return task;
    }

    return {
      taskId: request.params.taskId,
      status: "cancelled",
      statusMessage: "Task not found; treated as cancelled",
      createdAt: new Date().toISOString(),
      lastUpdatedAt: new Date().toISOString(),
      ttl: 0,
    };
  });
}

export async function notifyTaskStatus(server: McpServer, task: Record<string, unknown>) {
  try {
    await server.server.notification({
      method: "notifications/tasks/status",
      params: task,
    } as never);
  } catch {
    // The test servers can close between async updates; ignore best-effort failures.
  }
}
