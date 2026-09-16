import { randomUUID } from "node:crypto";
import { expect } from "@playwright/test";

const BASE_URL = process.env.OCG_E2E_BASE_URL || "http://127.0.0.1:9001";
const LOGIN_NAVIGATION_TIMEOUT_MS = 5_000;
const LOGIN_RETRY_ATTEMPTS = 3;
const NAVIGATION_ASSET_TIMEOUT_MS = 5_000;
const NAVIGATION_ATTEMPT_TIMEOUT_MS = 15_000;
const NAVIGATION_RETRY_ATTEMPTS = 12;
const NAVIGATION_RETRY_DELAY_MS = 1_000;
const HTMX_SETTLE_TIMEOUT_MS = 10_000;
const ACTION_RESPONSE_BODY_PREVIEW_CHARS = 2_000;

/** Builds an absolute E2E URL for a relative path. */
const buildUrl = (path) => new URL(path, BASE_URL).toString();

/** Waits before retrying a navigation while the test server is starting. */
const waitForNavigationRetry = () =>
  new Promise((resolve) => {
    setTimeout(resolve, NAVIGATION_RETRY_DELAY_MS);
  });

/** Waits for the shared stylesheet and HTMX runtime required by every page. */
const waitForApplicationAssets = async (page) => {
  try {
    await page.waitForFunction(
      () => {
        const applicationStylesheet = document.querySelector(
          'link[rel="stylesheet"][href^="/static/css/styles."][href$=".css"]',
        );

        return Boolean(applicationStylesheet?.sheet && window.htmx);
      },
      undefined,
      { timeout: NAVIGATION_ASSET_TIMEOUT_MS },
    );
  } catch (error) {
    throw new Error("Application assets did not load", { cause: error });
  }
};

/** Checks whether a navigation error is caused by a temporarily missing server. */
const isServerUnavailableNavigationError = (error) => {
  const message = String(error?.message || error);
  const isNavigationTimeout = error?.name === "TimeoutError" && message.includes("page.goto");

  return (
    isNavigationTimeout ||
    message.includes("Could not connect to the server") ||
    message.includes("Application assets did not load") ||
    message.includes("ERR_CONNECTION_RESET") ||
    message.includes("ERR_CONNECTION_REFUSED") ||
    message.includes("ERR_NETWORK_IO_SUSPENDED") ||
    message.includes("Navigation completed without a server response") ||
    message.includes("NS_ERROR_NET_EMPTY_RESPONSE") ||
    message.includes("NS_ERROR_NET_RESET") ||
    message.includes("NS_ERROR_CONNECTION_REFUSED") ||
    message.includes("ECONNRESET") ||
    message.includes("ECONNREFUSED")
  );
};

/** Navigates to a URL and tolerates brief server restarts during E2E runs. */
const navigateToUrl = async (page, url) => {
  let lastError;

  for (let attempt = 1; attempt <= NAVIGATION_RETRY_ATTEMPTS; attempt += 1) {
    try {
      const response = await page.goto(url, {
        timeout: NAVIGATION_ATTEMPT_TIMEOUT_MS,
        waitUntil: "domcontentloaded",
      });

      if (!response) {
        throw new Error("Navigation completed without a server response");
      }

      await waitForApplicationAssets(page);
      return;
    } catch (error) {
      lastError = error;

      if (attempt === NAVIGATION_RETRY_ATTEMPTS || !isServerUnavailableNavigationError(error)) {
        throw error;
      }

      await waitForNavigationRetry();
    }
  }

  throw lastError;
};

/** Submits the login form and retries when navigation does not start. */
const submitSeededLogin = async (page) => {
  let lastError;

  for (let attempt = 1; attempt <= LOGIN_RETRY_ATTEMPTS; attempt += 1) {
    try {
      await Promise.all([
        page.waitForURL((url) => !url.pathname.includes("/log-in"), {
          timeout: LOGIN_NAVIGATION_TIMEOUT_MS,
        }),
        page.getByRole("button", { name: "Sign In" }).click(),
      ]);

      return;
    } catch (error) {
      lastError = error;

      if (attempt === LOGIN_RETRY_ATTEMPTS || page.isClosed()) {
        throw error;
      }
    }
  }

  throw lastError;
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

/** Selects the stable intro section used by community, group, and event pages. */
export const getIntroSection = (page) =>
  page
    .getByRole("heading", { level: 1 })
    .locator("xpath=ancestor::div[parent::div[contains(@class,'gap-y-6')]][1]");

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
 * Returns a `datetime-local` string a number of days in the future at a fixed hour.
 * @param {{ days: number, hour?: number }} options - Offset from today and optional hour (default 10).
 * @returns {string} Value such as `2031-05-10T10:00` accepted by `<input type="datetime-local">`.
 */
export const futureDate = ({ days, hour = 10 }) => {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + days);
  const yyyy = date.getUTCFullYear();
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(date.getUTCDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}T${String(hour).padStart(2, "0")}:00`;
};

/** Navigates to the site home page. */
export const navigateToSiteHome = async (page) => {
  await navigateToUrl(page, buildUrl("/"));
};

/** Navigates to the site explore page. */
export const navigateToSiteExplore = async (page) => {
  await navigateToUrl(page, buildUrl("/explore"));
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

/** Navigates to a specific path. */
export const navigateToPath = async (page, path) => {
  await navigateToUrl(page, buildUrl(path));
};

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
 * Runs an action and waits for the response matching method and URL, then asserts its status.
 * Matching on the request contract first makes a wrong status fail immediately with the
 * response body instead of timing out. Status defaults to any successful response.
 */
export const waitForActionResponse = async (page, action, { method, urlIncludes, urlEndsWith, status }) => {
  const [response] = await Promise.all([
    page.waitForResponse(
      (candidate) =>
        candidate.request().method() === method &&
        (!urlIncludes || candidate.url().includes(urlIncludes)) &&
        (!urlEndsWith || candidate.url().endsWith(urlEndsWith)),
    ),
    action(),
  ]);

  const statusMatches = status === undefined ? response.ok() : response.status() === status;

  if (!statusMatches) {
    const body = await response.text().catch(() => "<body unavailable>");

    throw new Error(
      `Expected ${method} ${response.url()} to respond with ${status ?? "a 2xx status"} but received ` +
        `${response.status()}.\n${body.slice(0, ACTION_RESPONSE_BODY_PREVIEW_CHARS)}`,
    );
  }

  await waitForHtmxSettle(page);

  return response;
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
  await Promise.all([
    page.waitForResponse((response) => {
      const searchParams = new URL(response.url()).searchParams;
      const hasNextOffset = [...searchParams.entries()].some(
        ([key, value]) => key.endsWith("offset") && value === "1",
      );

      return response.request().method() === "GET" && hasNextOffset && response.ok();
    }),
    nextLink.click(),
  ]);
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
  await Promise.all([
    page.waitForResponse((response) => {
      const searchParams = new URL(response.url()).searchParams;
      const hasFirstOffset = [...searchParams.entries()].some(
        ([key, value]) => key.endsWith("offset") && value === "0",
      );

      return response.request().method() === "GET" && hasFirstOffset && response.ok();
    }),
    previousLink.click(),
  ]);
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

  expect(response.ok()).toBeTruthy();
};

/** Selects a group dashboard context for the logged-in user. */
export const selectGroupContext = async (page, communityId, groupId) => {
  const communityResponse = await page.request.put(
    buildUrl(`/dashboard/group/community/${communityId}/select`),
  );
  expect(communityResponse.ok()).toBeTruthy();

  const groupResponse = await page.request.put(buildUrl(`/dashboard/group/${groupId}/select`));
  expect(groupResponse.ok()).toBeTruthy();
};
