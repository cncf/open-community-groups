import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { playwrightLauncher } from "@web/test-runner-playwright";

const configDir = dirname(fileURLToPath(import.meta.url));
const repoRootDir = resolve(configDir, "../..");
const litBundlePath = "/static/vendor/js/lit-all.v3.3.3.min.js";
const litDevModeWarningUrl = "lit.dev/msg/dev-mode";
const litImportSpecifiers = new Set([
  "lit",
  "lit/directives/ref.js",
  "lit/directives/repeat.js",
  "lit/directives/unsafe-html.js",
]);

const litImportMapResolver = {
  name: "lit-import-map-resolver",
  resolveImport: ({ source, context }) => {
    const isRepositoryModule =
      context.path.startsWith("/ocg-server/static/js/") || context.path.startsWith("/tests/unit/");

    // Keep package imports on nodeResolve so Open WC retains its own Lit instance.
    if (!isRepositoryModule || !litImportSpecifiers.has(source)) {
      return undefined;
    }

    return litBundlePath;
  },
};

/**
 * Creates a Chromium launcher with the shared locale and an optional timezone.
 * @param {string|undefined} timezoneId - IANA timezone emulated by the browser.
 * @returns {import("@web/test-runner").BrowserLauncher} Browser launcher.
 */
const createChromiumLauncher = (timezoneId) =>
  playwrightLauncher({
    product: "chromium",
    createBrowserContext: ({ browser }) => browser.newContext({ locale: "en-US", timezoneId }),
  });

// Chart bucket helpers must produce the same UTC days in every browser timezone.
const chartTimezoneGroups = ["Pacific/Auckland", "America/Los_Angeles"].map((timezoneId) => ({
  name: `chart-config-${timezoneId.toLowerCase().replace("/", "-").replaceAll("_", "-")}`,
  files: `${repoRootDir}/tests/unit/dashboard/chart-config.test.js`,
  browsers: [createChromiumLauncher(timezoneId)],
}));

const importMap = JSON.stringify({
  imports: {
    "/static/": "/ocg-server/static/",
  },
});

export default {
  rootDir: repoRootDir,
  files: `${repoRootDir}/tests/unit/**/*.test.js`,
  filterBrowserLogs: ({ args }) =>
    !args.some((argument) => typeof argument === "string" && argument.includes(litDevModeWarningUrl)),
  hostname: "127.0.0.1",
  nodeResolve: true,
  plugins: [litImportMapResolver],
  browsers: [createChromiumLauncher()],
  groups: chartTimezoneGroups,
  testRunnerHtml: (testFrameworkImport) => `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <script type="importmap">${importMap}</script>
  </head>
  <body>
    <script type="module" src="${testFrameworkImport}"></script>
  </body>
</html>`,
};
