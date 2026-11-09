import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { playwrightLauncher } from "@web/test-runner-playwright";

const configDir = dirname(fileURLToPath(import.meta.url));
const repoRootDir = resolve(configDir, "../..");
// URL path prefix of the app modules whose raw V8 coverage is kept.
const appModulesPathPrefix = "/ocg-server/static/js/";
// Coverage reports of `--coverage` runs: the lcov report and the raw V8 coverage under raw/.
const coverageDir = resolve(configDir, "coverage");
const rawCoverageDir = join(coverageDir, "raw");
const baseTemplatePath = join(repoRootDir, "ocg-server/templates/common/base.html");
const litDevModeWarningUrl = "lit.dev/msg/dev-mode";
const litImportSpecifiers = new Set([
  "lit",
  "lit/directives/ref.js",
  "lit/directives/repeat.js",
  "lit/directives/unsafe-html.js",
]);
// URL path of the module that exposes the vendor bundle manifest to the tests. It sits outside the
// served repository tree so it cannot shadow a repository file.
const vendorBundlesModulePath = "/__ocg__/vendor-bundles.js";

/**
 * Builds the vendored bundle manifest from the base template, so a vendor upgrade only touches
 * common/base.html. Classic vendor scripts are keyed by the file name before `.v`, and `lit` comes
 * from the import map.
 * @param {string} templatePath - Path of the base template.
 * @returns {Record<string, string>} Bundle URL paths keyed by vendor name.
 */
const readVendorBundles = (templatePath) => {
  const template = readFileSync(templatePath, "utf8");
  const bundles = {};

  for (const [, path, name] of template.matchAll(
    /<script src="(\/static\/vendor\/js\/([a-z0-9-]+)\.v[\d.]+\.min\.js)">/g,
  )) {
    bundles[name] = path;
  }

  const importMapJson = template.match(/<script type="importmap">([\s\S]*?)<\/script>/)?.[1];
  if (importMapJson) {
    bundles.lit = JSON.parse(importMapJson).imports?.lit;
  }

  for (const key of ["htmx", "lit", "sweetalert2"]) {
    if (!bundles[key]) {
      throw new Error(`Vendor bundle "${key}" not found in ${templatePath}`);
    }
  }

  return bundles;
};

const vendorBundles = readVendorBundles(baseTemplatePath);

const litImportMapResolver = {
  name: "lit-import-map-resolver",
  resolveImport: ({ source, context }) => {
    const isRepositoryModule =
      context.path.startsWith("/ocg-server/static/js/") || context.path.startsWith("/tests/unit/");

    // Keep package imports on nodeResolve so Open WC retains its own Lit instance.
    if (!isRepositoryModule || !litImportSpecifiers.has(source)) {
      return undefined;
    }

    return vendorBundles.lit;
  },
};

const vendorBundlesModule = {
  name: "vendor-bundles-module",
  serve: (context) => {
    if (context.path !== vendorBundlesModulePath) {
      return undefined;
    }

    return {
      body: `export const VENDOR_BUNDLES = Object.freeze(${JSON.stringify(vendorBundles)});`,
      type: "js",
    };
  },
};

// Raw coverage files written by this run.
let rawCoverageFileCount = 0;

// A coverage run replaces the raw coverage of the previous one.
if (process.argv.includes("--coverage")) {
  rmSync(rawCoverageDir, { force: true, recursive: true });
}

/**
 * Writes the app module entries of a page's V8 coverage to coverage/raw/ for
 * tests/e2e/scripts/js-coverage-report.js, which merges them with the e2e coverage.
 * @param {object[]} entries - V8 script coverage returned by Playwright.
 */
const writeRawCoverage = (entries) => {
  const appEntries = entries
    .map(({ functions, source, url }) => ({ functions, source, url: new URL(url).pathname }))
    .filter(({ url }) => url.startsWith(appModulesPathPrefix));

  if (appEntries.length === 0) {
    return;
  }
  rawCoverageFileCount += 1;
  mkdirSync(rawCoverageDir, { recursive: true });
  writeFileSync(join(rawCoverageDir, `unit-${rawCoverageFileCount}.json`), JSON.stringify(appEntries));
};

/**
 * Creates a test page. With `--coverage`, the V8 coverage the launcher reads from the page is also
 * written as raw JSON, since the launcher only keeps its Istanbul conversion.
 * @param {{config: import("@web/test-runner").TestRunnerConfig, context: import("playwright").BrowserContext}} args -
 * Test runner configuration and the session's browser context.
 * @returns {Promise<import("playwright").Page>} Test page.
 */
const createCoveragePage = async ({ config, context }) => {
  const page = await context.newPage();

  if (config.coverage) {
    const stopJSCoverage = page.coverage.stopJSCoverage.bind(page.coverage);
    page.coverage.stopJSCoverage = async () => {
      const entries = await stopJSCoverage();
      writeRawCoverage(entries);
      return entries;
    };
  }

  return page;
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
    createPage: createCoveragePage,
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
  plugins: [litImportMapResolver, vendorBundlesModule],
  browsers: [createChromiumLauncher()],
  // Only used with --coverage (just e2e-js-coverage).
  coverageConfig: {
    include: [`${repoRootDir}/ocg-server/static/js/**/*.js`],
    reportDir: coverageDir,
  },
  groups: chartTimezoneGroups,
  testRunnerHtml: (testFrameworkImport) => `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <script type="importmap">${importMap}</script>
    <script>
      // Browsers emit a benign "ResizeObserver loop" notification when an observer
      // callback mutates layout (as the agenda badge clamp does). Suppress it here,
      // before the Mocha harness installs window.onerror, so it is not reported as
      // an uncaught test failure. Registered first and in the capture phase, this
      // listener stops the notification from reaching that handler.
      window.addEventListener(
        "error",
        (event) => {
          if (
            event.message === "ResizeObserver loop completed with undelivered notifications." ||
            event.message === "ResizeObserver loop limit exceeded"
          ) {
            event.stopImmediatePropagation();
            event.preventDefault();
          }
        },
        true,
      );
    </script>
  </head>
  <body>
    <script type="module" src="${testFrameworkImport}"></script>
  </body>
</html>`,
};
