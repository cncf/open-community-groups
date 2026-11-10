import { expect } from "@open-wc/testing";

import {
  createDeploymentRefreshUrl,
  DEPLOYMENT_REFRESH_PARAM,
} from "/static/js/common/deployment-version.js";

const DEFAULT_VIEWPORT_CONTENT = "width=device-width, initial-scale=1.0";
const EXPIRED_VIEWPORT_MODE_COOKIE = "ocg_viewport_mode=; Path=/; Max-Age=0; SameSite=Lax";

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
 * Runs the inline preferences initializer inside an isolated same-origin frame with stubbed cookie,
 * storage and media query globals, then returns the resulting state.
 * @param {string} scriptBody - Initializer source.
 * @param {object} [options] - Frame globals.
 * @param {string} [options.cookie] - Value `document.cookie` returns.
 * @param {boolean} [options.prefersDark] - Whether the OS color scheme query matches dark.
 * @param {object} [options.storage] - Fake `localStorage`.
 * @param {Record<string, string>} [options.storage.entries] - Initially stored values.
 * @param {"getter"|"setItem"|null} [options.storage.failure] - Storage access that throws.
 * @returns {object} Root attributes, viewport metas, recorded writes, errors and theme-color metas.
 */
const runPreferencesScript = (scriptBody, { cookie = "", prefersDark = false, storage = {} } = {}) => {
  // Create an isolated frame with a default viewport meta.
  const frame = document.createElement("iframe");
  document.body.append(frame);
  const frameDocument = frame.contentDocument;
  const frameWindow = frame.contentWindow;
  frameDocument.open();
  frameDocument.write(
    `<!DOCTYPE html><html><head><meta name="viewport" content="${DEFAULT_VIEWPORT_CONTENT}" /></head><body></body></html>`,
  );
  frameDocument.close();

  // Control what the initializer reads from document.cookie and record its writes.
  const cookieWrites = [];
  Object.defineProperty(frameDocument, "cookie", {
    configurable: true,
    get: () => cookie,
    set: (value) => {
      cookieWrites.push(value);
    },
  });

  // Replace the frame storage, shared with the test page origin, with a recording fake.
  const { entries = {}, failure = null } = storage;
  const storedValues = new Map(Object.entries(entries));
  const storageWrites = [];
  const fakeStorage = {
    getItem: (key) => (storedValues.has(key) ? storedValues.get(key) : null),
    removeItem: (key) => {
      storageWrites.push([key, null]);
      storedValues.delete(key);
    },
    setItem: (key, value) => {
      if (failure === "setItem") {
        throw new DOMException("Storage is full", "QuotaExceededError");
      }
      storageWrites.push([key, value]);
      storedValues.set(key, value);
    },
  };
  Object.defineProperty(frameWindow, "localStorage", {
    configurable: true,
    get: () => {
      if (failure === "getter") {
        throw new DOMException("Storage is blocked", "SecurityError");
      }
      return fakeStorage;
    },
  });

  // Answer the OS color scheme query inside the frame.
  frameWindow.matchMedia = (query) => ({
    matches: prefersDark && query === "(prefers-color-scheme: dark)",
    media: query,
  });

  // Collect uncaught errors raised inside the frame.
  const errors = [];
  frameWindow.onerror = (message) => {
    errors.push(String(message));
  };

  // Insert the source as a real classic script so it runs synchronously.
  const script = frameDocument.createElement("script");
  script.textContent = scriptBody;
  frameDocument.head.append(script);

  // Capture the resulting state before removing the frame.
  const root = frameDocument.documentElement;
  const result = {
    colorScheme: root.style.colorScheme,
    cookieWrites,
    errors,
    storageWrites,
    theme: root.getAttribute("data-theme"),
    themeColorMetaCount: frameDocument.querySelectorAll('meta[name="theme-color"]').length,
    viewportMetaContents: [...frameDocument.querySelectorAll('meta[name="viewport"]')].map((meta) =>
      meta.getAttribute("content"),
    ),
    viewportMode: root.getAttribute("data-viewport-mode"),
  };
  frame.remove();

  return result;
};

/**
 * Builds the expected initializer state: light theme, default layout, no writes, no errors and no
 * theme-color metas, with the given overrides.
 * @param {object} [overrides] - Expected values that differ from the defaults.
 * @returns {object} Expected state.
 */
const expectedPreferencesState = (overrides = {}) => ({
  colorScheme: "light",
  cookieWrites: [],
  errors: [],
  storageWrites: [],
  theme: "light",
  themeColorMetaCount: 0,
  viewportMetaContents: [DEFAULT_VIEWPORT_CONTENT],
  viewportMode: null,
  ...overrides,
});

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
  it("contains no Askama delimiters in any included head script", async () => {
    // Verify every file the base template includes is free of Askama delimiters.
    const includedFiles = ["deployment_refresh_cleanup.js", "preferences_init.js"];
    for (const fileName of includedFiles) {
      const body = await loadInlineScript(fileName);
      ["{{", "{%", "{#"].forEach((delimiter) => {
        expect(body.includes(delimiter), `${fileName} ${delimiter}`).to.equal(false);
      });
    }
  });

  it("resolves the color theme from storage or the OS without writing storage", async () => {
    // Load the initializer source.
    const body = await loadInlineScript("preferences_init.js");

    // Verify stored light and dark win and anything else follows the OS.
    const storedThemes = [
      [undefined, null],
      ["light", "light"],
      ["dark", "dark"],
      ["system", null],
      ["garbage", null],
    ];
    storedThemes.forEach(([stored, storedTheme]) => {
      [false, true].forEach((prefersDark) => {
        const entries = stored === undefined ? {} : { ocg_theme: stored };
        const theme = storedTheme ?? (prefersDark ? "dark" : "light");
        expect(
          runPreferencesScript(body, { prefersDark, storage: { entries } }),
          `stored ${stored}, OS dark ${prefersDark}`,
        ).to.deep.equal(expectedPreferencesState({ colorScheme: theme, theme }));
      });
    });

    // Verify blocked storage falls back to the OS without escaping errors.
    [false, true].forEach((prefersDark) => {
      const theme = prefersDark ? "dark" : "light";
      expect(
        runPreferencesScript(body, {
          prefersDark,
          storage: { entries: { ocg_theme: "light" }, failure: "getter" },
        }),
        `blocked storage, OS dark ${prefersDark}`,
      ).to.deep.equal(expectedPreferencesState({ colorScheme: theme, theme }));
    });
  });

  it("applies the stored desktop version without touching cookies", async () => {
    // Load the initializer source.
    const body = await loadInlineScript("preferences_init.js");

    // Verify the stored desktop mode forces the desktop layout viewport.
    expect(
      runPreferencesScript(body, { storage: { entries: { ocg_viewport_mode: "desktop" } } }),
    ).to.deep.equal(
      expectedPreferencesState({ viewportMetaContents: ["width=1280"], viewportMode: "desktop" }),
    );
  });

  it("migrates the legacy desktop cookie to storage and always expires it", async () => {
    // Load the initializer source.
    const body = await loadInlineScript("preferences_init.js");

    // Verify the legacy desktop cookie applies desktop, writes storage and expires once.
    const desktopCookies = [
      "ocg_viewport_mode=desktop",
      "  ocg_viewport_mode=desktop  ",
      "theme=light; ocg_viewport_mode=desktop; session=abc",
    ];
    desktopCookies.forEach((cookie) => {
      expect(runPreferencesScript(body, { cookie }), cookie).to.deep.equal(
        expectedPreferencesState({
          cookieWrites: [EXPIRED_VIEWPORT_MODE_COOKIE],
          storageWrites: [["ocg_viewport_mode", "desktop"]],
          viewportMetaContents: ["width=1280"],
          viewportMode: "desktop",
        }),
      );
    });

    // Verify a failed storage write still applies desktop for this load and expires the cookie.
    expect(
      runPreferencesScript(body, { cookie: "ocg_viewport_mode=desktop", storage: { failure: "setItem" } }),
    ).to.deep.equal(
      expectedPreferencesState({
        cookieWrites: [EXPIRED_VIEWPORT_MODE_COOKIE],
        viewportMetaContents: ["width=1280"],
        viewportMode: "desktop",
      }),
    );

    // Verify other values of the exact cookie name keep the default layout and still expire it.
    const otherValueCookies = [
      "ocg_viewport_mode=desktops",
      "ocg_viewport_mode=mobile",
      "ocg_viewport_mode=",
    ];
    otherValueCookies.forEach((cookie) => {
      expect(runPreferencesScript(body, { cookie }), cookie).to.deep.equal(
        expectedPreferencesState({ cookieWrites: [EXPIRED_VIEWPORT_MODE_COOKIE] }),
      );
    });

    // Verify missing and look-alike cookies are left alone.
    const unrelatedCookies = ["", "theme=light; session=abc", "xocg_viewport_mode=desktop"];
    unrelatedCookies.forEach((cookie) => {
      expect(runPreferencesScript(body, { cookie }), cookie).to.deep.equal(expectedPreferencesState());
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
