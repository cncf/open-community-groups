import { expect } from "@open-wc/testing";

import {
  createDeploymentRefreshUrl,
  DEPLOYMENT_REFRESH_PARAM,
} from "/static/js/common/deployment-version.js";

const DEFAULT_VIEWPORT_CONTENT = "width=device-width, initial-scale=1.0";

/**
 * Loads an inline head script that the base template includes verbatim.
 * @param {string} fileName - File name under templates/common/scripts.
 * @returns {Promise<string>} Script source.
 */
const loadInlineScript = async (fileName) => {
  const response = await fetch(`/ocg-server/templates/common/scripts/${fileName}`);

  expect(response.ok, fileName).to.equal(true);

  return response.text();
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

  // Insert the source as a real classic script so it runs synchronously.
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

/**
 * Runs the inline deployment refresh cleanup against stubbed browser globals for
 * the given URL, then returns the address bar rewrites.
 */
const runDeploymentRefreshScript = (scriptBody, href) => {
  // Stub the globals the cleanup reads and rewrites.
  const url = new URL(href);
  const replacedUrls = [];
  const historyStub = {
    state: { page: "current" },
    replaceState: (state, _title, replacedUrl) => replacedUrls.push({ state, url: replacedUrl }),
  };
  const locationStub = { hash: url.hash, pathname: url.pathname, search: url.search };

  // Run the source with the stubs in place of the page globals.
  new Function("history", "location", scriptBody)(historyStub, locationStub);

  return replacedUrls;
};

describe("common inline head scripts", () => {
  it("forces the desktop layout viewport only when the exact cookie pair is present", async () => {
    // Load the initializer source.
    const body = await loadInlineScript("viewport_mode_init.js");

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

  it("strips only the deployment refresh parameter", async () => {
    // Load the cleanup source.
    const body = await loadInlineScript("deployment_refresh_cleanup.js");

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
      ).to.deep.equal([{ state: { page: "current" }, url: `${pathname}${search}${hash}` }]);
    });

    // Verify URLs without the exact parameter are left untouched.
    const untouchedUrls = [
      "https://example.test/cncf?page=2",
      `https://example.test/cncf?x${DEPLOYMENT_REFRESH_PARAM}=1`,
      `https://example.test/cncf?page=${DEPLOYMENT_REFRESH_PARAM}`,
    ];
    untouchedUrls.forEach((untouchedUrl) => {
      expect(runDeploymentRefreshScript(body, untouchedUrl), untouchedUrl).to.deep.equal([]);
    });
  });
});
