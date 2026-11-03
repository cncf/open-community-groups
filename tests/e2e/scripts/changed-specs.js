import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

// Lists the e2e specs a change touches and splits them into chunks for the CI job that repeats
// them (`--repeat-each=3 --retries=0`, one worker per chunk). Changed specs that still exist are
// kept. Changed spec-local helpers (`helpers.js`, `*-helpers.js`) expand to the specs importing
// them, following helpers that import helpers; shared root modules (`utils.js`, `fixtures.js`,
// `seed.js`, ...) and other files do not expand, since they would select most of the suite.
// Changed ARIA snapshot files (`<spec>-snapshots/*.aria.yml`) select their spec.
// Chunks are balanced by spec file size.
//
// Prints two lines in the GitHub Actions output format, so CI can append them to
// $GITHUB_OUTPUT: `repeat_matrix` (JSON array of {chunk, specs}, specs space-separated and
// relative to tests/e2e) and `repeat_count` (number of specs). The specs of each chunk are also
// listed on stderr.
//
// Usage: changed-specs.js [--max-chunks N] CHANGED_PATHS_JSON
//   CHANGED_PATHS_JSON - JSON array of changed paths relative to the repository root
//   --max-chunks       - Maximum number of chunks (default: 8)

const DEFAULT_MAX_CHUNKS = 8;
const E2E_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const HELPER_FILE_PATTERN = /^(?:.+-)?helpers\.js$/u;
const IGNORED_FOLDERS = new Set(["node_modules", "playwright-report", "test-results"]);
const IMPORT_PATTERN = /(?:\bfrom|\bimport)\s*\(?\s*["'](\.{1,2}\/[^"']+)["']/gu;
const REPO_DIR = resolve(E2E_DIR, "../..");
const SPEC_FILE_PATTERN = /\.spec\.js$/u;
const SPEC_SNAPSHOT_PATTERN = /^(.+\.spec\.js)-snapshots\/[^/]+\.aria\.yml$/u;

/**
 * Selects the specs of the changed paths and prints the chunk matrix and the spec count.
 */
const main = () => {
  const { changedPaths, maxChunks } = readOptions();
  const specs = selectSpecs(changedPaths, buildImporters(listModules(E2E_DIR)));
  const chunks = splitIntoChunks(specs, maxChunks);

  const matrix = chunks.map((chunk, index) => ({ chunk: index + 1, specs: chunk.join(" ") }));
  for (const { chunk, specs: chunkSpecs } of matrix) {
    console.error(`chunk ${chunk}/${matrix.length}: ${chunkSpecs}`);
  }
  console.log(`repeat_matrix=${JSON.stringify(matrix)}`);
  console.log(`repeat_count=${specs.length}`);
};

/**
 * Maps every module to the modules that import it through a relative specifier.
 * @param {string[]} modules - Absolute paths of the e2e modules.
 * @returns {Map<string, Set<string>>} Importers by imported module, as absolute paths.
 */
const buildImporters = (modules) => {
  const importers = new Map();
  for (const module of modules) {
    for (const [, specifier] of readFileSync(module, "utf8").matchAll(IMPORT_PATTERN)) {
      const imported = resolve(dirname(module), specifier);
      if (!importers.has(imported)) {
        importers.set(imported, new Set());
      }
      importers.get(imported).add(module);
    }
  }

  return importers;
};

/**
 * Compares two strings by code point, independent of the locale.
 * @param {string} a - First string.
 * @param {string} b - Second string.
 * @returns {number} Negative, zero or positive, as expected by Array.prototype.sort.
 */
const compareStrings = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

/**
 * Checks whether a module is a spec-local helper.
 * @param {string} path - Module path.
 * @returns {boolean} True for `helpers.js` and `*-helpers.js` outside the e2e root folder.
 */
const isSpecLocalHelper = (path) => dirname(path) !== E2E_DIR && HELPER_FILE_PATTERN.test(basename(path));

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

/**
 * Reads the command line options.
 * @returns {{changedPaths: string[], maxChunks: number}} Changed paths and maximum chunk count.
 */
const readOptions = () => {
  const { positionals, values } = parseArgs({
    allowPositionals: true,
    options: {
      "max-chunks": { default: String(DEFAULT_MAX_CHUNKS), type: "string" },
    },
  });
  if (positionals.length !== 1) {
    throw new Error("expected one argument: a JSON array of changed paths");
  }
  const changedPaths = JSON.parse(positionals[0]);
  if (!Array.isArray(changedPaths) || changedPaths.some((path) => typeof path !== "string")) {
    throw new Error("changed paths must be a JSON array of strings");
  }
  const maxChunks = Number(values["max-chunks"]);
  if (!Number.isInteger(maxChunks) || maxChunks < 1) {
    throw new Error(`--max-chunks must be a positive integer (got '${values["max-chunks"]}')`);
  }

  return { changedPaths, maxChunks };
};

/**
 * Selects the existing specs that changed, own a changed ARIA snapshot or import a changed
 * spec-local helper.
 * @param {string[]} changedPaths - Changed paths relative to the repository root.
 * @param {Map<string, Set<string>>} importers - Importers by imported module.
 * @returns {string[]} Spec paths relative to the e2e folder, sorted.
 */
const selectSpecs = (changedPaths, importers) => {
  const specs = new Set();
  const visitedHelpers = new Set();
  const pendingHelpers = [];

  const addModule = (path) => {
    if (SPEC_FILE_PATTERN.test(path)) {
      if (existsSync(path) && statSync(path).isFile()) {
        specs.add(path);
      }
    } else if (isSpecLocalHelper(path) && !visitedHelpers.has(path)) {
      visitedHelpers.add(path);
      pendingHelpers.push(path);
    }
  };

  for (const changedPath of changedPaths) {
    const path = resolve(REPO_DIR, changedPath);
    if (path.startsWith(`${E2E_DIR}${sep}`)) {
      const snapshotSpec = path.split(sep).join("/").match(SPEC_SNAPSHOT_PATTERN)?.[1];
      addModule(snapshotSpec ? resolve(snapshotSpec) : path);
    }
  }
  // Removed helpers expand too, through the importers still pointing at them.
  while (pendingHelpers.length > 0) {
    for (const importer of importers.get(pendingHelpers.pop()) ?? []) {
      addModule(importer);
    }
  }

  return [...specs].map((path) => relative(E2E_DIR, path).split(sep).join("/")).sort(compareStrings);
};

/**
 * Splits specs into at most maxChunks chunks of similar total file size.
 * @param {string[]} specs - Spec paths relative to the e2e folder.
 * @param {number} maxChunks - Maximum number of chunks.
 * @returns {string[][]} Non-empty chunks, each sorted.
 */
const splitIntoChunks = (specs, maxChunks) => {
  const chunks = Array.from({ length: Math.min(specs.length, maxChunks) }, () => ({ size: 0, specs: [] }));
  const sized = specs
    .map((spec) => ({ size: statSync(join(E2E_DIR, spec)).size, spec }))
    .sort((a, b) => b.size - a.size || compareStrings(a.spec, b.spec));

  // Give each spec, largest first, to the chunk with the smallest total so far.
  for (const { size, spec } of sized) {
    const smallest = chunks.reduce((min, chunk) => (chunk.size < min.size ? chunk : min));
    smallest.size += size;
    smallest.specs.push(spec);
  }

  return chunks.map((chunk) => chunk.specs.sort(compareStrings));
};

try {
  main();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}
