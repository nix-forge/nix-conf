/** Produce JavaScript for consumers that read browser or host probe source. */
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
export function javascriptSource(path: string | URL): string {
  return stripTypeScriptTypes(readFileSync(path, "utf8"), { mode: "strip" });
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const source = process.argv[2];
  if (!source) throw new Error("usage: source.mts TYPESCRIPT_FILE");
  process.stdout.write(javascriptSource(source));
}
