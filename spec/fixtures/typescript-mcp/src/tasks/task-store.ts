export type MCPTaskStatus =
  | "working"
  | "input_required"
  | "completed"
  | "failed"
  | "cancelled";

export interface TaskRecord {
  taskId: string;
  status: MCPTaskStatus;
  statusMessage?: string;
  createdAt: string;
  lastUpdatedAt: string;
  ttl: number;
  pollInterval?: number;
}

interface StoredTask {
  task: TaskRecord;
  payload?: Record<string, unknown>;
}

export class TaskStore {
  private tasks = new Map<string, StoredTask>();

  createTask({
    taskId,
    status = "working",
    statusMessage,
    ttl = 60_000,
    pollInterval = 100,
  }: {
    taskId: string;
    status?: MCPTaskStatus;
    statusMessage?: string;
    ttl?: number;
    pollInterval?: number;
  }): TaskRecord {
    const now = new Date().toISOString();
    const task: TaskRecord = {
      taskId,
      status,
      statusMessage,
      createdAt: now,
      lastUpdatedAt: now,
      ttl,
      pollInterval,
    };

    this.tasks.set(taskId, { task });
    return task;
  }

  listTasks(): TaskRecord[] {
    return Array.from(this.tasks.values()).map(({ task }) => task);
  }

  getTask(taskId: string): TaskRecord | undefined {
    return this.tasks.get(taskId)?.task;
  }

  setTaskStatus(
    taskId: string,
    status: MCPTaskStatus,
    statusMessage?: string
  ): TaskRecord | undefined {
    const current = this.tasks.get(taskId);
    if (!current) return undefined;

    current.task = {
      ...current.task,
      status,
      statusMessage,
      lastUpdatedAt: new Date().toISOString(),
    };
    this.tasks.set(taskId, current);
    return current.task;
  }

  setTaskPayload(taskId: string, payload: Record<string, unknown>): void {
    const current = this.tasks.get(taskId);
    if (!current) return;
    current.payload = payload;
    this.tasks.set(taskId, current);
  }

  getTaskPayload(taskId: string): Record<string, unknown> | undefined {
    return this.tasks.get(taskId)?.payload;
  }
}

export const taskStore = new TaskStore();
