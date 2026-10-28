import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";

const BASE_URL = process.env.OCG_E2E_BASE_URL || "http://127.0.0.1:9001";
const NAVIGATION_ASSET_TIMEOUT_MS = 5_000;
const NAVIGATION_RETRY_ATTEMPTS = 3;
const NAVIGATION_RETRY_DELAY_MS = 1_000;
const HTMX_SETTLE_TIMEOUT_MS = 10_000;
const ACTION_RESPONSE_BODY_PREVIEW_CHARS = 2_000;

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

/** Builds a fully-qualified URL. */
export const buildE2eUrl = (path) => buildUrl(path);

/** Selects a site or community stats container. */
export const getStatsContainer = (page, pageKind, viewport) => {
  const selector = viewport === "desktop" ? "div.hidden.lg\\:flex" : "div.grid.lg\\:hidden";

  return page
    .locator(selector)
    .filter({ has: page.getByText("Groups", { exact: true }) })
    .first();
};

/** Selects a stat value within a stats container. */
export const getStatValue = (statsContainer, statLabel) => {
  const labelElement = statsContainer.getByText(statLabel, { exact: true });
  const statBlock = labelElement.locator("..");

  return statBlock.locator(".lg\\:text-4xl");
};

/** Selects a section container from its visible heading. */
export const getSectionByHeading = (page, heading) =>
  page.getByText(heading, { exact: true }).locator("..").locator("..");

/** Selects a responsive link within a heading-based section. */
export const getSectionLink = (page, heading, linkName, viewport) => {
  const section = getSectionByHeading(page, heading);

  return viewport === "desktop"
    ? section.locator("div.hidden.md\\:flex").getByRole("link", { name: linkName })
    : section.locator("div.md\\:hidden").getByRole("link", { name: linkName });
};

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
 * Replaces the external basemap style with an empty style while keeping the real map runtime.
 * With `attribution`, the style keeps one empty source credited with that HTML, so maps
 * render their attribution links without the network.
 */
export const routeEmptyBasemap = (page, { attribution } = {}) =>
  page.route("https://tiles.openfreemap.org/styles/bright", (route) =>
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

/** Verifies loaded forward and backward pagination while preserving the first result. */
export const expectCurrentPaginationNavigation = async (page, resultSelector) => {
  // Capture the first result and initial disabled boundary controls.
  const pagination = page.locator(".pagination");
  const results = page.locator(resultSelector);
  const initialResult = (await results.first().innerText()).trim();
  await expect(initialResult).not.toEqual("");
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

  // Verify both backward controls point to the first result page.
  const firstLink = page.locator(".pagination").getByRole("link", {
    name: "First",
  });
  const previousLink = page.locator(".pagination").getByRole("link", {
    name: "Prev",
  });
  await expect(firstLink).toHaveAttribute("href", /limit=1.*offset=0|offset=0.*limit=1/);
  await expect(firstLink).toHaveAttribute("hx-get", /limit=1.*offset=0|offset=0.*limit=1/);
  await expect(previousLink).toHaveAttribute("href", /limit=1.*offset=0|offset=0.*limit=1/);

  // Return to the first page and verify the original result is restored.
  await waitForActionResponse(page, () => previousLink.click(), {
    ...nextMatcher,
    params: { [offsetParam]: "0" },
  });
  await expect.poll(async () => (await results.first().innerText()).trim()).toBe(initialResult);
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
