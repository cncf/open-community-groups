import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import * as path from "node:path";

// Centralize direct E2E database access used by workflows that inspect or reset fixtures.

/**
 * Runs a SQL query through `psql` and returns machine-readable output.
 * @param {string} sql - Query to execute.
 * @returns {string} Trimmed query output.
 */
export const queryE2eDatabase = (sql) => {
  return execFileSync(
    getPsqlPath(),
    [
      "-h",
      e2eDbConfig.host,
      "-p",
      e2eDbConfig.port,
      "-U",
      e2eDbConfig.user,
      "-d",
      e2eDbConfig.database,
      // Suppress headers, alignment, and command status so callers receive only
      // query values.
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
 * Resolves connection settings with environment variables taking precedence.
 * @returns {object} Complete PostgreSQL connection settings for the E2E database.
 */
const getDbConfig = () => {
  const serverDbConfig = readServerDbConfig();

  return {
    host: process.env.OCG_DB_HOST ?? serverDbConfig.host ?? "localhost",
    port: process.env.OCG_DB_PORT ?? serverDbConfig.port ?? "5432",
    user: process.env.OCG_DB_USER ?? serverDbConfig.user ?? "postgres",
    password: process.env.OCG_DB_PASSWORD ?? serverDbConfig.password ?? "",
    database:
      process.env.OCG_DB_NAME_TESTS_E2E ??
      serverDbConfig.database ??
      process.env.OCG_DB_NAME ??
      "ocg_tests_e2e",
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

/**
 * Removes matching YAML quotes from a simple scalar value.
 * @param {string} value - Scalar text read from the server configuration.
 * @returns {string} Unquoted scalar value.
 */
const parseYamlScalar = (value) => {
  const trimmedValue = value.trim();

  if (
    (trimmedValue.startsWith('"') && trimmedValue.endsWith('"')) ||
    (trimmedValue.startsWith("'") && trimmedValue.endsWith("'"))
  ) {
    return trimmedValue.slice(1, -1);
  }

  return trimmedValue;
};

/**
 * Reads the database section from the local E2E server configuration.
 * @returns {object} Connection settings found in the configuration file.
 */
const readServerDbConfig = () => {
  const configDir = process.env.OCG_CONFIG || path.join(process.env.HOME || "", ".config/ocg");
  const serverConfigPath = path.join(configDir, "server-tests-e2e.yml");

  if (!existsSync(serverConfigPath)) {
    return {};
  }

  const config = readFileSync(serverConfigPath, "utf8");
  const dbConfig = {};
  let dbSectionIndent = -1;

  for (const line of config.split(/\r?\n/u)) {
    const trimmedLine = line.trim();

    if (!trimmedLine || trimmedLine.startsWith("#")) {
      continue;
    }

    const indent = line.length - line.trimStart().length;

    // Ignore document content until the top-level database section begins.
    if (dbSectionIndent === -1) {
      if (trimmedLine === "db:") {
        dbSectionIndent = indent;
      }

      continue;
    }

    // Stop parsing when indentation indicates that the database section ended.
    if (indent <= dbSectionIndent && /^[A-Za-z0-9_-]+:/u.test(trimmedLine)) {
      break;
    }

    const match = trimmedLine.match(/^(host|port|dbname|user|password):\s*(.+)$/u);

    if (!match) {
      continue;
    }

    const [, key, rawValue] = match;
    const parsedValue = parseYamlScalar(rawValue);

    switch (key) {
      case "host":
        dbConfig.host = parsedValue;
        break;
      case "port":
        dbConfig.port = parsedValue;
        break;
      case "dbname":
        dbConfig.database = parsedValue;
        break;
      case "user":
        dbConfig.user = parsedValue;
        break;
      case "password":
        dbConfig.password = parsedValue;
        break;
    }
  }

  return dbConfig;
};

// Resolve configuration once so polling queries reuse the same connection settings.
const e2eDbConfig = getDbConfig();
