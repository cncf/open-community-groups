import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, devices } from "@playwright/test";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** Base URL used by browser contexts and the optional web server health check. */
const baseURL = process.env.OCG_E2E_BASE_URL || "http://127.0.0.1:9001";
/** Enables CI-specific retries and screenshot tolerance when running in CI. */
const isCI = process.env.CI === "true";
/** Starts the application server as part of the Playwright run when requested. */
const shouldStartServer = process.env.OCG_E2E_START_SERVER === "true";
/** Reuses an already running app server instead of booting a new one. */
const shouldReuseExistingServer = process.env.OCG_E2E_REUSE_SERVER === "true";
/** Command used to start the application server before the suite begins. */
const webServerCommand = process.env.OCG_E2E_SERVER_CMD;
/** Maximum time to wait for the application server to become reachable. */
const webServerTimeout = Number(process.env.OCG_E2E_SERVER_TIMEOUT || 300_000);
/** Repository root used as the working directory for the server command. */
const webServerCwd = path.resolve(__dirname, "../..");
/** Output folder for Playwright's HTML report. */
const reportDir = path.resolve(__dirname, "playwright-report");
/** Output folder for Playwright artifacts such as traces and videos. */
const resultsDir = path.resolve(__dirname, "test-results");
/** Fast cross-browser specs that make up the smoke projects. */
const smokeSpecPaths = [
  "dashboard/home/home.spec.js",
  "dashboard/user/my-events/my-events.spec.js",
  "site/common/header.spec.js",
  "site/home/home.spec.js",
];
/** Matches visual regression specs that live next to the pages they cover. */
const visualSpecPattern = /(^|\/)[^/]+_visual\.spec\.js$/u;
/** Detects visual-only runs so deep projects ignore the right specs. */
const isVisualOnlyRun = process.argv.some(
  (arg) => visualSpecPattern.test(arg) || arg.includes("@visual"),
);
/** Visual runs need a deterministic browser environment for stable snapshots. */
const visualUseOverrides = isVisualOnlyRun
  ? {
      colorScheme: "light",
      locale: "en-US",
      reducedMotion: "reduce",
      timezoneId: "UTC",
    }
  : {};
/** Matches tests that should only execute in the mobile project. */
const mobileTestPattern = /@mobile/;

const webServer =
  shouldStartServer && webServerCommand
    ? {
        command: webServerCommand,
        cwd: webServerCwd,
        url: baseURL,
        reuseExistingServer: shouldReuseExistingServer,
        timeout: webServerTimeout,
      }
    : undefined;

export default defineConfig({
  testDir: __dirname,
  fullyParallel: false,
  workers: 1,
  retries: isCI ? 2 : 0,
  expect: {
    toHaveScreenshot: isCI ? { maxDiffPixelRatio: 0.03 } : undefined,
  },
  reporter: [["html", { open: "never", outputFolder: reportDir }], ["list"]],
  outputDir: resultsDir,
  snapshotPathTemplate:
    "{testFileDir}/{testFileName}-snapshots/{arg}-{projectName}{ext}",
  use: {
    baseURL,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium-smoke",
      testMatch: smokeSpecPaths,
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "firefox-smoke",
      testMatch: smokeSpecPaths,
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Firefox"] },
    },
    {
      name: "webkit-smoke",
      testMatch: smokeSpecPaths,
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Safari"] },
    },
    {
      name: "chromium-deep",
      testIgnore: isVisualOnlyRun
        ? smokeSpecPaths
        : [...smokeSpecPaths, visualSpecPattern],
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Chrome"], ...visualUseOverrides },
    },
    {
      name: "chromium-mobile-deep",
      testIgnore: isVisualOnlyRun
        ? smokeSpecPaths
        : [...smokeSpecPaths, visualSpecPattern],
      grep: mobileTestPattern,
      use: { ...devices["iPhone 12"], ...visualUseOverrides },
    },
  ],
  webServer,
});
