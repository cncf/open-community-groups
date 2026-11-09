import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Rejects e2e locators that break on any restyle: escaped Tailwind variants (`.md\\:hidden`),
// class-predicate XPath (`contains(@class, ...)`) and `title` attribute selectors. Locate
// elements by role, label or text, then by an existing hook or component class (see the
// README, 'Pages, Waits and Timeouts'). A line passes when it, or the line just above it,
// carries `// e2e-locator-allow: <reason>` with a non-empty reason.
//
// Prints one `path:line: <pattern> locator; ...` line per hit and exits with status 1 when
// there is any. Run by `just frontend-fmt-and-lint` and the CI JavaScript format job.
//
// Usage: check-locators.js

const ALLOW_COMMENT_PATTERN = /\/\/\s*e2e-locator-allow:\s*\S/u;
const E2E_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const IGNORED_FOLDERS = new Set(["coverage", "node_modules", "playwright-report", "test-results"]);
const LOCATOR_PATTERNS = [
  { name: "escaped Tailwind variant", pattern: /\\\\:/u },
  { name: "class-predicate XPath", pattern: /contains\(\s*@class/u },
  { name: "title attribute", pattern: /\[title\s*[~|^$*]?=/u },
];
const REPO_DIR = resolve(E2E_DIR, "../..");
const SCRIPT_PATH = fileURLToPath(import.meta.url);

/**
 * Checks every e2e module and prints the rejected locators.
 */
const main = () => {
  const hits = listModules(E2E_DIR)
    .filter((path) => path !== SCRIPT_PATH)
    .toSorted()
    .flatMap(findHits);

  for (const { line, name, path } of hits) {
    console.error(
      `${relative(REPO_DIR, path)}:${line}: ${name} locator; use role, label, text or a data-* hook`,
    );
  }
  if (hits.length > 0) {
    process.exitCode = 1;
  }
};

/**
 * Finds the rejected locators of a module, skipping lines covered by an allow comment.
 * @param {string} path - Absolute path of the module.
 * @returns {{line: number, name: string, path: string}[]} Hits with their 1-based line.
 */
const findHits = (path) => {
  const lines = readFileSync(path, "utf8").split("\n");

  return lines.flatMap((text, index) => {
    const match = LOCATOR_PATTERNS.find(({ pattern }) => pattern.test(text));
    if (!match || ALLOW_COMMENT_PATTERN.test(text) || ALLOW_COMMENT_PATTERN.test(lines[index - 1] ?? "")) {
      return [];
    }
    return [{ line: index + 1, name: match.name, path }];
  });
};

/**
 * Lists the JavaScript modules of a folder recursively, skipping generated and dependency folders.
 * @param {string} folder - Absolute folder path.
 * @returns {string[]} Absolute module paths.
 */
const listModules = (folder) =>
  readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) {
      return IGNORED_FOLDERS.has(entry.name) || entry.name.startsWith(".") ? [] : listModules(path);
    }
    return entry.isFile() && entry.name.endsWith(".js") ? [path] : [];
  });

try {
  main();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}
