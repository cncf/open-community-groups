import { expect } from "@open-wc/testing";

import {
  createDeploymentRefreshUrl,
  DEPLOYMENT_REFRESH_ATTRIBUTE,
  DEPLOYMENT_REFRESH_PARAM,
} from "/static/js/common/deployment-version.js";

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

const DEFAULT_VIEWPORT_CONTENT = "width=device-width, initial-scale=1.0";

/** Extracts the inline desktop version initializer from the base template source. */
const extractViewportModeScript = (template) => {
  const headEnd = template.indexOf("</head>");
  const scripts = [
    ...template.slice(0, headEnd).matchAll(/<script(?<attributes>[^>]*)>(?<body>[\s\S]*?)<\/script>/g),
  ];
  const inlineScript = scripts.find(({ groups }) => groups.body.includes("ocg_viewport_mode"));

  expect(inlineScript, "viewport mode initializer").not.to.equal(undefined);

  return {
    attributes: inlineScript.groups.attributes.trim(),
    body: inlineScript.groups.body,
    index: inlineScript.index,
  };
};

/**
 * Runs the inline initializer inside an isolated same-origin frame whose cookie jar is
 * replaced with the given `document.cookie` value, then returns the resulting state.
 */
const runViewportModeScript = (scriptBody, cookie) => {
  // Create an isolated frame with a default viewport meta.
  const frame = document.createElement("iframe");
  document.body.append(frame);
  const frameDocument = frame.contentDocument;
  frameDocument.open();
  frameDocument.write(
    `<!DOCTYPE html><html><head><meta name="viewport" content="${DEFAULT_VIEWPORT_CONTENT}" /></head><body></body></html>`,
  );
  frameDocument.close();

  // Control what the initializer reads from document.cookie.
  Object.defineProperty(frameDocument, "cookie", { configurable: true, get: () => cookie });

  // Insert the extracted source as a real classic script so it runs synchronously.
  const script = frameDocument.createElement("script");
  script.textContent = scriptBody;
  frameDocument.head.append(script);

  // Capture the resulting state before removing the frame.
  const result = {
    viewportMode: frameDocument.documentElement.getAttribute("data-viewport-mode"),
    viewportMetaContents: [...frameDocument.querySelectorAll('meta[name="viewport"]')].map((meta) =>
      meta.getAttribute("content"),
    ),
  };
  frame.remove();

  return result;
};

/** Extracts the inline deployment refresh URL cleanup from the base template source. */
const extractDeploymentRefreshScript = (template) => {
  const headEnd = template.indexOf("</head>");
  const scripts = [
    ...template.slice(0, headEnd).matchAll(/<script(?<attributes>[^>]*)>(?<body>[\s\S]*?)<\/script>/g),
  ];
  const inlineScript = scripts.find(({ groups }) => groups.body.includes(`"${DEPLOYMENT_REFRESH_PARAM}"`));

  expect(inlineScript, "deployment refresh URL cleanup").not.to.equal(undefined);

  return {
    attributes: inlineScript.groups.attributes.trim(),
    body: inlineScript.groups.body,
    index: inlineScript.index,
  };
};

/**
 * Runs the inline deployment refresh cleanup against stubbed browser globals for
 * the given URL, then returns the address bar rewrites and the root marker state.
 */
const runDeploymentRefreshScript = (scriptBody, href) => {
  // Stub the globals the cleanup reads and rewrites.
  const url = new URL(href);
  const documentElement = document.createElement("html");
  const replacedUrls = [];
  const historyStub = {
    state: { page: "current" },
    replaceState: (state, _title, replacedUrl) => replacedUrls.push({ state, url: replacedUrl }),
  };
  const locationStub = { hash: url.hash, pathname: url.pathname, search: url.search };

  // Run the extracted source with the stubs in place of the page globals.
  new Function("document", "history", "location", scriptBody)({ documentElement }, historyStub, locationStub);

  return { marked: documentElement.hasAttribute(DEPLOYMENT_REFRESH_ATTRIBUTE), replacedUrls };
};

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

  it("runs the desktop version initializer before any stylesheet or other script", async () => {
    // Load the base template and locate the inline initializer.
    const template = await loadTemplate();
    const { attributes, index } = extractViewportModeScript(template);

    // Verify the initializer is a classic, render-blocking inline script.
    expect(attributes).to.equal("");

    // Verify charset and a single viewport meta precede the initializer.
    const viewportMetaMatches = [...template.matchAll(/<meta name="viewport"/g)];
    expect(viewportMetaMatches).to.have.lengthOf(1);
    expect(template.indexOf('<meta charset="UTF-8"')).to.be.lessThan(viewportMetaMatches[0].index);
    expect(viewportMetaMatches[0].index).to.be.lessThan(index);

    // Verify the initializer precedes the first stylesheet and every other script.
    expect(index).to.be.lessThan(template.indexOf('<link rel="stylesheet"'));
    expect(index).to.be.lessThan(template.indexOf("<script "));

    // Verify the click behaviour module is loaded with the other common modules.
    expect(template).to.include('<script type="module" src="/static/js/common/viewport-mode.js"></script>');
  });

  it("forces the desktop layout viewport only when the exact cookie pair is present", async () => {
    // Load the base template and extract the initializer source.
    const template = await loadTemplate();
    const { body } = extractViewportModeScript(template);

    // Verify the exact cookie switches the document to desktop mode.
    const desktopCookies = [
      "ocg_viewport_mode=desktop",
      "  ocg_viewport_mode=desktop  ",
      "theme=light; ocg_viewport_mode=desktop; session=abc",
    ];
    desktopCookies.forEach((cookie) => {
      expect(runViewportModeScript(body, cookie), cookie).to.deep.equal({
        viewportMode: "desktop",
        viewportMetaContents: ["width=1280"],
      });
    });

    // Verify missing, misleading, and unknown values keep the responsive layout.
    const defaultCookies = [
      "",
      "theme=light; session=abc",
      "xocg_viewport_mode=desktop",
      "ocg_viewport_mode=desktops",
      "ocg_viewport_mode=mobile",
      "ocg_viewport_mode=",
    ];
    defaultCookies.forEach((cookie) => {
      expect(runViewportModeScript(body, cookie), cookie).to.deep.equal({
        viewportMode: null,
        viewportMetaContents: [DEFAULT_VIEWPORT_CONTENT],
      });
    });
  });

  it("cleans the deployment refresh URL before HTMX records the history path", async () => {
    // Load the base template and locate the inline cleanup.
    const template = await loadTemplate();
    const { attributes, index } = extractDeploymentRefreshScript(template);

    // Verify the cleanup is a classic inline script that runs before HTMX loads.
    expect(attributes).to.equal("");
    const htmxScriptIndex = template.search(/<script src="\/static\/vendor\/js\/htmx\.v[\d.]+\.min\.js">/);
    expect(htmxScriptIndex).to.be.greaterThan(-1);
    expect(index).to.be.lessThan(htmxScriptIndex);
  });

  it("strips only the deployment refresh parameter and marks the refreshed page", async () => {
    // Load the base template and extract the cleanup source.
    const { body } = extractDeploymentRefreshScript(await loadTemplate());

    // Verify refreshed URLs return to the page URL without re-encoding other parameters.
    const pageUrls = [
      "https://example.test/explore?kind[0]=a%20b&entity=events#results",
      "https://example.test/cncf?page=2",
      "https://example.test/cncf",
    ];
    pageUrls.forEach((pageUrl) => {
      const { hash, pathname, search } = new URL(pageUrl);
      expect(
        runDeploymentRefreshScript(body, createDeploymentRefreshUrl(pageUrl, "t1")),
        pageUrl,
      ).to.deep.equal({
        marked: true,
        replacedUrls: [{ state: { page: "current" }, url: `${pathname}${search}${hash}` }],
      });
    });

    // Verify URLs without the exact parameter are left untouched.
    const untouchedUrls = [
      "https://example.test/cncf?page=2",
      `https://example.test/cncf?x${DEPLOYMENT_REFRESH_PARAM}=1`,
      `https://example.test/cncf?page=${DEPLOYMENT_REFRESH_PARAM}`,
    ];
    untouchedUrls.forEach((untouchedUrl) => {
      expect(runDeploymentRefreshScript(body, untouchedUrl), untouchedUrl).to.deep.equal({
        marked: false,
        replacedUrls: [],
      });
    });
  });
});
