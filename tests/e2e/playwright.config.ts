import * as path from "node:path";
import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.OCG_E2E_BASE_URL || "http://localhost:9000";
const isCI = process.env.CI === "true";
const shouldStartServer = process.env.OCG_E2E_START_SERVER === "true";
const webServerCommand = process.env.OCG_E2E_SERVER_CMD;
const webServerTimeout = Number(process.env.OCG_E2E_SERVER_TIMEOUT || 300_000);
const webServerCwd = path.resolve(__dirname, "../..");
const reportDir = path.resolve(__dirname, "../../playwright-report");
const resultsDir = path.resolve(__dirname, "../../test-results");

const webServer =
  shouldStartServer && webServerCommand
    ? {
        command: webServerCommand,
        cwd: webServerCwd,
        url: baseURL,
        reuseExistingServer: true,
        timeout: webServerTimeout,
      }
    : undefined;

export default defineConfig({
  testDir: __dirname,
  fullyParallel: false,
  workers: 1,
  retries: isCI ? 2 : 0,
  reporter: [["html", { open: "never", outputFolder: reportDir }], ["list"]],
  outputDir: resultsDir,
  use: {
    baseURL,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "firefox",
      use: { ...devices["Desktop Firefox"] },
    },
    {
      name: "webkit",
      use: { ...devices["Desktop Safari"] },
    },
  ],
  webServer,
});
