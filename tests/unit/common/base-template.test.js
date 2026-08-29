import { expect } from "@open-wc/testing";

const litBundlePath = "/static/vendor/js/lit-all.v3.3.3.min.js";
const expectedLitImportMap = {
  imports: {
    lit: litBundlePath,
    "lit/directives/ref.js": litBundlePath,
    "lit/directives/repeat.js": litBundlePath,
    "lit/directives/unsafe-html.js": litBundlePath,
  },
};

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/common/base.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("common base template", () => {
  it("maps the supported Lit imports to the production bundle", async () => {
    // Load the source template and locate its import map.
    const template = await loadTemplate();
    const importMapMatch = template.match(/<script type="importmap">([\s\S]*?)<\/script>/);

    expect(importMapMatch).not.to.equal(null);

    // Parse the import map and verify its production contract.
    const importMap = JSON.parse(importMapMatch[1]);
    expect(importMap).to.deep.equal(expectedLitImportMap);

    // Verify the parsed mapping points to a versioned vendored Lit bundle.
    const mappedBundlePath = importMap.imports.lit;
    expect(mappedBundlePath).to.match(/^\/static\/vendor\/js\/lit-all\.v\d+\.\d+\.\d+\.min\.js$/);

    // Verify the import map is processed before any module script.
    const importMapIndex = template.indexOf(importMapMatch[0]);
    const firstModuleScriptIndex = template.indexOf('<script type="module"');
    expect(importMapIndex).to.be.greaterThan(-1);
    expect(firstModuleScriptIndex).to.be.greaterThan(importMapIndex);

    // Verify the mapped source bundle exists in the repository test server.
    const bundleResponse = await fetch(`/ocg-server${mappedBundlePath}`);
    expect(bundleResponse.ok).to.equal(true);
  });

  it("uses the OCG favicon when no custom favicon is configured", async () => {
    // Load the base template before checking favicon sources.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify custom favicon URLs remain supported.
    expect(template).to.include('href="{{ favicon_url }}" sizes="any"');

    // Verify pages fall back to the default OCG favicon.
    expect(template).to.include('href="/static/images/favicon.svg" type="image/svg+xml" sizes="any"');
  });
});
