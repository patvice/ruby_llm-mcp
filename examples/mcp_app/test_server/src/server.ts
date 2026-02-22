import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

type TodoItem = {
  id: number;
  description: string;
  done: boolean;
};

type Store = {
  nextId: number;
  items: TodoItem[];
};

const dataFile = process.env.MCP_APP_DATA_FILE || path.resolve(process.cwd(), "data", "items.json");

async function readStore(): Promise<Store> {
  try {
    const content = await readFile(dataFile, "utf8");
    const parsed = JSON.parse(content) as Store;

    return {
      nextId: parsed.nextId || 1,
      items: Array.isArray(parsed.items) ? parsed.items : []
    };
  } catch {
    return { nextId: 1, items: [] };
  }
}

async function writeStore(store: Store): Promise<void> {
  await mkdir(path.dirname(dataFile), { recursive: true });
  await writeFile(dataFile, JSON.stringify(store, null, 2), "utf8");
}

function payload(data: unknown) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(data) }]
  };
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function buildItemsEmbed(items: TodoItem[]): string {
  const itemRows =
    items.length === 0
      ? '<p class="empty">No items yet.</p>'
      : `<ul class="items">${items
          .map(
            (item) =>
              `<li class="row" data-id="${item.id}" data-completed="${item.done}">
                <span class="text ${item.done ? "done" : ""}">#${item.id} · ${escapeHtml(item.description)}</span>
                <span class="right">
                  <button class="toggle-btn ${item.done ? "on" : "off"}" data-action="toggle" data-id="${
                    item.id
                  }" type="button">
                    ${item.done ? "On" : "Off"}
                  </button>
                </span>
              </li>`
          )
          .join("")}</ul>`;

  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <style>
      :root { color-scheme: dark; }
      body {
        margin: 0;
        padding: 12px;
        font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
        background: #070b12;
        color: #e5e7eb;
      }
      .toolbar {
        margin-bottom: 10px;
        display: inline-flex;
        align-items: center;
        gap: 8px;
        border: 1px solid rgba(251, 146, 60, 0.7);
        background: rgba(251, 146, 60, 0.08);
        padding: 8px 10px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        font-size: 11px;
      }
      input[type="checkbox"] {
        accent-color: #fb923c;
      }
      .items {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 8px;
      }
      .row {
        display: flex;
        justify-content: space-between;
        gap: 10px;
        align-items: center;
        border: 1px solid rgba(251, 146, 60, 0.5);
        background: rgba(2, 6, 23, 0.85);
        padding: 10px;
        font-size: 12px;
      }
      .right {
        display: inline-flex;
        align-items: center;
      }
      .text.done {
        color: #6b7280;
        text-decoration: line-through;
      }
      .state {
        color: #fb923c;
      }
      .toggle-btn {
        border: 1px solid rgba(251, 146, 60, 0.8);
        color: #fdba74;
        background: rgba(251, 146, 60, 0.08);
        text-transform: uppercase;
        letter-spacing: 0.1em;
        font-size: 10px;
        padding: 4px 7px;
        cursor: pointer;
        transition: background 120ms ease-in-out, color 120ms ease-in-out;
      }
      .toggle-btn.on {
        background: rgba(16, 185, 129, 0.2);
        border-color: rgba(16, 185, 129, 0.8);
        color: #6ee7b7;
      }
      .toggle-btn.off {
        background: rgba(251, 146, 60, 0.08);
        border-color: rgba(251, 146, 60, 0.8);
        color: #fdba74;
      }
      .toggle-btn:hover {
        background: rgba(251, 146, 60, 0.2);
      }
      .empty {
        margin: 0;
        border: 1px dashed rgba(251, 146, 60, 0.5);
        padding: 12px;
        font-size: 12px;
      }
      .hidden { display: none; }
    </style>
  </head>
  <body>
    <label class="toolbar">
      <input id="hide-completed" type="checkbox" />
      Hide completed (MCP iframe UI)
    </label>
    <section id="items-root">${itemRows}</section>

    <script>
      const toggle = document.getElementById("hide-completed");
      const rows = Array.from(document.querySelectorAll("[data-completed]"));
      const rowMap = new Map(rows.map((row) => [Number(row.getAttribute("data-id")), row]));

      const apply = () => {
        rows.forEach((row) => {
          const isCompleted = row.getAttribute("data-completed") === "true";
          row.classList.toggle("hidden", toggle.checked && isCompleted);
        });
      };

      const setButtonState = (row, pending) => {
        const button = row.querySelector(".toggle-btn");
        if (!button) return;
        button.disabled = pending;
        button.style.opacity = pending ? "0.6" : "1";
      };

      const updateRowState = (row, done) => {
        row.setAttribute("data-completed", String(done));
        const text = row.querySelector(".text");
        if (text) text.classList.toggle("done", done);
        const button = row.querySelector(".toggle-btn");
        if (button) {
          button.textContent = done ? "On" : "Off";
          button.classList.toggle("on", done);
          button.classList.toggle("off", !done);
        }
      };

      apply();

      toggle.addEventListener("change", () => {
        apply();
      });

      document.addEventListener("click", (event) => {
        const target = event.target;
        if (!(target instanceof HTMLElement)) return;
        if (target.dataset.action !== "toggle") return;
        const id = Number(target.dataset.id);
        if (!Number.isInteger(id) || id <= 0) return;
        const row = rowMap.get(id);
        if (row) setButtonState(row, true);

        window.parent.postMessage({ action: "toggle_item", id }, "*");
      });

      window.addEventListener("message", (event) => {
        const data = event.data || {};
        if (data.action === "toggle_item_result" && data.item) {
          const id = Number(data.item.id);
          const row = rowMap.get(id);
          if (!row) return;
          updateRowState(row, Boolean(data.item.done));
          setButtonState(row, false);
          apply();
        }

        if (data.action === "toggle_item_error") {
          const id = Number(data.id);
          const row = rowMap.get(id);
          if (!row) return;
          setButtonState(row, false);
        }
      });
    </script>
  </body>
</html>`;
}

const server = new McpServer({
  name: "mcp-app-test-server",
  version: "1.0.0"
});

server.tool(
  "list_items",
  "List todo items, with optional completed filter",
  { include_completed: z.boolean().optional().default(true) },
  async ({ include_completed }) => {
    const store = await readStore();
    const items = include_completed ? store.items : store.items.filter((item) => !item.done);

    return payload({ items, include_completed });
  }
);

server.tool(
  "render_items_embed",
  "Render iframe HTML for todo items, including isolated JS filtering UI",
  {},
  async () => {
    const store = await readStore();
    const html = buildItemsEmbed(store.items);

    return payload({
      html,
      item_count: store.items.length,
      completed_count: store.items.filter((item) => item.done).length
    });
  }
);

server.tool(
  "create_item",
  "Create a new todo item",
  { description: z.string().min(1) },
  async ({ description }) => {
    const store = await readStore();
    const item: TodoItem = {
      id: store.nextId,
      description,
      done: false
    };

    store.nextId += 1;
    store.items.push(item);
    await writeStore(store);

    return payload({ item, items: store.items });
  }
);

server.tool(
  "mark_done",
  "Mark a todo item as done",
  { id: z.number().int().positive() },
  async ({ id }) => {
    const store = await readStore();
    const item = store.items.find((entry) => entry.id === id);

    if (!item) {
      return {
        content: [{ type: "text", text: `Item ${id} not found` }],
        isError: true
      };
    }

    item.done = true;
    await writeStore(store);

    return payload({ item, items: store.items });
  }
);

server.tool(
  "toggle_done",
  "Toggle a todo item between done and open",
  { id: z.number().int().positive() },
  async ({ id }) => {
    const store = await readStore();
    const item = store.items.find((entry) => entry.id === id);

    if (!item) {
      return {
        content: [{ type: "text", text: `Item ${id} not found` }],
        isError: true
      };
    }

    item.done = !item.done;
    await writeStore(store);

    return payload({ item, items: store.items });
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
