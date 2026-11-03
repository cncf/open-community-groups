import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

import { findCoveredByProblem } from "./covered-by.js";

// Reports which public database functions an e2e run called and which audit actions it wrote.
// Run it after the servers stop, so every backend has flushed its function statistics. The
// counts come from `pg_stat_user_functions`, which `just e2e-db-track-functions` enables per
// database. Uncalled `plpgsql` and trigger functions need an allowlist entry naming the test
// that covers them; uncalled `sql` functions are informational because the planner may inline
// them. With --merge it sums the reports of several runs (CI shards) instead of reading
// databases.
//
// Without --blocking the report exits non-zero only when it has no data to report. With
// --blocking it also exits non-zero on uncalled `plpgsql` and trigger functions without an entry
// and on allowlist errors: entries naming no public function or an `sql` one, duplicated or with
// an unresolvable `coveredBy`. It always warns, without failing, on allowlisted functions the run
// called, except for `intermittent` entries: worker timing decides whether a run calls those.
//
// Usage: db-coverage.js [--run-dir DIR] [--db NAME]... [--since TIMESTAMP] [--merge FILE]...
//                       [--json FILE] [--summary] [--blocking]
//   --run-dir  - Parallel run folder with stacks.json and run-started-at
//                (default: $TMPDIR/ocg-e2e-parallel)
//   --db       - Database to read instead of the run's stacks (repeatable)
//   --since    - Start of the audit inventory (default: the run's run-started-at, if any)
//   --merge    - Report written by --json to sum instead of reading databases (repeatable); the
//                audit inventory starts at the earliest run start
//   --json     - File to write the full report to
//   --summary  - Print counts and allowlist problems only (plus the unexplained functions with
//                --blocking)
//   --blocking - Exit non-zero on unexplained uncalled functions and on allowlist errors

const ALLOWLIST_PATH = fileURLToPath(new URL("../coverage/db-function-allowlist.json", import.meta.url));
const AUDIT_FUNCTIONS_DIR = "database/migrations/functions";
const AUDIT_INSERT_FUNCTION = "insert_audit_log";
const BACKEND_EXIT_TIMEOUT_MS = 10_000;
const BACKEND_EXIT_POLL_MS = 200;
const COVERED_BY_SCHEMES = ["pgtap", "rust"];
// Audit action expressions built at runtime, mapped to the actions they can produce.
const DYNAMIC_AUDIT_ACTIONS = new Map([
  // transition_event_cohost accepts the approved, canceled and rejected statuses only.
  [
    "'event_cohost_' || p_status",
    ["event_cohost_approved", "event_cohost_canceled", "event_cohost_rejected"],
  ],
]);
const ENTRY_KINDS = new Set(["plpgsql", "trigger"]);
const REPO_ROOT = fileURLToPath(new URL("../../..", import.meta.url));
const SINCE_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/u;

/**
 * Entry of the allowlist of uncalled functions. `intermittent` marks functions that worker timing
 * decides whether a run calls, so a call is not reported as a stale entry.
 * @typedef {{coveredBy: string, function: string, intermittent?: boolean, reason: string}}
 * AllowlistEntry
 */

/**
 * Runs a query on an e2e database and returns its unaligned psql output (`queryE2eDatabase`).
 * @callback QueryFn
 * @param {string} sql - Query.
 * @param {string} database - Database name.
 * @returns {string} Output rows.
 */

/**
 * Builds the report, prints it, optionally writes it as JSON and fails when blocking.
 * @returns {Promise<void>} Resolves once the report is printed and written.
 */
const main = async () => {
  const options = readOptions();
  const { databases, emittedActions, functions, since } = options.merge
    ? readMergedReports(options)
    : await readDatabases(options);
  if (![...functions.values()].some(({ calls }) => calls > 0)) {
    throw new Error(
      `No function calls recorded in ${databases.join(", ")}; is track_functions enabled ` +
        "(just e2e-db-track-functions, needs a superuser)?",
    );
  }

  // Compare the counters with the allowlist and the audit actions in the SQL sources
  const allowlist = readAllowlist();
  const report = {
    auditActions: buildAuditInventory(emittedActions),
    databases,
    functions: buildFunctionReport(functions, allowlist),
    since: since ?? null,
  };

  printReport(report, options.summary, options.blocking);
  if (options.json) {
    writeFileSync(options.json, `${JSON.stringify(report, null, 2)}\n`);
  }

  const { allowlistErrors, unexplained } = report.functions;
  if (options.blocking && (unexplained.length > 0 || allowlistErrors.length > 0)) {
    throw new Error(
      `DB function coverage check failed: ${unexplained.length} uncalled plpgsql and trigger ` +
        `functions without an allowlist entry, ${allowlistErrors.length} allowlist errors`,
    );
  }
};

/**
 * Compares the audit actions written during the run with those the SQL sources can emit.
 * @param {Map<string, number>} emittedActions - Row count per action written during the run.
 * @returns {object} Emitted actions with counts, source actions not emitted, emitted actions not
 * found in the sources and source expressions the parser could not resolve.
 */
const buildAuditInventory = (emittedActions) => {
  const { actions: sourceActions, unresolved } = parseSourceAuditActions();

  return {
    emitted: [...emittedActions].map(([action, count]) => ({ action, count })),
    notEmitted: [...sourceActions].filter((action) => !emittedActions.has(action)).sort(),
    notInSources: [...emittedActions.keys()].filter((action) => !sourceActions.has(action)),
    sourceCount: sourceActions.size,
    unresolvedSources: unresolved,
  };
};

/**
 * Classifies the merged function counters against the allowlist.
 * @param {Map<string, {calls: number, kind: string}>} functions - Calls and kind per function.
 * @param {AllowlistEntry[]} allowlist - Allowlist entries.
 * @returns {object} Every function with its calls, the unexplained and allowlisted uncalled
 * functions that need an entry, the uncalled `sql` functions, allowlist errors and warnings.
 */
const buildFunctionReport = (functions, allowlist) => {
  const allowlisted = new Set(allowlist.map((entry) => entry.function));
  const uncalled = [...functions].filter(([, { calls }]) => calls === 0);
  const needsEntry = uncalled.filter(([, { kind }]) => ENTRY_KINDS.has(kind)).map(([name]) => name);
  const { errors, warnings } = checkAllowlist(allowlist, functions);

  return {
    all: [...functions].map(([name, { calls, kind }]) => ({ calls, function: name, kind })),
    allowlistErrors: errors,
    allowlistWarnings: warnings,
    calledCount: functions.size - uncalled.length,
    uncalledAllowlisted: needsEntry.filter((name) => allowlisted.has(name)),
    uncalledInformational: uncalled.filter(([, { kind }]) => !ENTRY_KINDS.has(kind)).map(([name]) => name),
    unexplained: needsEntry.filter((name) => !allowlisted.has(name)),
  };
};

/**
 * Checks the allowlist entries against the function counters.
 * @param {AllowlistEntry[]} allowlist - Allowlist entries.
 * @param {Map<string, {calls: number, kind: string}>} functions - Calls and kind per function.
 * @returns {{errors: string[], warnings: string[]}} Entries that are duplicated, name no
 * function needing one or an unresolvable covering test (errors), and entries of functions this
 * run called that are not intermittent (warnings).
 */
const checkAllowlist = (allowlist, functions) => {
  const errors = [];
  const seen = new Set();
  const warnings = [];

  for (const entry of allowlist) {
    const name = entry.function;
    const counters = functions.get(name);

    if (seen.has(name)) {
      errors.push(`${name}: duplicate entry`);
    }
    seen.add(name);

    // Every entry must name a plpgsql or trigger function
    if (!counters) {
      errors.push(`${name}: not a public database function`);
    } else if (!ENTRY_KINDS.has(counters.kind)) {
      errors.push(`${name}: ${counters.kind} functions need no entry`);
    } else if (counters.calls > 0 && !entry.intermittent) {
      warnings.push(`${name}: called ${counters.calls} times in this run; remove the entry`);
    }

    // The covering test must exist
    const problem = findCoveredByProblem(entry.coveredBy, COVERED_BY_SCHEMES);
    if (problem) {
      errors.push(`${name}: ${problem}`);
    }
  }

  return { errors, warnings };
};

/**
 * Collects the string literals that follow `then` or `else` in a `case` expression.
 * @param {string} expression - `case` expression.
 * @returns {string[]} Result literals, empty when a branch is not a literal.
 */
const extractCaseLiterals = (expression) => {
  const literals = [...expression.matchAll(/\b(?:then|else)\s+'([^']+)'/giu)].map((match) => match[1]);
  const branches = expression.match(/\b(?:then|else)\b/giu) ?? [];

  return literals.length === branches.length ? literals : [];
};

/**
 * Finds the function defined around an offset of a SQL source file.
 * @param {string} sql - SQL source without comments.
 * @param {number} index - Offset inside the function body.
 * @returns {string|undefined} Name of the closest preceding function definition.
 */
const findEnclosingFunction = (sql, index) => {
  const definitions = [...sql.slice(0, index).matchAll(/\bfunction\s+(\w+)\s*\(/giu)];

  return definitions.at(-1)?.[1];
};

/**
 * Finds the calls of a function in a SQL source, ignoring its definition.
 * @param {string} sql - SQL source without comments.
 * @param {string} name - Function name.
 * @returns {{args: string[], index: number}[]} Top-level arguments and offset of every call.
 */
const findFunctionCalls = (sql, name) =>
  [...sql.matchAll(new RegExp(`(\\bfunction\\s+)?\\b${name}\\s*\\(`, "giu"))]
    .filter((match) => !match[1])
    .map((match) => ({
      args: splitTopLevel(sql, match.index + match[0].length).items,
      index: match.index,
    }));

/**
 * Lists the SQL files under a folder, recursively.
 * @param {string} dir - Absolute folder path.
 * @returns {string[]} Absolute file paths.
 */
const listSqlFiles = (dir) =>
  readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".sql"))
    .map((entry) => join(entry.parentPath, entry.name));

/**
 * Sums the audit action counts of several databases.
 * @param {Map<string, number>[]} perDatabase - Row count per action for each database.
 * @returns {Map<string, number>} Row count per action, sorted by action.
 */
const mergeAuditActions = (perDatabase) => {
  const merged = new Map();

  for (const actions of perDatabase) {
    for (const [action, count] of actions) {
      merged.set(action, (merged.get(action) ?? 0) + count);
    }
  }

  return new Map([...merged].sort(([a], [b]) => (a < b ? -1 : 1)));
};

/**
 * Sums the function calls of several databases.
 * @param {Map<string, {calls: number, kind: string}>[]} perDatabase - Counters for each database.
 * @returns {Map<string, {calls: number, kind: string}>} Calls and kind per function.
 */
const mergeFunctionCalls = (perDatabase) => {
  const merged = new Map();

  for (const functions of perDatabase) {
    for (const [name, { calls, kind }] of functions) {
      merged.set(name, { calls: (merged.get(name)?.calls ?? 0) + calls, kind });
    }
  }

  return merged;
};

/**
 * Parses the audit actions the database functions can write.
 *
 * Actions come from the first argument of `insert_audit_log` calls and of the audit helpers
 * that forward a parameter to it, and from direct `insert into audit_log` statements. An
 * argument may be a literal, a `case` with literal branches, a `v_*` variable assigned
 * literals in the same file or a known dynamic expression.
 * @returns {{actions: Set<string>, unresolved: string[]}} Actions and unparsed expressions.
 */
const parseSourceAuditActions = () => {
  const sources = listSqlFiles(join(REPO_ROOT, AUDIT_FUNCTIONS_DIR)).map((path) => ({
    file: relative(REPO_ROOT, path),
    sql: stripSqlComments(readFileSync(path, "utf8")),
  }));
  const actions = new Set();
  const unresolved = [];
  const collect = (file, sql, expression, label) => {
    const resolved = resolveActionExpression(expression, sql);
    if (resolved === undefined) {
      unresolved.push(`${file}: ${label}`);
    }
    for (const action of resolved ?? []) {
      actions.add(action);
    }
  };

  // Find the helpers that forward an action parameter to insert_audit_log
  const helpers = new Set([AUDIT_INSERT_FUNCTION]);
  let added = true;
  while (added) {
    added = false;
    for (const { sql } of sources) {
      for (const helper of helpers) {
        for (const call of findFunctionCalls(sql, helper)) {
          const wrapper = findEnclosingFunction(sql, call.index);
          if (/^p_\w+$/u.test(readActionArgument(call.args)) && wrapper && !helpers.has(wrapper)) {
            helpers.add(wrapper);
            added = true;
          }
        }
      }
    }
  }

  for (const { file, sql } of sources) {
    // Resolve the action argument of every helper call
    for (const helper of helpers) {
      for (const call of findFunctionCalls(sql, helper)) {
        const expression = readActionArgument(call.args);
        collect(file, sql, expression, `${helper}(${expression})`);
      }
    }

    // Resolve the action value of direct inserts
    for (const match of sql.matchAll(/\binsert\s+into\s+audit_log\s*\(/giu)) {
      const columns = splitTopLevel(sql, match.index + match[0].length);
      const actionIndex = columns.items.indexOf("action");
      const rest = sql.slice(columns.end);
      const values = /^\s*values\s*\(/iu.exec(rest);
      const select = /^\s*select\b/iu.exec(rest);
      let row = [];
      if (values) {
        row = splitTopLevel(sql, columns.end + values[0].length).items;
      } else if (select) {
        row = splitTopLevel(sql, columns.end + select[0].length, /^from\b/iu).items;
      }
      const expression = (row[actionIndex] ?? "").replace(/\s+/gu, " ");
      collect(file, sql, expression, `insert into audit_log (${expression || "unparsed"})`);
    }
  }

  return { actions, unresolved };
};

/**
 * Prints the report.
 * @param {object} report - Report built by `main`.
 * @param {boolean} [summary] - Print counts and allowlist problems only.
 * @param {boolean} [blocking] - Also list the unexplained functions in a summary.
 */
const printReport = (report, summary = false, blocking = false) => {
  const { auditActions, databases, functions, since } = report;
  const list = (title, items, always = false) => {
    console.log(`  ${title}: ${items.length}`);
    for (const item of summary && !always ? [] : items) {
      console.log(`    - ${item}`);
    }
  };

  console.log(`==> DB function coverage (${databases.join(", ")})`);
  list(
    `Called functions (of ${functions.all.length})`,
    functions.all.filter(({ calls }) => calls > 0).map(({ calls, function: name }) => `${name} (${calls})`),
  );
  list("Uncalled plpgsql and trigger functions without an allowlist entry", functions.unexplained, blocking);
  console.log(
    `  Uncalled plpgsql and trigger functions allowlisted: ${functions.uncalledAllowlisted.length}`,
  );
  list("Uncalled sql functions (informational, may be inlined)", functions.uncalledInformational);
  list("Allowlist errors", functions.allowlistErrors, true);
  list("Allowlist warnings", functions.allowlistWarnings, true);

  console.log(`==> Audit actions written since ${since ?? "the seed (all rows)"}`);
  console.log(
    `  Emitted actions: ${auditActions.emitted.length} of ${auditActions.sourceCount} in the sources`,
  );
  list("Source actions not emitted", auditActions.notEmitted);
  list("Emitted actions not found in the sources", auditActions.notInSources);
  list("Unresolved source expressions", auditActions.unresolvedSources);
};

/**
 * Returns the action argument of an audit helper call: the `p_action =>` argument when named,
 * otherwise the first one.
 * @param {string[]} args - Top-level call arguments.
 * @returns {string} Action expression with collapsed whitespace.
 */
const readActionArgument = (args) => {
  const named = args.find((arg) => /^p_action\s*=>/iu.test(arg));

  return (named ?? args[0] ?? "")
    .replace(/^p_action\s*=>\s*/iu, "")
    .replace(/\s+/gu, " ")
    .trim();
};

/**
 * Reads the allowlist of uncalled functions and checks its shape.
 * @returns {AllowlistEntry[]} Allowlist entries.
 */
const readAllowlist = () => {
  const entries = JSON.parse(readFileSync(ALLOWLIST_PATH, "utf8"));
  const fields = ["coveredBy", "function", "reason"];
  const invalid = Array.isArray(entries)
    ? entries.find(
        (entry) =>
          fields.some((field) => typeof entry?.[field] !== "string" || !entry[field]) ||
          !["boolean", "undefined"].includes(typeof entry.intermittent),
      )
    : entries;

  if (invalid !== undefined) {
    throw new Error(
      `${relative(REPO_ROOT, ALLOWLIST_PATH)} must be an array of { function, reason, coveredBy } ` +
        `objects with an optional boolean intermittent (got ${JSON.stringify(invalid)})`,
    );
  }

  return entries;
};

/**
 * Counts the audit rows written since the run started.
 * @param {QueryFn} query - Runs a query on an e2e database.
 * @param {string} database - Stack database.
 * @param {string|undefined} since - Run start; every row counts when unset.
 * @returns {Map<string, number>} Row count per action.
 */
const readAuditActions = (query, database, since) => {
  const filter = since ? `where created_at >= '${since}'::timestamptz` : "";
  const output = query(
    `select action, count(*) from audit_log ${filter} group by action order by action collate "C"`,
    database,
  );

  return new Map(splitRows(output).map(([action, count]) => [action, Number(count)]));
};

/**
 * Reads the function counters and audit actions of the run's stopped stacks.
 * @param {{db?: string[], "run-dir": string, since?: string}} options - Command-line options.
 * @returns {Promise<{databases: string[], emittedActions: Map<string, number>,
 * functions: Map<string, {calls: number, kind: string}>, since: string|undefined}>} Run data.
 */
const readDatabases = async (options) => {
  const { databases, since } = resolveTargets(options);
  // Imported here because database.js requires the e2e database settings, which --merge does not.
  const { queryE2eDatabase: query } = await import("../database.js");

  // Read the counters of every stopped stack
  const perDatabase = [];
  for (const database of databases) {
    await waitForBackendsToExit(query, database);
    perDatabase.push(readFunctionCalls(query, database));
  }

  return {
    databases,
    emittedActions: mergeAuditActions(databases.map((database) => readAuditActions(query, database, since))),
    functions: mergeFunctionCalls(perDatabase),
    since,
  };
};

/**
 * Reads the call count of every public, non-extension function of a stopped stack.
 * @param {QueryFn} query - Runs a query on an e2e database.
 * @param {string} database - Stack database.
 * @returns {Map<string, {calls: number, kind: string}>} Calls and kind (`plpgsql`, `sql` or
 * `trigger`) per function.
 */
const readFunctionCalls = (query, database) => {
  const output = query(
    `select
        p.proname,
        case when p.prorettype = 'trigger'::regtype then 'trigger' else l.lanname end,
        coalesce(s.calls, 0)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
    left join pg_stat_user_functions s on s.funcid = p.oid
    where n.nspname = 'public'
    and p.prokind in ('f', 'p')
    and not exists (
        select 1
        from pg_depend d
        where d.classid = 'pg_proc'::regclass
        and d.objid = p.oid
        and d.deptype = 'e'
    )
    order by p.proname collate "C"`,
    database,
  );

  return new Map(splitRows(output).map(([name, kind, calls]) => [name, { calls: Number(calls), kind }]));
};

/**
 * Sums the reports of several runs written with --json.
 * @param {{db?: string[], merge: string[], since?: string}} options - Command-line options.
 * @returns {{databases: string[], emittedActions: Map<string, number>,
 * functions: Map<string, {calls: number, kind: string}>, since: string|undefined}} Run data.
 */
const readMergedReports = (options) => {
  if (options.db || options.since) {
    throw new Error("--merge cannot be combined with --db or --since");
  }
  const reports = options.merge.map((file) => {
    if (!existsSync(file)) {
      throw new Error(`${file} not found`);
    }
    return JSON.parse(readFileSync(file, "utf8"));
  });
  const functions = mergeFunctionCalls(
    reports.map(
      (report) =>
        new Map(report.functions.all.map(({ calls, function: name, kind }) => [name, { calls, kind }])),
    ),
  );

  return {
    databases: reports.flatMap((report) => report.databases),
    emittedActions: mergeAuditActions(
      reports.map(
        (report) => new Map(report.auditActions.emitted.map(({ action, count }) => [action, count])),
      ),
    ),
    functions: new Map([...functions].sort(([a], [b]) => (a < b ? -1 : 1))),
    since: reports
      .map((report) => report.since)
      .filter(Boolean)
      .sort()[0],
  };
};

/**
 * Parses the command-line options.
 * @returns {{blocking?: boolean, db?: string[], json?: string, merge?: string[], "run-dir": string,
 * since?: string, summary?: boolean}} Options.
 */
const readOptions = () =>
  parseArgs({
    options: {
      blocking: { type: "boolean" },
      db: { multiple: true, type: "string" },
      json: { type: "string" },
      merge: { multiple: true, type: "string" },
      "run-dir": { default: join(tmpdir(), "ocg-e2e-parallel"), type: "string" },
      since: { type: "string" },
      summary: { type: "boolean" },
    },
  }).values;

/**
 * Resolves an audit action expression to the actions it can produce.
 * @param {string} expression - Action expression with collapsed whitespace.
 * @param {string} sql - SQL source the expression appears in.
 * @returns {string[]|undefined} Actions, empty for forwarded parameters, or undefined when
 * the expression cannot be resolved.
 */
const resolveActionExpression = (expression, sql) => {
  const literal = /^'([^']+)'$/u.exec(expression);
  if (literal) {
    return [literal[1]];
  }

  // Parameters are resolved at the helper call sites
  if (/^p_\w+$/u.test(expression)) {
    return [];
  }

  if (DYNAMIC_AUDIT_ACTIONS.has(expression)) {
    return DYNAMIC_AUDIT_ACTIONS.get(expression);
  }

  let actions = [];
  if (/^case\b/iu.test(expression)) {
    actions = extractCaseLiterals(expression);
  } else if (/^v_\w+$/u.test(expression)) {
    actions = [...sql.matchAll(new RegExp(`\\b${expression}\\s*:=\\s*'([^']+)'`, "gu"))].map((m) => m[1]);
  }

  return actions.length > 0 ? actions : undefined;
};

/**
 * Lists the databases to read and the start of the audit inventory.
 * @param {{db?: string[], "run-dir": string, since?: string}} options - Command-line options.
 * @returns {{databases: string[], since: string|undefined}} Databases and run start.
 */
const resolveTargets = (options) => {
  const runDir = options["run-dir"];
  const startedAtPath = join(runDir, "run-started-at");
  let databases = options.db;

  if (!databases) {
    const stacksPath = join(runDir, "stacks.json");
    if (!existsSync(stacksPath)) {
      throw new Error(`${stacksPath} not found; run just e2e-tests-parallel first or pass --db`);
    }
    databases = JSON.parse(readFileSync(stacksPath, "utf8")).map((stack) => stack.dbName);
  }

  const since =
    options.since ??
    (!options.db && existsSync(startedAtPath) ? readFileSync(startedAtPath, "utf8").trim() : undefined);
  if (since !== undefined && !SINCE_PATTERN.test(since)) {
    throw new Error(
      `The run start must be a UTC timestamp like 2026-01-31T12:00:00.000000Z (got "${since}")`,
    );
  }

  return { databases, since };
};

/**
 * Splits unaligned psql output into rows of columns.
 * @param {string} output - Output with one row per line and `|`-separated columns.
 * @returns {string[][]} Rows, empty when there is no output.
 */
const splitRows = (output) => (output === "" ? [] : output.split("\n").map((line) => line.split("|")));

/**
 * Splits a comma-separated list at nesting depth zero. The list ends at the closing parenthesis
 * of its depth, a semicolon or, when given, a keyword at depth zero.
 * @param {string} sql - SQL source without comments.
 * @param {number} start - Offset of the first item.
 * @param {RegExp} [stopKeyword] - Anchored keyword pattern that also ends the list.
 * @returns {{end: number, items: string[]}} Trimmed items and the offset after the list.
 */
const splitTopLevel = (sql, start, stopKeyword) => {
  const items = [];
  let depth = 0;
  let itemStart = start;

  for (let index = start; index < sql.length; index += 1) {
    const char = sql[index];
    const atKeyword =
      stopKeyword && /\s/u.test(sql[index - 1]) && stopKeyword.test(sql.slice(index, index + 32));

    if (char === "'") {
      index = sql.indexOf("'", index + 1);
      if (index === -1) {
        break;
      }
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")" && depth > 0) {
      depth -= 1;
    } else if (depth === 0 && (char === ")" || char === ";" || atKeyword)) {
      items.push(sql.slice(itemStart, index).trim());
      return { end: char === ")" ? index + 1 : index, items };
    } else if (depth === 0 && char === ",") {
      items.push(sql.slice(itemStart, index).trim());
      itemStart = index + 1;
    }
  }
  items.push(sql.slice(itemStart).trim());

  return { end: sql.length, items };
};

/**
 * Removes `--` comments from SQL, keeping string literals intact.
 * @param {string} sql - SQL source.
 * @returns {string} SQL without line comments.
 */
const stripSqlComments = (sql) =>
  sql.replace(/('(?:[^']|'')*')|--[^\n]*/gu, (match, literal) => literal ?? "");

/**
 * Waits until no other backend is connected to a database, so its statistics are flushed.
 * @param {QueryFn} query - Runs a query on an e2e database.
 * @param {string} database - Stack database.
 * @returns {Promise<void>} Resolves when the database is idle or after a warning on timeout.
 */
const waitForBackendsToExit = async (query, database) => {
  const deadline = Date.now() + BACKEND_EXIT_TIMEOUT_MS;
  const sql = `select count(*) from pg_stat_activity
    where datname = current_database() and pid <> pg_backend_pid()`;

  while (Number(query(sql, database)) > 0) {
    if (Date.now() > deadline) {
      console.warn(`warning: ${database} still has connections; its function counts may be incomplete`);
      return;
    }
    await delay(BACKEND_EXIT_POLL_MS);
  }
};

try {
  await main();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}
