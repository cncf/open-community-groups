import { playwrightLauncher } from "@web/test-runner-playwright";

const importMap = JSON.stringify({
  imports: {
    "/static/": "/ocg-server/static/",
  },
});

export default {
  rootDir: ".",
  files: "tests/unit/**/*.test.js",
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
