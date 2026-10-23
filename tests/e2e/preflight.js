import { queryE2eDatabase } from "./database.js";
import { getE2eStacks } from "./stacks.js";

// Global setup that aborts the run unless each application server and its psql target are the
// same database. `/health-check` only proves readiness; the identity check compares a
// per-reset marker written by `just e2e-db-mark` through an uncached public group page.

const BASE_URL = process.env.OCG_E2E_BASE_URL || "http://127.0.0.1:9001";
const HEALTH_CHECK_ATTEMPTS = 60;
const HEALTH_CHECK_RETRY_DELAY_MS = 1_000;
// External Payments Lab: active, publicly rendered and uncached, so the description is live.
const MARKER_GROUP_ID = "44444444-4444-4444-4444-444444444448";
const MARKER_GROUP_PATH = "/e2e-test-community/group/external-payments-lab";
const MARKER_PATTERN = /E2E seed run [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/u;

/**
 * Verifies server readiness and cross-boundary database identity before any test runs.
 * @param {import("@playwright/test").FullConfig} config - Resolved config, including `--workers`.
 * @returns {Promise<void>} Resolves when every stack passes; throws with diagnostics otherwise.
 */
const preflight = async (config) => {
  const stacks = getE2eStacks();

  // Each worker needs a stack of its own, so fail once here instead of in every worker.
  if (stacks.length > 0 && config.workers > stacks.length) {
    throw new Error(
      [
        `E2E preflight failed: ${config.workers} workers requested but only ${stacks.length} stacks are running.`,
        `Pass --workers ${stacks.length} or fewer, or set OCG_E2E_PARALLEL_WORKERS=${config.workers}.`,
      ].join("\n"),
    );
  }

  const targets = stacks.length > 0 ? stacks : [{ baseUrl: BASE_URL, dbName: process.env.OCG_E2E_DB_NAME }];

  for (const target of targets) {
    await checkStack(target);
  }
};

/**
 * Verifies that one server is ready and renders the marker of the database psql reads.
 * @param {{baseUrl: string, dbName: string}} target - Server base URL and its database name.
 * @returns {Promise<void>} Resolves when both checks pass; throws with diagnostics otherwise.
 */
const checkStack = async ({ baseUrl, dbName }) => {
  await waitForServerReadiness(baseUrl);

  // Compare the marker as rendered by the application with the marker psql sees.
  const renderedMarker = await readRenderedMarker(baseUrl);
  const databaseMarker = readDatabaseMarker(dbName);

  if (!renderedMarker || !databaseMarker || renderedMarker !== databaseMarker) {
    throw new Error(
      [
        "E2E preflight failed: the server and psql do not target the same seeded database.",
        `  server (${baseUrl}${MARKER_GROUP_PATH}): ${renderedMarker ?? "<marker missing>"}`,
        `  psql (${dbName}): ${databaseMarker ?? "<marker missing>"}`,
        "Run `just e2e-db-reset` and start the server with `just e2e-server`, or rerun `just e2e-tests-parallel`.",
      ].join("\n"),
    );
  }
};

/**
 * Reads the marker stored in the External Payments Lab group description via psql.
 * @param {string} dbName - E2E database to read.
 * @returns {string|null} Marker text or null when the description is not a marker.
 */
const readDatabaseMarker = (dbName) => {
  const description = queryE2eDatabase(
    `select description from "group" where group_id = '${MARKER_GROUP_ID}'`,
    dbName,
  );

  return description.match(MARKER_PATTERN)?.[0] ?? null;
};

/**
 * Reads the marker from the public group page rendered by the application server.
 * @param {string} baseUrl - Server base URL.
 * @returns {Promise<string|null>} Marker text or null when the page does not render one.
 */
const readRenderedMarker = async (baseUrl) => {
  const response = await fetch(new URL(MARKER_GROUP_PATH, baseUrl));

  if (!response.ok) {
    throw new Error(`E2E preflight failed: GET ${MARKER_GROUP_PATH} returned ${response.status}`);
  }

  const html = await response.text();

  return html.match(MARKER_PATTERN)?.[0] ?? null;
};

/**
 * Polls the readiness endpoint until the server answers, tolerating startup delays.
 * @param {string} baseUrl - Server base URL.
 * @returns {Promise<void>} Resolves once `/health-check` returns 200.
 */
const waitForServerReadiness = async (baseUrl) => {
  let lastError;

  for (let attempt = 1; attempt <= HEALTH_CHECK_ATTEMPTS; attempt += 1) {
    try {
      const response = await fetch(new URL("/health-check", baseUrl));

      if (response.ok) {
        return;
      }

      lastError = new Error(`health-check returned ${response.status}`);
    } catch (error) {
      lastError = error;
    }

    await new Promise((resolve) => {
      setTimeout(resolve, HEALTH_CHECK_RETRY_DELAY_MS);
    });
  }

  throw new Error(`E2E preflight failed: server at ${baseUrl} is not ready`, { cause: lastError });
};

export default preflight;
