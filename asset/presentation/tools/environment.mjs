import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createRequire } from "node:module";

const here = path.dirname(fileURLToPath(import.meta.url));
export const root = path.resolve(here, "../../..");
export const task = path.join(root, ".ai-interaction/presentation");
export const material = path.resolve(here, "..");

export async function external(name) {
  const modules = process.env.PRESENTATION_NODE_MODULES;
  if (!modules)
    throw new Error("Set PRESENTATION_NODE_MODULES to the authoring modules directory.");
  const require = createRequire(
    path.join(path.dirname(path.resolve(modules)), "package.json"),
  );
  const loaded = await import(pathToFileURL(require.resolve(name)).href);
  return { ...(loaded.default ?? {}), ...loaded };
}
