import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";

// Centralize direct E2E database access used by tests and data graphs that inspect or reset fixtures.
// Connection settings come exclusively from the `OCG_E2E_DB_*` contract exported by the
// justfile so psql, tern, the server, and Playwright always target the same database.

const E2E_DB_NAME_SUFFIX = "_e2e";
const REQUIRED_ENV_VARS = ["OCG_E2E_DB_HOST", "OCG_E2E_DB_NAME", "OCG_E2E_DB_PORT", "OCG_E2E_DB_USER"];

// Tables whose seeded rows hold plain columns that a single-row restore can put back. An `event`
// restore only covers the event row an editor save rewrites, not its sessions or ticketing.
// Lifecycle tables (attendees, offers, purchases) have triggers and dependent rows, so they need
// targeted SQL resets instead.
const ROW_RESTORE_TABLES = new Set([
  "community",
  "community_team",
  "event",
  "group",
  "group_sponsor",
  "group_team",
  "user",
]);

/**
 * Reads the month the seed was loaded in, so month-relative assertions follow the seed instead
 * of the test runner's clock (a run that crosses a month boundary keeps passing).
 * @param {string} eventId - Seeded event dated relative to the seed month, such as
 * `TEST_CALENDAR_EVENTS.thisMonth.id`.
 * @returns {{ monthStart: Date }} UTC midnight of the first day of the event's UTC month.
 */
export const getSeedClock = (eventId) => {
  const monthStart = queryScalar(`
    select to_char(date_trunc('month', starts_at at time zone 'UTC'), 'YYYY-MM-DD')
    from event
    where event_id = ${sqlUuid(eventId)}
  `);
  if (monthStart === "") {
    throw new Error(`Seed clock event ${eventId} was not found`);
  }

  return { monthStart: new Date(`${monthStart}T00:00:00Z`) };
};

/**
 * Runs a SQL statement through `psql` and returns the raw unaligned output.
 * @param {string} sql - Statement to execute.
 * @param {string} [database] - E2E database to query instead of `OCG_E2E_DB_NAME`.
 * @returns {string} Trimmed output with one row per line and `|`-separated columns.
 */
export const queryE2eDatabase = (sql, database = e2eDbConfig.database) => {
  assertE2eDatabaseName(database);

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
      database,
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
 * Runs a scalar SQL query and returns its value as a number.
 * @param {string} sql - Query whose first column of the first row is numeric, such as `count(*)`.
 * @returns {number} Parsed value; `0` when the query returned no rows.
 */
export const queryCount = (sql) => Number(queryScalar(sql));

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
 * Runs a SQL query and returns the first column of its first row.
 * @param {string} sql - Query to execute.
 * @returns {string} Raw value; empty when the query returned no rows.
 */
export const queryScalar = (sql) => queryE2eDatabaseRows(sql).at(0)?.at(0) ?? "";

/**
 * Writes a row snapshot back over the current row, skipping the update when nothing changed.
 * @param {{ key: object, rowJson: string, table: string }} snapshot - Value returned by `snapshotRow`.
 */
export const restoreRow = ({ key, rowJson, table }) => {
  assertRowRestoreTable(table);

  const columns = getRestorableColumns(table, Object.keys(key));
  if (columns.length === 0) {
    return;
  }

  // A random tag keeps the snapshot from closing its own dollar quote.
  const tag = `$row_${randomBytes(8).toString("hex")}$`;
  const targetColumns = columns.join(", ");
  const snapshotColumns = columns.map((column) => `s.${column}`).join(", ");
  const currentColumns = columns.map((column) => `t.${column}`).join(", ");

  queryE2eDatabase(`
    update ${sqlIdentifier(table)} t
    set (${targetColumns}) = row(${snapshotColumns})
    from jsonb_populate_record(null::${sqlIdentifier(table)}, ${tag}${rowJson}${tag}::jsonb) s
    where ${getRowKeyCondition("t", key)}
    and row(${currentColumns}) is distinct from row(${snapshotColumns})
  `);
};

/**
 * Captures one seeded row so `restoreRow` can put its column values back.
 * @param {{ key: object, table: string }} target - Allowlisted table and the column values that
 * identify exactly one row, such as `{ group_id: "…" }`.
 * @returns {{ key: object, rowJson: string, table: string }} Snapshot holding the row as JSON.
 */
export const snapshotRow = ({ key, table }) => {
  assertRowRestoreTable(table);

  const output = queryE2eDatabase(`
    select to_jsonb(t)::text
    from ${sqlIdentifier(table)} t
    where ${getRowKeyCondition("t", key)}
  `);

  // jsonb text output escapes newlines, so each matched row is one line.
  const rows = output === "" ? [] : output.split("\n");
  if (rows.length !== 1) {
    throw new Error(`Expected one ${table} row for ${JSON.stringify(key)} (got ${rows.length})`);
  }

  return { key: { ...key }, rowJson: rows[0], table };
};

/**
 * Quotes a value as a SQL string literal, doubling embedded single quotes.
 * @param {*} value - Value converted with `String()` before quoting.
 * @returns {string} Literal such as `'it''s'`; append a cast for non-text columns.
 */
export const sqlString = (value) => `'${String(value).replaceAll("'", "''")}'`;

/**
 * Builds a SQL `text[]` array literal.
 * @param {*[]} values - Values quoted with `sqlString`.
 * @returns {string} Typed array expression, valid when `values` is empty.
 */
export const sqlTextArray = (values) => `array[${values.map(sqlString).join(", ")}]::text[]`;

/**
 * Quotes a value as a SQL uuid literal.
 * @param {string} value - UUID string.
 * @returns {string} Literal such as `'…'::uuid`.
 */
export const sqlUuid = (value) => `${sqlString(value)}::uuid`;

/**
 * Builds a SQL `uuid[]` array literal for `any(...)` and `unnest(...)`.
 * @param {string[]} values - UUID strings quoted with `sqlUuid`.
 * @returns {string} Typed array expression, valid when `values` is empty.
 */
export const sqlUuidArray = (values) => `array[${values.map(sqlUuid).join(", ")}]::uuid[]`;

/**
 * Runs `fn` and restores the row's snapshot afterwards, even when `fn` throws.
 * @param {{ key: object, table: string }} target - Row to snapshot, as accepted by `snapshotRow`.
 * @param {Function} fn - Possibly async callback that mutates the row.
 * @returns {Promise<*>} Value returned by `fn`.
 */
export const withRowRestore = async (target, fn) => {
  const snapshot = snapshotRow(target);

  try {
    return await fn();
  } finally {
    restoreRow(snapshot);
  }
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
  assertE2eDatabaseName(database);

  return {
    database,
    host: process.env.OCG_E2E_DB_HOST,
    password: process.env.OCG_E2E_DB_PASSWORD ?? "",
    port: process.env.OCG_E2E_DB_PORT,
    user: process.env.OCG_E2E_DB_USER,
  };
};

/**
 * Refuses to touch anything that is not clearly an e2e database.
 * @param {string} database - Database name to check.
 */
const assertE2eDatabaseName = (database) => {
  if (!database.endsWith(E2E_DB_NAME_SUFFIX)) {
    throw new Error(`E2E database name must end in "${E2E_DB_NAME_SUFFIX}" (got "${database}")`);
  }
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
 * Rejects tables outside the row-restore allowlist.
 * @param {string} table - Table name to check.
 */
const assertRowRestoreTable = (table) => {
  if (!ROW_RESTORE_TABLES.has(table)) {
    throw new Error(
      `Row restore does not support table "${table}"; reset lifecycle tables with targeted SQL`,
    );
  }
};

/**
 * Lists the columns a row restore may write, excluding key, dropped, generated and identity
 * columns.
 * @param {string} table - Allowlisted table name.
 * @param {string[]} keyColumns - Columns that identify the row.
 * @returns {string[]} Quoted column identifiers in table order.
 */
const getRestorableColumns = (table, keyColumns) => {
  const output = queryE2eDatabase(`
    select quote_ident(attname)
    from pg_attribute
    where attrelid = ${sqlString(sqlIdentifier(table))}::regclass
    and attnum > 0
    and not attisdropped
    and attgenerated = ''
    and attidentity = ''
    and attname <> all(${sqlTextArray(keyColumns)})
    order by attnum
  `);

  return output === "" ? [] : output.split("\n");
};

/**
 * Builds the SQL condition matching a row by its key column values.
 * @param {string} alias - Table alias used in the statement.
 * @param {object} key - Column values that identify the row.
 * @returns {string} Condition joined with `and`.
 */
const getRowKeyCondition = (alias, key) => {
  const entries = Object.entries(key);
  if (entries.length === 0) {
    throw new Error("Row restore key needs at least one column");
  }

  return entries
    .map(([column, value]) => `${alias}.${sqlIdentifier(column)} = ${sqlString(value)}`)
    .join(" and ");
};

/**
 * Quotes a SQL identifier, doubling embedded double quotes.
 * @param {string} name - Table or column name.
 * @returns {string} Identifier such as `"group"`.
 */
const sqlIdentifier = (name) => `"${String(name).replaceAll('"', '""')}"`;

// Resolve configuration once so polling queries reuse the same connection settings.
const e2eDbConfig = getDbConfig();
