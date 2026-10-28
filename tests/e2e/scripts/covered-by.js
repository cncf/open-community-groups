import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// Resolves the `coveredBy` references of the coverage allowlists to the tests they name:
//   e2e:<spec>          - Spec file relative to tests/e2e
//   pgtap:<path>        - pgTAP file relative to the repository root
//   rust:<test>         - Function declared in a workspace crate
//   rust:<file>::<test> - Function declared in a Rust file relative to the repository root, for
//                         test names shared by several modules

const E2E_ROOT = fileURLToPath(new URL("..", import.meta.url));
const REPO_ROOT = fileURLToPath(new URL("../../..", import.meta.url));
const RUST_SOURCE_DIRS = ["ocg-common/src", "ocg-redirector/src", "ocg-server/src"];
const SCHEME_FORMATS = { e2e: "e2e:<spec>", pgtap: "pgtap:<path>", rust: "rust:<test>" };

// Function names of the workspace crates, read on first use.
let rustFunctionNames;

/**
 * Checks that a `coveredBy` reference uses an accepted scheme and names an existing test.
 * @param {string} coveredBy - Reference such as `pgtap:<path>` or `rust:<test>`.
 * @param {string[]} schemes - Accepted schemes, among `e2e`, `pgtap` and `rust`.
 * @returns {string|undefined} Problem description, or undefined when the test exists.
 */
export const findCoveredByProblem = (coveredBy, schemes) => {
  const [scheme, target] = splitCoveredBy(coveredBy);

  if (!schemes.includes(scheme) || target === "") {
    const formats = new Intl.ListFormat("en", { type: "disjunction" }).format(
      schemes.map((name) => SCHEME_FORMATS[name]),
    );
    return `coveredBy must be ${formats} (got "${coveredBy}")`;
  }
  if (scheme === "e2e" && !(target.endsWith(".spec.js") && existsSync(join(E2E_ROOT, target)))) {
    return `e2e spec ${target} not found`;
  }
  if (scheme === "pgtap" && !(target.endsWith(".sql") && existsSync(join(REPO_ROOT, target)))) {
    return `pgTAP file ${target} not found`;
  }
  if (scheme === "rust" && !rustTestExists(target)) {
    return `Rust test ${target} not found`;
  }

  return undefined;
};

/**
 * Lists the Rust function names declared in the workspace crates.
 * @returns {Set<string>} Function names.
 */
const listRustFunctionNames = () => {
  const names = new Set();

  for (const dir of RUST_SOURCE_DIRS) {
    const files = readdirSync(join(REPO_ROOT, dir), { recursive: true, withFileTypes: true }).filter(
      (entry) => entry.isFile() && entry.name.endsWith(".rs"),
    );
    for (const file of files) {
      const source = readFileSync(join(file.parentPath, file.name), "utf8");
      for (const match of source.matchAll(/\bfn\s+(\w+)/gu)) {
        names.add(match[1]);
      }
    }
  }

  return names;
};

/**
 * Checks that a Rust test exists, in the given file when the target is file-qualified.
 * @param {string} target - `<test>` or `<file>::<test>`.
 * @returns {boolean} Whether the function is declared.
 */
const rustTestExists = (target) => {
  const separator = target.lastIndexOf("::");
  const name = separator === -1 ? target : target.slice(separator + 2);
  if (!/^\w+$/u.test(name)) {
    return false;
  }

  if (separator === -1) {
    rustFunctionNames ??= listRustFunctionNames();
    return rustFunctionNames.has(name);
  }
  const file = join(REPO_ROOT, target.slice(0, separator));
  if (!file.endsWith(".rs") || !existsSync(file)) {
    return false;
  }

  return new RegExp(`\\bfn\\s+${name}\\b`, "u").test(readFileSync(file, "utf8"));
};

/**
 * Splits a `coveredBy` value into its scheme and target.
 * @param {string} coveredBy - `<scheme>:<target>`.
 * @returns {[string, string]} Scheme and target.
 */
const splitCoveredBy = (coveredBy) => {
  const separator = coveredBy.indexOf(":");

  return separator === -1 ? ["", coveredBy] : [coveredBy.slice(0, separator), coveredBy.slice(separator + 1)];
};
