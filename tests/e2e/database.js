import { execFileSync } from "node:child_process";

// Centralize direct E2E database access used by tests and data graphs that inspect or reset fixtures.
// Connection settings come exclusively from the `OCG_E2E_DB_*` contract exported by the
// justfile so psql, tern, the server, and Playwright always target the same database.

const E2E_DB_NAME_SUFFIX = "_e2e";
const REQUIRED_ENV_VARS = ["OCG_E2E_DB_HOST", "OCG_E2E_DB_NAME", "OCG_E2E_DB_PORT", "OCG_E2E_DB_USER"];

/**
 * Runs a SQL statement through `psql` and returns the raw unaligned output.
 * @param {string} sql - Statement to execute.
 * @returns {string} Trimmed output with one row per line and `|`-separated columns.
 */
export const queryE2eDatabase = (sql) => {
  return execFileSync(
    getPsqlPath(),
    [
      "-X",
      "-v",
      "ON_ERROR_STOP=1",
      "-h",
      e2eDbConfig.host,
      "-p",
      e2eDbConfig.port,
      "-U",
      e2eDbConfig.user,
      "-d",
      e2eDbConfig.database,
      // Suppress headers, alignment, and command status so callers receive only values.
      "-qtA",
      "-c",
      sql,
    ],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        // Keep the password out of the process arguments displayed by system tools.
        PGPASSWORD: e2eDbConfig.password,
      },
    },
  ).trim();
};

/**
 * Runs a SQL query and returns each result row as an array of column strings.
 * @param {string} sql - Query to execute.
 * @returns {string[][]} Rows split on the unaligned `|` separator; empty when nothing matched.
 */
export const queryE2eDatabaseRows = (sql) => {
  const output = queryE2eDatabase(sql);

  if (output === "") {
    return [];
  }

  return output.split("\n").map((line) => line.split("|"));
};

/**
 * Resolves connection settings from the environment contract, failing closed when incomplete.
 * @returns {object} Complete PostgreSQL connection settings for the E2E database.
 */
const getDbConfig = () => {
  const missing = REQUIRED_ENV_VARS.filter((name) => !process.env[name]);

  if (missing.length > 0) {
    throw new Error(
      `Missing E2E database settings: ${missing.join(", ")}. Run the suite through \`just e2e-tests\`.`,
    );
  }

  const database = process.env.OCG_E2E_DB_NAME;

  // Refuse to touch anything that is not clearly an e2e database.
  if (!database.endsWith(E2E_DB_NAME_SUFFIX)) {
    throw new Error(`OCG_E2E_DB_NAME must end in "${E2E_DB_NAME_SUFFIX}" (got "${database}")`);
  }

  return {
    database,
    host: process.env.OCG_E2E_DB_HOST,
    password: process.env.OCG_E2E_DB_PASSWORD ?? "",
    port: process.env.OCG_E2E_DB_PORT,
    user: process.env.OCG_E2E_DB_USER,
  };
};

/**
 * Locates `psql` from the configured PostgreSQL binary directory.
 * @returns {string} Executable path or the command resolved from `PATH`.
 */
const getPsqlPath = () => {
  const pgBin = process.env.OCG_PG_BIN;

  return pgBin ? `${pgBin}/psql` : "psql";
};

// Resolve configuration once so polling queries reuse the same connection settings.
const e2eDbConfig = getDbConfig();
