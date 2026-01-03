import * as path from "node:path";
import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.OCG_E2E_BASE_URL || "http://localhost:9000";
const shouldStartServer = process.env.OCG_E2E_START_SERVER === "true";
const webServerCommand = process.env.OCG_E2E_SERVER_CMD;
const reportDir = path.resolve(__dirname, "../../playwright-report");
const resultsDir = path.resolve(__dirname, "../../test-results");

const webServer =
  shouldStartServer && webServerCommand
    ? {
        command: webServerCommand,
        url: baseURL,
        reuseExistingServer: true,
        timeout: 120_000,
      }
    : undefined;

export default defineConfig({
  testDir: __dirname,
  fullyParallel: false,
  workers: 1,
  reporter: [["html", { open: "never", outputFolder: reportDir }], ["list"]],
  outputDir: resultsDir,
  use: {
    baseURL,
    trace: "on-first-retry",
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
