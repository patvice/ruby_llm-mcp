import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { existsSync } from "node:fs";

/**
 * Determines if we're in the root of ruby_llm-mcp or in the typescript-mcp directory
 * and returns the correct path to the resources folder
 */
function getResourcesPath(): string {
  const cwd = process.cwd();

  // Check if we're in the root of ruby_llm-mcp (look for ruby_llm-mcp.gemspec)
  if (existsSync(join(cwd, "ruby_llm-mcp.gemspec"))) {
    return "./spec/fixtures/typescript-mcp/resources";
  }

  // Check if we're in the typescript-mcp directory (look for tsconfig.json)
  if (existsSync(join(cwd, "tsconfig.json"))) {
    return "./resources";
  }

  // Fallback to the full path from root
  return "./spec/fixtures/typescript-mcp/resources";
}

/**
 * Reads a file from the resources directory, automatically resolving the correct path
 * based on the current working directory
 */
export async function readResourceFile(filename: string): Promise<Buffer> {
  const resourcesPath = getResourcesPath();
  const fullPath = join(resourcesPath, filename);
  return await readFile(fullPath);
}

/**
 * Reads a text file from the resources directory and returns it as a string
 */
export async function readResourceTextFile(
  filename: string,
  encoding: BufferEncoding = "utf-8"
): Promise<string> {
  const resourcesPath = getResourcesPath();
  const fullPath = join(resourcesPath, filename);
  return await readFile(fullPath, encoding);
}

/**
 * Gets the full path to a resource file
 */
export function getResourcePath(filename: string): string {
  const resourcesPath = getResourcesPath();
  return join(resourcesPath, filename);
}
