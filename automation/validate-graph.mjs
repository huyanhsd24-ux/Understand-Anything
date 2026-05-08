#!/usr/bin/env node
/**
 * validate-graph.mjs
 *
 * Validates the committed knowledge graph against the Understand-Anything
 * schema and (optionally) checks staleness vs the current git commit hash.
 *
 * Usage:
 *   node validate-graph.mjs [--check-stale] [--graph PATH] [--meta PATH]
 *
 * Exit codes:
 *   0  graph valid (and fresh, if --check-stale)
 *   1  schema validation failed
 *   2  graph file missing
 *   3  graph stale (only when --check-stale)
 */

import { readFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const checkStale = args.includes("--check-stale");
const graphPath = resolve(
  args[args.indexOf("--graph") + 1] ??
    ".understand-anything/knowledge-graph.json"
);
const metaPath = resolve(
  args[args.indexOf("--meta") + 1] ?? ".understand-anything/meta.json"
);

function fail(code, msg) {
  console.error(`✗ ${msg}`);
  process.exit(code);
}

if (!existsSync(graphPath)) {
  fail(2, `Graph not found: ${graphPath}\n  Run \`/understand\` to create it, then commit the result.`);
}

// Use the schema validator shipped in @understand-anything/core
let validateGraph;
try {
  ({ validateGraph } = await import("@understand-anything/core/schema"));
} catch (e) {
  fail(
    1,
    `Cannot import @understand-anything/core/schema. Install it as a devDependency:\n  pnpm add -D @understand-anything/core\n\nDetail: ${e.message}`
  );
}

const raw = readFileSync(graphPath, "utf8");
let parsed;
try {
  parsed = JSON.parse(raw);
} catch (e) {
  fail(1, `Graph is not valid JSON: ${e.message}`);
}

const result = validateGraph(parsed);
if (!result.success) {
  console.error(`✗ Schema validation failed (${result.errors.length} issue(s)):`);
  for (const err of result.errors.slice(0, 20)) {
    console.error(`  • ${err.path}: ${err.message}`);
  }
  if (result.errors.length > 20)
    console.error(`  ... and ${result.errors.length - 20} more`);
  process.exit(1);
}
console.log(`✓ Graph valid (${parsed.nodes.length} nodes, ${parsed.edges.length} edges)`);

if (checkStale) {
  if (!existsSync(metaPath)) {
    fail(3, `Meta missing: ${metaPath}. Cannot verify freshness.`);
  }
  const meta = JSON.parse(readFileSync(metaPath, "utf8"));
  const currentHash = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
  if (meta.gitCommitHash !== currentHash) {
    console.error(
      `✗ Graph stale: meta.gitCommitHash=${meta.gitCommitHash?.slice(0, 7)}, HEAD=${currentHash.slice(0, 7)}`
    );
    console.error(
      `  Run \`/understand\` (or enable \`/understand --auto-update\`) and commit the result.`
    );
    process.exit(3);
  }
  console.log(`✓ Graph is fresh (matches commit ${currentHash.slice(0, 7)})`);
}
