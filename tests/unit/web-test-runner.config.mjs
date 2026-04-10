import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { playwrightLauncher } from "@web/test-runner-playwright";

const configDir = dirname(fileURLToPath(import.meta.url));
const repoRootDir = resolve(configDir, "../..");

const importMap = JSON.stringify({
  imports: {
    "/static/": "/ocg-server/static/",
  },
});

export default {
  rootDir: repoRootDir,
  files: `${repoRootDir}/tests/unit/**/*.test.js`,
  hostname: "127.0.0.1",
  nodeResolve: true,
  browsers: [playwrightLauncher({ product: "chromium" })],
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
