import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";

const BASE_URL = process.env.OCG_E2E_BASE_URL || "http://127.0.0.1:9001";
// OpenFreeMap basemap style of each color theme (see static/js/common/location/maplibre.js).
export const BASEMAP_STYLE_URLS = {
  dark: "https://tiles.openfreemap.org/styles/dark",
  light: "https://tiles.openfreemap.org/styles/bright",
};
// Either basemap style URL, matched whole.
const BASEMAP_STYLE_URL_PATTERN = /^https:\/\/tiles\.openfreemap\.org\/styles\/(?:bright|dark)$/;
const NAVIGATION_ASSET_TIMEOUT_MS = 5_000;
const NAVIGATION_RETRY_ATTEMPTS = 3;
const NAVIGATION_RETRY_DELAY_MS = 1_000;
const HTMX_SETTLE_TIMEOUT_MS = 10_000;
const ACTION_RESPONSE_BODY_PREVIEW_CHARS = 2_000;
// Total time to open a table filter menu and click one of its options.
const TABLE_FILTER_MENU_TIMEOUT_MS = 10_000;
// Wait for a table filter option before reopening its menu and trying again.
const TABLE_FILTER_OPTION_TIMEOUT_MS = 2_000;
// Prefix of the keys that record which `seedLocalStorage` entries a page already wrote.
const SEED_MARKER_PREFIX = "__ocg_e2e_seeded";
// Storage key of the color theme choice (see static/js/common/theme.js).
const THEME_STORAGE_KEY = "ocg_theme";
// Visible label of each account menu theme choice.
const THEME_CHOICE_LABELS = { dark: "Dark", light: "Light", system: "System" };

/** Builds an absolute E2E URL for a relative path. */
const buildUrl = (path) => new URL(path, BASE_URL).toString();

/** Waits before retrying a navigation that could not reach the test server. */
const waitForNavigationRetry = () =>
  new Promise((resolve) => {
    setTimeout(resolve, NAVIGATION_RETRY_DELAY_MS);
  });

/**
 * Waits for the shared stylesheet and HTMX runtime required by every page. Chromium attaches an
 * empty `sheet` even when the stylesheet request fails (a 404, say), so the stylesheet only
 * counts as loaded once it has CSS rules.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @throws {Error} Naming each asset that did not load within the timeout.
 */
const waitForApplicationAssets = async (page) => {
  try {
    await page.waitForFunction(
      () => {
        const applicationStylesheet = document.querySelector(
          'link[rel="stylesheet"][href^="/static/css/styles."][href$=".css"]',
        );

        return Boolean(applicationStylesheet?.sheet?.cssRules.length > 0 && window.htmx);
      },
      undefined,
      { timeout: NAVIGATION_ASSET_TIMEOUT_MS },
    );
  } catch (error) {
    if (error?.name !== "TimeoutError") {
      throw error;
    }

    const missingAssets = await page
      .evaluate(() => {
        const missing = [];
        const applicationStylesheet = document.querySelector(
          'link[rel="stylesheet"][href^="/static/css/styles."][href$=".css"]',
        );
        if (!applicationStylesheet) {
          missing.push("application stylesheet link (/static/css/styles.*.css)");
        } else if (!applicationStylesheet.sheet?.cssRules.length) {
          // Resource timing gives the HTTP status of a failed load (0 when unknown).
          const [resource] = performance.getEntriesByName(applicationStylesheet.href);
          const status = resource?.responseStatus ? ` (HTTP ${resource.responseStatus})` : "";
          const state = applicationStylesheet.sheet ? "has no CSS rules" : "did not load";
          missing.push(`stylesheet ${applicationStylesheet.getAttribute("href")} ${state}${status}`);
        }
        if (!window.htmx) {
          const htmxScript = document.querySelector('script[src*="/htmx."]');
          missing.push(`HTMX runtime ${htmxScript?.getAttribute("src") ?? "(no htmx script tag)"}`);
        }
        return missing;
      })
      .catch(() => ["unknown (page closed or navigated)"]);

    throw new Error(`Application assets did not load at ${page.url()}: ${missingAssets.join(", ")}`, {
      cause: error,
    });
  }
};

/**
 * Checks whether a navigation error means the server refused or reset the connection, which
 * happens while a test server restarts. Uses Chromium, Firefox and WebKit wording.
 * @param {unknown} error - Error thrown by `page.goto`.
 * @returns {boolean} Whether the navigation is retried.
 */
const isConnectionFailure = (error) => {
  const message = String(error?.message || error);

  return [
    // Chromium.
    "net::ERR_CONNECTION_REFUSED",
    "net::ERR_CONNECTION_RESET",
    // Firefox.
    "NS_ERROR_CONNECTION_REFUSED",
    "NS_ERROR_NET_RESET",
    // WebKit (macOS "Could not connect to the server.", Linux "Could not connect: Connection refused").
    "Could not connect",
    "Connection reset",
  ].some((wording) => message.includes(wording));
};

/**
 * Records a retried navigation as a `navigation-retry` annotation on the running test; does
 * nothing outside a test.
 * @param {{attempt: number, url: string}} retry - Failed attempt number and URL.
 */
const reportNavigationRetry = ({ attempt, url }) => {
  let testInfo;
  try {
    testInfo = test.info();
  } catch {
    return;
  }

  testInfo.annotations.push({
    type: "navigation-retry",
    description: `connection (attempt ${attempt}/${NAVIGATION_RETRY_ATTEMPTS}) ${url}`,
  });
};

/**
 * Navigates to a URL and waits for the application assets. Only connection failures are retried;
 * goto timeouts, missing responses and missing assets fail immediately.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} url - Absolute URL.
 * @returns {Promise<import("@playwright/test").Response>} Main-frame response.
 */
const navigateToUrl = async (page, url) => {
  for (let attempt = 1; ; attempt += 1) {
    let response;
    try {
      response = await page.goto(url, { waitUntil: "domcontentloaded" });
    } catch (error) {
      if (attempt === NAVIGATION_RETRY_ATTEMPTS || !isConnectionFailure(error)) {
        throw error;
      }

      reportNavigationRetry({ attempt, url });
      await waitForNavigationRetry();
      continue;
    }

    if (!response) {
      throw new Error(`Navigation to ${url} completed without a server response`);
    }

    await waitForApplicationAssets(page);
    return response;
  }
};

/**
 * Submits the seeded login form once and waits for the redirect away from the login page.
 * @param {import("@playwright/test").Page} page - Playwright page showing the login form.
 * @throws {Error} When the server redirects back to `/log-in` (credentials rejected).
 */
const submitSeededLogin = async (page) => {
  const response = await waitForActionResponse(
    page,
    () => page.getByRole("button", { name: "Sign In" }).click(),
    { method: "POST", pathname: "/log-in", settle: false, status: 303 },
  );

  const location = new URL((await response.headerValue("location")) ?? "", response.url());
  if (location.pathname === "/log-in") {
    throw new Error(`Login rejected: POST /log-in redirected back to ${location.pathname}${location.search}`);
  }

  await page.waitForURL((url) => url.pathname !== "/log-in");
};

/**
 * Checks a response status and fails with the response body when it does not match.
 * @param {import("@playwright/test").Response} response - Matched response.
 * @param {number|number[]} [status] - Expected status or statuses; defaults to any 2xx.
 */
const expectResponseStatus = async (response, status) => {
  const expectedStatuses = status === undefined ? [] : [status].flat();
  const statusMatches =
    expectedStatuses.length === 0 ? response.ok() : expectedStatuses.includes(response.status());

  if (!statusMatches) {
    const body = await response.text().catch(() => "<body unavailable>");
    const expected = expectedStatuses.length === 0 ? "a 2xx status" : expectedStatuses.join(" or ");

    throw new Error(
      `Expected ${response.request().method()} ${response.url()} to respond with ${expected} but ` +
        `received ${response.status()}.\n${body.slice(0, ACTION_RESPONSE_BODY_PREVIEW_CHARS)}`,
    );
  }
};

/**
 * Builds the response matcher for the HTMX request of the Next pagination link.
 * The offset parameter is the one that moves to 1, since a page can carry several offsets.
 * @param {import("@playwright/test").Locator} nextLink - Next link with an `hx-get` URL.
 * @returns {Promise<{ matcher: object, offsetParam: string }>} Matcher and offset name.
 */
const getPaginationNextMatcher = async (nextLink) => {
  const requestUrl = new URL(await nextLink.getAttribute("hx-get"), BASE_URL);
  const offsetParam = [...requestUrl.searchParams].find(
    ([name, value]) => name.endsWith("offset") && value === "1",
  )?.[0];
  expect(offsetParam, `Next link ${requestUrl} has no offset of 1`).toBeTruthy();

  return {
    matcher: {
      method: "GET",
      params: { [offsetParam]: "1" },
      pathname: requestUrl.pathname,
      status: 200,
    },
    offsetParam,
  };
};

/**
 * Returns whether a response matches a request contract. Omitted fields match anything.
 * @param {import("@playwright/test").Response} candidate - Response to check.
 * @param {{
 *   method?: string,
 *   params?: Record<string, string|null|true>,
 *   pathname?: string|RegExp,
 *   urlEndsWith?: string,
 *   urlIncludes?: string
 * }} matcher - Exact `pathname` string or non-global RegExp; `params` values are an
 *   exact value (string), absent (`null`) or present with any value (`true`).
 * @returns {boolean} Whether the response matches.
 */
const matchesResponse = (candidate, { method, params, pathname, urlEndsWith, urlIncludes }) => {
  const url = new URL(candidate.url());

  if (method && candidate.request().method() !== method) {
    return false;
  }
  if (typeof pathname === "string" && url.pathname !== pathname) {
    return false;
  }
  if (pathname instanceof RegExp && !pathname.test(url.pathname)) {
    return false;
  }
  if (urlIncludes && !candidate.url().includes(urlIncludes)) {
    return false;
  }
  if (urlEndsWith && !candidate.url().endsWith(urlEndsWith)) {
    return false;
  }

  return Object.entries(params ?? {}).every(([name, value]) => {
    if (value === null) {
      return !url.searchParams.has(name);
    }
    if (value === true) {
      return url.searchParams.has(name);
    }
    return url.searchParams.get(name) === value;
  });
};

/**
 * Reads the alpha channel of a computed CSS colour. Covers the legacy `rgba()`/`hsla()` comma
 * syntax and the slash syntax of modern colour functions; colours without alpha are opaque.
 * @param {string} color - Computed colour.
 * @returns {number} Alpha between 0 and 1.
 */
const getColorAlpha = (color) => {
  const value = color.trim().toLowerCase();
  if (value === "transparent") {
    return 0;
  }

  const slashAlpha = value.match(/\/\s*(-?[\d.]+)(%?)\s*\)$/);
  const legacyArgs = value.match(/^(?:rgba|hsla)\(([^()]*)\)$/)?.[1].split(",");
  const alpha = slashAlpha
    ? `${slashAlpha[1]}${slashAlpha[2]}`
    : legacyArgs?.length === 4
      ? legacyArgs[3].trim()
      : "1";

  return alpha.endsWith("%") ? Number.parseFloat(alpha) / 100 : Number.parseFloat(alpha);
};

/**
 * Splits a computed `box-shadow` into its layers, dropping transparent layers and layers whose
 * offsets, blur and spread are all zero, since neither draws anything.
 * @param {string} boxShadow - Computed `box-shadow` value.
 * @returns {string[]} Layers that draw a visible shadow.
 */
const getVisibleShadowLayers = (boxShadow) => {
  if (boxShadow.trim() === "none") {
    return [];
  }

  // Split on commas outside colour functions.
  const layers = [];
  let depth = 0;
  let layer = "";
  for (const character of boxShadow) {
    if (character === "," && depth === 0) {
      layers.push(layer.trim());
      layer = "";
      continue;
    }
    if (character === "(") {
      depth += 1;
    } else if (character === ")") {
      depth -= 1;
    }
    layer += character;
  }
  layers.push(layer.trim());

  return layers.filter((shadowLayer) => {
    const colorFunction = shadowLayer.match(/[a-z-]+\((?:[^()]|\([^()]*\))*\)/i)?.[0];
    const rest = colorFunction ? shadowLayer.replace(colorFunction, " ") : shadowLayer;
    const tokens = rest.split(/\s+/).filter(Boolean);
    const lengths = tokens.filter((token) => /^-?[\d.]+(?:e-?\d+)?[a-z]*$/i.test(token));
    const color = colorFunction ?? tokens.find((token) => token !== "inset" && !lengths.includes(token));

    return (
      (color === undefined || getColorAlpha(color) > 0) &&
      lengths.some((length) => Number.parseFloat(length) !== 0)
    );
  });
};

/**
 * Names the focus indicator that appeared between two style reads: an outline that is visible and
 * differs from the baseline, otherwise a visible box-shadow that differs from the baseline one.
 * @param {{ boxShadow: string, outlineColor: string, outlineStyle: string, outlineWidth: string }}
 * baseline - Styles read before focus.
 * @param {{ boxShadow: string, outlineColor: string, outlineStyle: string, outlineWidth: string }}
 * focused - Styles read after focus.
 * @returns {"box-shadow"|"outline"|null} Indicator kind, or null when nothing visible appeared.
 */
const getFocusIndicatorKind = (baseline, focused) => {
  const outlineVisible =
    !["hidden", "none"].includes(focused.outlineStyle) &&
    Number.parseFloat(focused.outlineWidth) > 0 &&
    getColorAlpha(focused.outlineColor) > 0;
  const outlineChanged = ["outlineColor", "outlineStyle", "outlineWidth"].some(
    (property) => focused[property] !== baseline[property],
  );
  if (outlineVisible && outlineChanged) {
    return "outline";
  }

  const focusedShadow = getVisibleShadowLayers(focused.boxShadow).join(", ");
  if (focusedShadow !== "" && focusedShadow !== getVisibleShadowLayers(baseline.boxShadow).join(", ")) {
    return "box-shadow";
  }

  return null;
};

/** Builds a fully-qualified URL. */
export const buildE2eUrl = (path) => buildUrl(path);

/**
 * Selects the desktop or mobile copy of the site or community stats strip.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {"community" | "site"} pageKind - Unused: both pages share one strip markup.
 * @param {"desktop" | "mobile"} viewport - Layout copy to select.
 * @returns {import("@playwright/test").Locator} Stats container.
 */
export const getStatsContainer = (page, pageKind, viewport) =>
  page.locator(`[data-stats-layout="${viewport}"]`);

/**
 * Selects a stat value within a stats container. The value follows its title in
 * `macros/stats.html`.
 * @param {import("@playwright/test").Locator} statsContainer - Stats container.
 * @param {string} statLabel - Exact stat title, such as "Groups".
 * @returns {import("@playwright/test").Locator} Stat value element.
 */
export const getStatValue = (statsContainer, statLabel) =>
  statsContainer.getByText(statLabel, { exact: true }).locator("xpath=following-sibling::*[1]");

/** Selects a section container from its visible heading. */
export const getSectionByHeading = (page, heading) =>
  page.getByText(heading, { exact: true }).locator("..").locator("..");

/**
 * Selects a responsive link within a heading-based section. Role queries skip the
 * `display:none` copies, so at each width it finds the one link shown: the heading
 * link from md up, the bottom link in narrow mouse windows and the heading's pill
 * on phones.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {string} heading - Exact section heading text.
 * @param {string} linkName - Exact accessible name of the link.
 * @returns {import("@playwright/test").Locator} Section link.
 */
export const getSectionLink = (page, heading, linkName) =>
  getSectionByHeading(page, heading).getByRole("link", { name: linkName, exact: true });

/** Selects a community banner on the site home page. */
export const getCommunityBanner = (page, displayName) => page.getByAltText(`${displayName} banner`).first();

/** Selects the summary region at the top of group and event pages. */
export const getIntroSection = (page) => page.getByRole("region", { name: /^(Event|Group) summary$/ });

/** Builds unique credentials for sign-up and login flows. */
export const buildAuthUser = () => {
  const suffix = randomUUID().replace(/-/g, "").slice(0, 8);
  const username = `e2e${suffix}`;

  return {
    name: `E2E User ${suffix}`,
    email: `${username}@example.com`,
    username,
    password: "Password123!",
  };
};

/**
 * Builds a unique, human-readable name for rows created through the browser.
 * @param {string} prefix - Short spec-specific label, e.g. "sponsor".
 * @returns {string} Name such as `E2E sponsor 3f9a1c2b`.
 */
export const uniqueName = (prefix) => `E2E ${prefix} ${randomUUID().replace(/-/g, "").slice(0, 8)}`;

/**
 * Returns a compact suffix from a UUID for slugs, usernames and provider references.
 * @param {string} id - UUID string.
 * @returns {string} First 12 hex characters without dashes.
 */
export const shortId = (id) => id.replaceAll("-", "").slice(0, 12);

/**
 * Returns a `datetime-local` string a number of days in the future at a fixed time.
 * @param {{ days: number, hour?: number, minute?: number }} options - Offset from today (UTC) and
 * optional hour (default 10) and minute (default 0).
 * @returns {string} Value such as `2031-05-10T10:00` accepted by `<input type="datetime-local">`.
 */
export const futureDate = ({ days, hour = 10, minute = 0 }) => {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + days);
  const yyyy = date.getUTCFullYear();
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(date.getUTCDate()).padStart(2, "0");
  const time = `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
  return `${yyyy}-${mm}-${dd}T${time}`;
};

/** Navigates to the site home page. */
export const navigateToSiteHome = async (page) => {
  await navigateToUrl(page, buildUrl("/"));
};

/** Navigates to a community home page. */
export const navigateToCommunityHome = async (page, communityName) => {
  await navigateToUrl(page, buildUrl(`/${communityName}`));
};

/** Navigates to a specific group page within a community. */
export const navigateToGroup = async (page, communityName, groupSlug) => {
  await navigateToUrl(page, buildUrl(`/${communityName}/group/${groupSlug}`));
};

/** Navigates to a specific event page within a community. */
export const navigateToEvent = async (page, communityName, groupSlug, eventSlug) => {
  await navigateToUrl(page, buildUrl(`/${communityName}/group/${groupSlug}/event/${eventSlug}`));
};

/**
 * Navigates to a relative path.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} path - Path relative to the E2E base URL.
 * @returns {Promise<import("@playwright/test").Response>} Main-frame response.
 */
export const navigateToPath = (page, path) => navigateToUrl(page, buildUrl(path));

/**
 * Waits until HTMX has finished swapping and settling any in-flight content.
 * HTMX wires swapped nodes (hx-* handlers, htmx:load) on a delayed settle step, so
 * interacting right after a response can hit visible but not yet processed elements.
 */
export const waitForHtmxSettle = async (page) => {
  await page.waitForFunction(
    () => !document.querySelector(".htmx-request, .htmx-swapping, .htmx-settling, .htmx-added"),
    undefined,
    { timeout: HTMX_SETTLE_TIMEOUT_MS },
  );
};

/**
 * Runs an action and waits for the response matching its request contract, then asserts its
 * status. Matching on the request contract first makes a wrong status fail immediately with the
 * response body instead of timing out. Status defaults to any successful response; pin the
 * exact status (or the exact set of statuses) the action can return.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {() => Promise<unknown>|unknown} action - Click or submit that sends the request.
 * @param {{
 *   method: string,
 *   params?: Record<string, string|null|true>,
 *   pathname?: string|RegExp,
 *   settle?: boolean,
 *   status?: number|number[],
 *   urlEndsWith?: string,
 *   urlIncludes?: string
 * }} matcher - Response matcher; `settle: false` skips the HTMX settle wait for actions
 *   that navigate.
 * @returns {Promise<import("@playwright/test").Response>} Matched response.
 */
export const waitForActionResponse = async (page, action, { settle = true, ...matcher }) => {
  const [response] = await Promise.all([waitForResponseMatching(page, matcher), action()]);

  if (settle) {
    await waitForHtmxSettle(page);
  }

  return response;
};

/**
 * Runs an action that sends several requests, waits for every matching response and asserts
 * their statuses, then waits for HTMX to settle once.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {() => Promise<unknown>|unknown} action - Click or submit that sends the requests.
 * @param {object[]} matchers - One `waitForResponseMatching` matcher per expected response.
 * @param {{ settle?: boolean }} [options] - `settle: false` for actions that navigate.
 * @returns {Promise<import("@playwright/test").Response[]>} Responses in matcher order.
 */
export const waitForActionResponses = async (page, action, matchers, { settle = true } = {}) => {
  const [responses] = await Promise.all([
    Promise.all(matchers.map((matcher) => waitForResponseMatching(page, matcher))),
    action(),
  ]);

  if (settle) {
    await waitForHtmxSettle(page);
  }

  return responses;
};

/**
 * Arms a wait for the next response matching a request contract and asserts its status.
 * Call it before the steps that trigger the request and await the returned promise after them;
 * it does not wait for HTMX to settle.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {{
 *   method: string,
 *   params?: Record<string, string|null|true>,
 *   pathname?: string|RegExp,
 *   status?: number|number[],
 *   urlEndsWith?: string,
 *   urlIncludes?: string
 * }} matcher - Response matcher; status defaults to any 2xx.
 * @returns {Promise<import("@playwright/test").Response>} Matched response.
 */
export const waitForResponseMatching = (page, { status, ...matcher }) =>
  page
    .waitForResponse((candidate) => matchesResponse(candidate, matcher))
    .then(async (response) => {
      await expectResponseStatus(response, status);
      return response;
    });

/**
 * Verifies the open confirmation dialog message and clicks its confirming button.
 * It does not wait for the dialog to close, because the confirmed action may open the next alert.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {{ button?: string, message: string }} options - Expected message and button name.
 */
export const confirmAlert = async (page, { button = "Yes", message }) => {
  const popup = page.locator(".swal2-popup");

  await expect(popup).toContainText(message);
  await popup.getByRole("button", { name: button, exact: true }).click();
};

/**
 * Verifies an alert message, closes it with the given button and waits until it is hidden.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {{ button?: string, message: string }} options - Expected message and button name.
 */
export const dismissAlert = async (page, { button = "OK", message }) => {
  const popup = page.locator(".swal2-popup");

  await expect(popup).toContainText(message);
  await popup.getByRole("button", { name: button, exact: true }).click();
  await expect(popup).toBeHidden();
};

/**
 * Closes an optional alert offering the given button when it appears within the timeout. Other
 * alerts are ignored. Use it only for prompts that legitimately may not show; use `dismissAlert`
 * when the alert is expected.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {{ button: string, timeout?: number }} options - Button name and wait in milliseconds.
 * @returns {Promise<boolean>} Whether an alert was dismissed.
 */
export const dismissAlertIfPresent = async (page, { button, timeout = 1000 }) => {
  const popup = page
    .locator(".swal2-popup")
    .filter({ has: page.getByRole("button", { name: button, exact: true }) });

  try {
    await popup.waitFor({ state: "visible", timeout });
  } catch (error) {
    if (error?.name !== "TimeoutError") {
      throw error;
    }
    return false;
  }

  await popup.getByRole("button", { name: button, exact: true }).click();
  await expect(popup).toBeHidden();
  return true;
};

/**
 * Clicks an option of a dashboard table filter menu, opening the menu first when it is closed.
 * An HTMX swap can replace the menu with a closed one, or close it, between the summary click and
 * the option click, so the menu is reopened and the option click retried until it lands. A click
 * that times out is never dispatched, so retries do not send duplicate requests.
 * @param {import("@playwright/test").Locator} scope - Region that contains the filter menu.
 * @param {string} label - Accessible name of the menu summary, such as "Status filters".
 * @param {import("@playwright/test").Locator} option - Option button inside the menu.
 * @returns {Promise<void>}
 */
export const clickTableFilterOption = async (scope, label, option) => {
  const summary = scope.getByLabel(label);
  const menu = summary.locator("xpath=..");

  await expect(async () => {
    if (!(await menu.evaluate((details) => details.open))) {
      await summary.click();
    }
    await option.click({ timeout: TABLE_FILTER_OPTION_TIMEOUT_MS });
  }).toPass({ intervals: [0], timeout: TABLE_FILTER_MENU_TIMEOUT_MS });
};

/** Verifies the ordered, user-facing column names for a table. */
export const expectTableHeaders = async (table, expectedHeaders) => {
  const columnHeaders = table.locator("thead th");

  await expect(columnHeaders).toHaveCount(expectedHeaders.length);

  for (const [index, expectedHeader] of expectedHeaders.entries()) {
    await expect(columnHeaders.nth(index)).toContainText(expectedHeader);
  }
};

/** Verifies responsive table-column visibility at one viewport width. */
export const expectTableColumnsAtViewport = async (
  page,
  table,
  viewportWidth,
  visibleHeaders,
  hiddenHeaders,
) => {
  await page.setViewportSize({ width: viewportWidth, height: 900 });

  for (const header of visibleHeaders) {
    const columnHeader = table.locator("thead th").filter({
      has: page.getByText(header, { exact: true }),
    });

    await expect(columnHeader).toBeVisible();
  }

  for (const header of hiddenHeaders) {
    const columnHeader = table.locator("thead th").filter({
      has: page.getByText(header, { exact: true }),
    });

    await expect(columnHeader).toBeHidden();
  }
};

/**
 * Checks that no id repeats on the page, so `for` and `aria-*` references cannot bind to a hidden
 * copy of the same markup.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>} Resolves once the check passes.
 */
export const expectNoDuplicateIds = async (page) => {
  const duplicateIds = await page.evaluate(() => {
    const counts = new Map();
    for (const element of document.querySelectorAll("[id]")) {
      counts.set(element.id, (counts.get(element.id) ?? 0) + 1);
    }
    return [...counts].filter(([, count]) => count > 1).map(([id]) => id);
  });

  expect(duplicateIds).toEqual([]);
};

/**
 * Reads how far the page scrolls sideways. `clientWidth` is the bound because `innerWidth` grows
 * with content wider than a phone's viewport, which would hide the overflow.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<number>} Overflow in pixels, zero or less when the page fits.
 */
export const getPageOverflow = (page) =>
  page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);

/**
 * Sends a close request as Android Back does. A sheet's own Escape handler would close it first
 * and destroy its CloseWatcher, so the next keydown is stopped before reaching the page.
 * @param {import("@playwright/test").Page} page - Page showing the sheet.
 * @returns {Promise<void>} Resolves once the key is released.
 */
export const sendCloseRequest = async (page) => {
  await page.evaluate(() => {
    window.addEventListener("keydown", (event) => event.stopImmediatePropagation(), {
      capture: true,
      once: true,
    });
  });
  await page.keyboard.press("Escape");
};

/**
 * Checks the whole close contract of a modal: it is hidden, the page scroll lock is released and,
 * when given, focus is back on the opener and the page kept its scroll position. Assumes no other
 * modal is still open, because the lock counter in `static/js/common/modals/modal-lifecycle.js`
 * only releases once every tracked modal has closed. Native `<dialog>` and SweetAlert closes do not
 * use that counter.
 * @param {import("@playwright/test").Page} page - Page showing the dialog.
 * @param {import("@playwright/test").Locator} dialog - Dialog that should be closed.
 * @param {object} [options] - Optional close checks.
 * @param {import("@playwright/test").Locator} [options.opener] - Control that should get focus back.
 * @param {number} [options.scrollY] - Page scroll position read before the dialog opened.
 * @returns {Promise<void>} Resolves once every check passes.
 */
export const expectDialogClosed = async (page, dialog, { opener, scrollY } = {}) => {
  await expect(dialog).toBeHidden();
  await expect
    .poll(
      () =>
        page.evaluate(() => ({
          lockCount: document.body.dataset.modalOpenCount ?? "0",
          scrollLocked: [document.documentElement, document.body].some(
            (element) => getComputedStyle(element).overflowY === "hidden",
          ),
        })),
      { message: "page scroll is still locked after the dialog closed" },
    )
    .toEqual({ lockCount: "0", scrollLocked: false });

  if (opener) {
    await expect(opener).toBeFocused();
  }
  if (typeof scrollY === "number") {
    await expect.poll(() => page.evaluate(() => Math.round(window.scrollY))).toBe(scrollY);
  }
};

/**
 * Resolves a CSS color expression where an element's custom properties apply, so color checks
 * hold in every color theme. A hidden probe appended to the element's parent (the root element
 * when it has none) reads the computed color and is removed again.
 * @param {import("@playwright/test").Locator} locator - Element whose context resolves the color.
 * @param {string} color - Any CSS color, for example `"var(--color-surface)"`.
 * @returns {Promise<string>} Computed color, for example `"rgb(255, 255, 255)"`.
 */
export const resolveCssColor = (locator, color) =>
  locator.evaluate((element, expression) => {
    const probe = document.createElement("span");
    probe.hidden = true;
    probe.style.color = expression;
    (element.parentElement ?? document.documentElement).append(probe);
    const resolvedColor = getComputedStyle(probe).color;
    probe.remove();

    return resolvedColor;
  }, color);

/**
 * Reads the tooltip background of an ECharts chart, resolved in the page.
 * @param {import("@playwright/test").Locator} chart - Rendered chart container.
 * @returns {Promise<string>} Computed tooltip background color.
 */
export const readTooltipBackground = async (chart) => {
  const background = await chart.evaluate(
    (element) => window.echarts.getInstanceByDom(element).getOption().tooltip[0].backgroundColor,
  );
  return resolveCssColor(chart, background);
};

/**
 * Checks that moving focus with the keyboard draws a visible focus indicator. The outline or
 * box-shadow is compared before and after focus, so a static shadow never passes as a focus ring.
 * The helper presses no keys itself, so it never closes menus that close on focus loss.
 * @param {import("@playwright/test").Locator} locator - Control that receives focus; it must not
 * be focused yet.
 * @param {() => Promise<unknown>} focus - Moves focus with the keyboard, for example
 * `() => page.keyboard.press("Tab")` or `ArrowRight` for roving tabs.
 * @param {object} [options] - Optional indicator checks.
 * @param {import("@playwright/test").Locator} [options.indicator] - Element that draws the ring,
 * such as the label of a visually hidden input. Defaults to `locator`.
 * @param {string} [options.outlineColor] - Any CSS colour, for example `"var(--color-focus)"`.
 * When given, the indicator must be an outline of that colour.
 * @returns {Promise<void>} Resolves once the indicator is visible.
 */
export const expectFocusIndicator = async (locator, focus, { indicator = locator, outlineColor } = {}) => {
  // Read the indicator styles before focus.
  await expect(locator).not.toBeFocused();
  const baseline = await indicator.evaluate((element) => {
    const style = getComputedStyle(element);

    return {
      boxShadow: style.boxShadow,
      outlineColor: style.outlineColor,
      outlineStyle: style.outlineStyle,
      outlineWidth: style.outlineWidth,
    };
  });

  // Move focus with the keyboard.
  await focus();
  await expect(locator).toBeFocused();

  // Read the focused styles and name the indicator they draw compared with the baseline.
  const readFocusedState = async () => {
    const focusVisible = await locator.evaluate((element) => element.matches(":focus-visible"));
    const focused = await indicator.evaluate((element) => {
      const style = getComputedStyle(element);

      return {
        boxShadow: style.boxShadow,
        outlineColor: style.outlineColor,
        outlineStyle: style.outlineStyle,
        outlineWidth: style.outlineWidth,
      };
    });

    return {
      focusVisible,
      kind: getFocusIndicatorKind(baseline, focused),
      outlineColor: focused.outlineColor,
    };
  };

  // Check that a visible indicator appeared.
  await expect
    .poll(
      async () => {
        const { focusVisible, kind } = await readFocusedState();

        return { focusVisible, indicator: kind };
      },
      { message: "no visible focus indicator appeared on keyboard focus" },
    )
    .toEqual({ focusVisible: true, indicator: expect.stringMatching(/^(box-shadow|outline)$/) });
  if (outlineColor === undefined) {
    return;
  }

  // Resolve the expected outline colour where the indicator's custom properties apply.
  const expectedOutlineColor = await resolveCssColor(indicator, outlineColor);

  // Check that the indicator is an outline of that colour.
  await expect
    .poll(
      async () => {
        const { kind, outlineColor: focusedOutlineColor } = await readFocusedState();

        return { indicator: kind, outlineColor: focusedOutlineColor };
      },
      { message: `focus indicator is not a ${outlineColor} outline` },
    )
    .toEqual({ indicator: "outline", outlineColor: expectedOutlineColor });
};

// Most key presses a focus walk may take before its target must be focused.
const MAX_FOCUS_WALK_PRESSES = 80;

/**
 * Walks focus with the keyboard until the target is focused, so a focus check reaches a control
 * the way a keyboard user does. Pass it as the `expectFocusIndicator` focus callback.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {import("@playwright/test").Locator} target - Control that should receive focus.
 * @param {"Tab"|"Shift+Tab"} [key] - Key that moves focus.
 * @returns {Promise<void>} Resolves once the target is focused; rejects when the walk never
 * reaches it.
 */
export const pressKeyUntilFocused = async (page, target, key = "Tab") => {
  for (let press = 0; press < MAX_FOCUS_WALK_PRESSES; press += 1) {
    await page.keyboard.press(key);
    if (await target.evaluate((element) => element === document.activeElement)) {
      return;
    }
  }
  throw new Error(`${key} never reached the focus target`);
};

/**
 * Plays a one-finger horizontal swipe through the browser's touch input.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {number} fromX - Starting x coordinate.
 * @param {number} toX - Ending x coordinate.
 * @param {number} [y] - Vertical coordinate of the swipe.
 * @returns {Promise<void>} Resolves once the touch ends.
 */
export const swipeHorizontally = async (page, fromX, toX, y = 300) => {
  const session = await page.context().newCDPSession(page);
  const steps = 6;

  await session.send("Input.dispatchTouchEvent", {
    touchPoints: [{ x: fromX, y }],
    type: "touchStart",
  });
  for (let step = 1; step <= steps; step += 1) {
    await session.send("Input.dispatchTouchEvent", {
      touchPoints: [{ x: fromX + ((toX - fromX) * step) / steps, y }],
      type: "touchMove",
    });
  }
  await session.send("Input.dispatchTouchEvent", { touchPoints: [], type: "touchEnd" });
  await session.detach();
};

/**
 * Replaces the external basemap styles of both color themes (`styles/bright` and `styles/dark`)
 * with an empty style while keeping the real map runtime. With `attribution`, the style keeps one
 * empty source credited with that HTML, so maps render their attribution links without the network.
 */
export const routeEmptyBasemap = (page, { attribution } = {}) =>
  page.route(BASEMAP_STYLE_URL_PATTERN, (route) =>
    route.fulfill({
      headers: { "access-control-allow-origin": "*" },
      json: attribution
        ? {
            layers: [{ id: "attribution", source: "attribution", type: "circle" }],
            sources: {
              attribution: {
                attribution,
                data: { features: [], type: "FeatureCollection" },
                type: "geojson",
              },
            },
            version: 8,
          }
        : { layers: [], sources: {}, version: 8 },
    }),
  );

/** Adds query parameters to the next matching browser request. */
export const routeNextRequestWithQuery = async (page, urlIncludes, query) => {
  const queryParameters = new URLSearchParams(query);

  await page.route(
    `**${urlIncludes}*`,
    async (route) => {
      const requestUrl = new URL(route.request().url());

      for (const [name, value] of queryParameters) {
        requestUrl.searchParams.set(name, value);
      }

      await route.continue({ url: requestUrl.toString() });
    },
    { times: 1 },
  );
};

/**
 * Seeds `localStorage` entries before any page script runs, including the inline pre-paint
 * script. Each call writes its entries once, on the first navigation after it is registered, and
 * skips them on later navigations, so a write made during the test survives navigation. A later
 * call overrides an earlier one when a navigation separates them; init scripts run in no defined
 * order, so two calls must not seed the same key before a navigation.
 * @param {import("@playwright/test").Page} page - Page whose context gets the entries.
 * @param {Record<string, string | null>} entries - Values by key; `null` removes the key.
 * @returns {Promise<void>} Resolves once the init script is registered.
 */
export const seedLocalStorage = async (page, entries) => {
  await page.context().addInitScript(
    ({ markerPrefix, seedEntries, seedId }) => {
      // Opaque origins such as `about:blank` throw on any storage access.
      try {
        for (const [key, value] of Object.entries(seedEntries)) {
          const markerKey = `${markerPrefix}:${key}:${seedId}`;
          if (localStorage.getItem(markerKey) !== null) {
            continue;
          }
          localStorage.setItem(markerKey, "1");
          if (value === null) {
            localStorage.removeItem(key);
          } else {
            localStorage.setItem(key, value);
          }
        }
      } catch {
        // Nothing to seed where storage is unavailable.
      }
    },
    { markerPrefix: SEED_MARKER_PREFIX, seedEntries: entries, seedId: randomUUID() },
  );
};

/**
 * Sets up the color theme for the next navigations. Every project pins `colorScheme: "light"`,
 * so System renders light unless `system` changes it. Call it before navigating, and again before
 * the next navigation to switch to another stored value.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {object} [options] - Theme inputs; omitted ones keep their current value.
 * @param {"light" | "dark" | "system"} [options.stored] - Stored choice; `"system"` removes the key.
 * @param {"light" | "dark"} [options.system] - Emulated OS color scheme.
 * @returns {Promise<void>} Resolves once the inputs are in place.
 */
export const useTheme = async (page, { stored, system } = {}) => {
  if (system) {
    await page.emulateMedia({ colorScheme: system });
  }
  if (stored) {
    await seedLocalStorage(page, { [THEME_STORAGE_KEY]: stored === "system" ? null : stored });
  }
};

/**
 * Picks a color theme from the account menu (the account sheet on phones), waits for it to apply
 * and closes the menu again, as a live switch without a reload.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {"dark" | "light" | "system"} preference - Choice to pick.
 * @returns {Promise<void>} Resolves once the choice is applied and the menu is closed.
 */
export const pickThemeFromAccountMenu = async (page, preference) => {
  const userMenu = page.locator("#user-dropdown");
  await page.locator("#user-dropdown-button").click();
  await expect(userMenu).toBeVisible();
  const choice = userMenu
    .getByRole("group", { name: "Theme" })
    .getByRole("menuitemradio", { exact: true, name: THEME_CHOICE_LABELS[preference] });
  await choice.click();
  await expect(choice).toHaveAttribute("aria-checked", "true");
  if (preference !== "system") {
    await expect(page.locator("html")).toHaveAttribute("data-theme", preference);
  }
  await page.keyboard.press("Escape");
  await expect(userMenu).toBeHidden();
};

/**
 * Records every basemap style URL the page requests from now on, routed or not.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {string[]} Requested style URLs, in request order; the array fills as requests start.
 */
export const trackBasemapStyleRequests = (page) => {
  const requests = [];
  page.on("request", (request) => {
    if (BASEMAP_STYLE_URL_PATTERN.test(request.url())) {
      requests.push(request.url());
    }
  });
  return requests;
};

/**
 * Verifies the dark theme applied to the document.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>} Resolves once the root carries the dark theme.
 */
export const expectDarkTheme = (page) => expect(page.locator("html")).toHaveAttribute("data-theme", "dark");

/** Verifies loaded forward and backward pagination while preserving the first result. */
export const expectCurrentPaginationNavigation = async (page, resultSelector) => {
  // Capture the first result, the page position and the disabled boundary controls.
  const pagination = page.getByRole("group", { name: "Pagination" });
  const results = page.locator(resultSelector);
  const initialResult = (await results.first().innerText()).trim();
  await expect(initialResult).not.toEqual("");
  await expect(pagination.getByText(/^Page 1 of \d+$/)).toBeVisible();
  await expect(pagination.getByRole("button", { name: "First" })).toBeDisabled();
  await expect(pagination.getByRole("button", { name: "Prev" })).toBeDisabled();

  // Move forward and verify both link contracts and visible results change.
  const nextLink = pagination.getByRole("link", { name: "Next" });
  const lastLink = pagination.getByRole("link", { name: "Last" });
  await expect(nextLink).toHaveAttribute("href", /limit=1.*offset=1|offset=1.*limit=1/);
  await expect(nextLink).toHaveAttribute("hx-get", /limit=1.*offset=1|offset=1.*limit=1/);
  await expect(lastLink).toHaveAttribute("href", /limit=1.*offset=[1-9]\d*|offset=[1-9]\d*.*limit=1/);
  await expect(lastLink).toHaveAttribute("hx-get", /limit=1.*offset=[1-9]\d*|offset=[1-9]\d*.*limit=1/);
  const { matcher: nextMatcher, offsetParam } = await getPaginationNextMatcher(nextLink);
  await waitForActionResponse(page, () => nextLink.click(), nextMatcher);
  await expect.poll(async () => (await results.first().innerText()).trim()).not.toBe(initialResult);
  await expect(pagination.getByText(/^Page 2 of \d+$/)).toBeVisible();

  // Verify both backward controls point to the first result page.
  const firstLink = pagination.getByRole("link", { name: "First" });
  const previousLink = pagination.getByRole("link", { name: "Prev" });
  await expect(firstLink).toHaveAttribute("href", /limit=1.*offset=0|offset=0.*limit=1/);
  await expect(firstLink).toHaveAttribute("hx-get", /limit=1.*offset=0|offset=0.*limit=1/);
  await expect(previousLink).toHaveAttribute("href", /limit=1.*offset=0|offset=0.*limit=1/);

  // Return to the first page and verify the original result is restored.
  await waitForActionResponse(page, () => previousLink.click(), {
    ...nextMatcher,
    params: { [offsetParam]: "0" },
  });
  await expect.poll(async () => (await results.first().innerText()).trim()).toBe(initialResult);
  await expect(pagination.getByText(/^Page 1 of \d+$/)).toBeVisible();
};

/** Loads a page and verifies forward and backward pagination. */
export const expectPaginationNavigation = async (page, path, resultSelector) => {
  await navigateToPath(page, path);
  await expectCurrentPaginationNavigation(page, resultSelector);
};

/** Chooses a timezone from the custom timezone selector. */
export const selectTimezone = async (page, timezone) => {
  const timezoneSelector = page.locator('timezone-selector[name="timezone"]');
  await timezoneSelector.locator("#timezone-selector-button").click();

  const searchInput = timezoneSelector.locator("#timezone-search-input");
  await expect(searchInput).toBeVisible();
  await searchInput.fill(timezone);

  const option = timezoneSelector.getByRole("option", {
    name: timezone,
    exact: true,
  });
  await expect(option).toBeVisible();
  await option.click();

  await expect(timezoneSelector.locator('input[name="timezone"]')).toHaveValue(timezone);
};

/** Logs in with one of the pre-seeded e2e users. */
export const logInWithSeededUser = async (page, credentials) => {
  await navigateToPath(page, "/log-in");

  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  await page.getByLabel("Username").fill(credentials.username);
  await page.getByRole("textbox", { name: "Password required" }).fill(credentials.password);

  await submitSeededLogin(page);
};

/** Selects a community dashboard context for the logged-in user. */
export const selectCommunityContext = async (page, communityId) => {
  const response = await page.request.put(buildUrl(`/dashboard/community/${communityId}/select`));

  expect(response.status(), await response.text()).toBe(204);
};

/** Selects a group dashboard context for the logged-in user. */
export const selectGroupContext = async (page, communityId, groupId) => {
  const communityResponse = await page.request.put(
    buildUrl(`/dashboard/group/community/${communityId}/select`),
  );
  expect(communityResponse.status(), await communityResponse.text()).toBe(204);

  const groupResponse = await page.request.put(buildUrl(`/dashboard/group/${groupId}/select`));
  expect(groupResponse.status(), await groupResponse.text()).toBe(204);
};
