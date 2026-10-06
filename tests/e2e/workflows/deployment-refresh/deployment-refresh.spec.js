import { expect, test } from "../../fixtures.js";

import { TEST_COMMUNITY_NAME, TEST_EVENT_NAMES, TEST_EVENT_SLUG, TEST_GROUP_SLUG } from "../../seed.js";
import {
  buildE2eUrl,
  navigateToPath,
  uniqueName,
  waitForActionResponse,
  waitForHtmxSettle,
} from "../../utils.js";

// Commit SHA advertised by pages that a shared cache kept from a previous deployment.
const STALE_COMMIT_SHA = "e2e-stale-build";
const COMMIT_SHA_META_PATTERN = /(<meta name="ocg-commit-sha" content=")[^"]*(")/;
const DEPLOYMENT_REFRESH_PARAM = "ocg_refresh";

// Session storage key mirrored from static/js/common/deployment-version.js.
const RELOADED_FROM_COMMIT_SHA_STORAGE_KEY = "ocg.deploymentReloadedFromCommitSha";

// User-facing deployment refresh copy.
const DIRTY_RELOAD_BLOCKED_MESSAGE =
  "A new version is live. Copy any unsaved work, then reload to pick up the update.";
const REFRESHED_MESSAGE = "This page was refreshed because a new version is available.";
const RELOAD_BLOCKED_MESSAGE =
  "A new version is live. This request did not complete. Reload to pick up the update.";
const RELOAD_PROMPT_MESSAGE =
  "A new version is available, but this page couldn't load it automatically. Reload to try again.";
const RESULTS_ERROR_MESSAGE = "Something went wrong loading results. Please try again later.";

const EXPLORE_EVENTS_PATH = `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`;
const EXPLORE_CALENDAR_PATH = `${EXPLORE_EVENTS_PATH}&view_mode=calendar`;
const GROUP_PATH = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`;
const DASHBOARD_EVENTS_PATH = "/dashboard/group?tab=events";
const PUBLIC_PATHS = [
  "/",
  EXPLORE_EVENTS_PATH,
  `/${TEST_COMMUNITY_NAME}`,
  GROUP_PATH,
  `${GROUP_PATH}/event/${TEST_EVENT_SLUG}`,
];

test.describe("deployment refresh", () => {
  test("reloads a stale page through a cache-busting URL", async ({ page }) => {
    // Serve the first document from a previous deployment, as a shared cache would.
    const staleDocuments = await serveStaleDocuments(page, { firstOnly: true });
    const refreshNavigation = page.waitForRequest(isDeploymentRefreshNavigation);

    // Load the stale page; its background user menu request is intercepted.
    await page.goto(buildE2eUrl(`${EXPLORE_EVENTS_PATH}#results`), { waitUntil: "domcontentloaded" });

    // The reload keeps the original query and bypasses the cache.
    const refreshUrl = new URL((await refreshNavigation).url());
    expect(refreshUrl.searchParams.get("entity")).toBe("events");
    expect(refreshUrl.searchParams.get("community[0]")).toBe(TEST_COMMUNITY_NAME);

    // The fresh page explains the refresh and drops the cache-busting parameter.
    await expect(page.locator(".swal2-popup")).toContainText(REFRESHED_MESSAGE);
    await expect(page.locator('meta[name="ocg-commit-sha"]')).not.toHaveAttribute(
      "content",
      STALE_COMMIT_SHA,
    );
    const currentUrl = new URL(page.url());
    expect(currentUrl.searchParams.has(DEPLOYMENT_REFRESH_PARAM)).toBe(false);
    expect(currentUrl.searchParams.get("entity")).toBe("events");
    expect(currentUrl.hash).toBe("#results");
    expect(staleDocuments.count).toBe(1);
  });

  test("offers a manual reload instead of looping when a reload returns the same version", async ({
    page,
  }) => {
    // Keep every document stale, as a shared cache that was not purged would.
    const staleDocuments = await serveStaleDocuments(page);
    await page.goto(buildE2eUrl(EXPLORE_EVENTS_PATH), { waitUntil: "domcontentloaded" });

    // The stale page reloads once, then offers a passive reload instead of reloading again.
    const prompt = page.locator(".swal2-popup").filter({ hasText: RELOAD_PROMPT_MESSAGE });
    await expect(prompt).toBeVisible();
    await waitForHtmxSettle(page);
    expect(staleDocuments.count).toBe(2);
    await expect(page.locator(".swal2-popup").filter({ hasText: RELOAD_BLOCKED_MESSAGE })).toHaveCount(0);
    await expect(page.locator(".swal2-popup").filter({ hasText: REFRESHED_MESSAGE })).toHaveCount(0);

    // The prompt does not block the page. It sits top-end and may cover the input's
    // center, so click near the input's left edge.
    const searchInput = page.getByPlaceholder("Search events");
    const searchInputBox = await searchInput.boundingBox();
    await searchInput.click({ position: { x: 8, y: searchInputBox.height / 2 } });
    await expect(searchInput).toBeFocused();
  });

  test("keeps the page when a user request is intercepted after a reload returned the same version", async ({
    page,
  }) => {
    // Load explore results before the loaded commit becomes stale.
    await navigateToPath(page, EXPLORE_EVENTS_PATH);
    const remoteEvent = page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true });
    await expect(remoteEvent).toBeVisible();
    await markPageAsStaleAfterReload(page);
    await markDocument(page);

    // Change a filter; the server intercepts the stale request instead of filtering.
    const response = await waitForActionResponse(page, () => checkKindFilter(page, "in-person"), {
      method: "GET",
      status: 204,
      urlIncludes: "/explore/events-section",
    });
    expect(response.headers()["hx-refresh"]).toBe("true");

    // The user is told the request did not complete, and the page stays in place.
    const prompt = page.locator(".swal2-popup").filter({ hasText: RELOAD_BLOCKED_MESSAGE });
    await expect(prompt).toBeVisible();
    await expect(remoteEvent).toBeVisible();
    expect(await isMarkedDocument(page)).toBe(true);

    // Reload from the prompt to load a fresh copy of the page.
    await Promise.all([
      page.waitForRequest(isDeploymentRefreshNavigation),
      page.waitForEvent("load"),
      prompt.getByRole("button", { name: "Reload" }).click(),
    ]);

    // The fresh page explains the refresh and clears the reload marker.
    expect(await isMarkedDocument(page)).toBe(false);
    await expect(page.locator('meta[name="ocg-commit-sha"]')).not.toHaveAttribute(
      "content",
      STALE_COMMIT_SHA,
    );
    await expect(page.locator(".swal2-popup")).toContainText(REFRESHED_MESSAGE);
    expect(new URL(page.url()).searchParams.has(DEPLOYMENT_REFRESH_PARAM)).toBe(false);
    expect(await readReloadedFromCommitSha(page)).toBeNull();
  });

  test("serves pages requested with the cache-busting parameter", async ({ organizerGroupPage, request }) => {
    // Public pages accept the cache-busting parameter.
    for (const path of PUBLIC_PATHS) {
      const response = await request.get(buildE2eUrl(withDeploymentRefreshParam(path)));
      expect(response.status(), path).toBe(200);
    }

    // Authenticated dashboard pages accept it without redirecting.
    const response = await organizerGroupPage.request.get(
      buildE2eUrl(withDeploymentRefreshParam(DASHBOARD_EVENTS_PATH)),
    );
    expect(response.status()).toBe(200);
    expect(new URL(response.url()).pathname).toBe("/dashboard/group");
  });

  test("refuses a manual reload while a dashboard form has unsaved changes", async ({
    organizerGroupPage,
  }) => {
    // Open the add form while the dashboard is current.
    await navigateToPath(organizerGroupPage, DASHBOARD_EVENTS_PATH);
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        organizerGroupPage.locator("#dashboard-content").getByRole("button", { name: "Add Event" }).click(),
      { method: "GET", urlIncludes: "/dashboard/group/events/add" },
    );

    // Make the page stale after a reload returned the same version, then intercept a background request.
    await markPageAsStaleAfterReload(organizerGroupPage);
    await organizerGroupPage.evaluate(() =>
      window.htmx.ajax("GET", window.location.pathname, { swap: "none" }),
    );
    const prompt = organizerGroupPage.locator(".swal2-popup").filter({ hasText: RELOAD_PROMPT_MESSAGE });
    await expect(prompt).toBeVisible();

    // Edit the form so it has visible pending changes.
    const eventName = uniqueName("Deployment Refresh Draft");
    await organizerGroupPage.locator("#name").fill(eventName);
    await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);
    await markDocument(organizerGroupPage);

    // Confirm the still-open prompt; the reload is refused to keep the draft.
    await prompt.getByRole("button", { name: "Reload" }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(DIRTY_RELOAD_BLOCKED_MESSAGE);
    await expect(organizerGroupPage.locator("#name")).toHaveValue(eventName);
    expect(await isMarkedDocument(organizerGroupPage)).toBe(true);
    expect(new URL(organizerGroupPage.url()).searchParams.has(DEPLOYMENT_REFRESH_PARAM)).toBe(false);
  });

  test("restores the reload prompt after a calendar error alert closes", async ({ page }) => {
    // Load the calendar, which renders its first month from embedded data.
    await navigateToPath(page, EXPLORE_CALENDAR_PATH);
    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(page.locator("#calendar-box .fc-daygrid-day").first()).toBeVisible();
    await markPageAsStaleAfterReload(page);

    // Move to the next month; the server intercepts the stale calendar fetch.
    const response = await waitForActionResponse(page, () => page.locator("#next-month-btn").click(), {
      method: "GET",
      status: 204,
      urlIncludes: "/explore/events/search",
    });
    expect(response.headers()["x-ocg-refresh"]).toBe("true");

    // The calendar error replaces the reload prompt.
    const popup = page.locator(".swal2-popup");
    await expect(popup).toContainText(RESULTS_ERROR_MESSAGE);

    // Closing the error brings the reload prompt back.
    await popup.getByRole("button", { name: "OK" }).click();
    await expect(popup.filter({ hasText: RELOAD_BLOCKED_MESSAGE })).toBeVisible();
    await expect(popup.getByRole("button", { name: "Reload" })).toBeVisible();
  });
});

/**
 * Checks an explore kind filter and dispatches the change that submits it.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} kind - Event kind filter value.
 * @returns {Promise<void>}
 */
const checkKindFilter = async (page, kind) => {
  await page
    .locator(`input[name="kind[]"][value="${kind}"]`)
    .first()
    .evaluate((input) => {
      if (!(input instanceof HTMLInputElement)) {
        throw new Error("kind filter input not found");
      }

      input.checked = true;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    });
};

/**
 * Returns whether a request is a deployment refresh page navigation.
 * @param {import("@playwright/test").Request} request - Browser request.
 * @returns {boolean} Whether the request loads a cache-busting page URL.
 */
const isDeploymentRefreshNavigation = (request) =>
  request.isNavigationRequest() && new URL(request.url()).searchParams.has(DEPLOYMENT_REFRESH_PARAM);

/**
 * Returns whether the current document still carries the test marker.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @returns {Promise<boolean>} Whether the page did not navigate since it was marked.
 */
const isMarkedDocument = (page) => page.evaluate(() => window.e2eDeploymentRefreshMarker === true);

/**
 * Marks the current document so later checks can prove it did not navigate.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @returns {Promise<void>}
 */
const markDocument = (page) =>
  page.evaluate(() => {
    window.e2eDeploymentRefreshMarker = true;
  });

/**
 * Makes the loaded page stale and records that an automatic reload already returned it.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @returns {Promise<void>}
 */
const markPageAsStaleAfterReload = async (page) => {
  await page.locator('meta[name="ocg-commit-sha"]').evaluate((meta, commitSha) => {
    meta.setAttribute("content", commitSha);
  }, STALE_COMMIT_SHA);
  await page.evaluate(
    ({ commitSha, storageKey }) => {
      window.sessionStorage.setItem(storageKey, commitSha);
    },
    { commitSha: STALE_COMMIT_SHA, storageKey: RELOADED_FROM_COMMIT_SHA_STORAGE_KEY },
  );
};

/**
 * Reads the commit SHA the last automatic deployment reload navigated away from.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @returns {Promise<string|null>} Stored commit SHA, or null when no reload is pending.
 */
const readReloadedFromCommitSha = (page) =>
  page.evaluate(
    (storageKey) => window.sessionStorage.getItem(storageKey),
    RELOADED_FROM_COMMIT_SHA_STORAGE_KEY,
  );

/**
 * Serves page documents with a stale commit SHA, as a cache holding old HTML would.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {{firstOnly?: boolean}} [options] - Whether only the first document is stale.
 * @returns {Promise<{count: number}>} Live count of stale documents served.
 */
const serveStaleDocuments = async (page, { firstOnly = false } = {}) => {
  const staleDocuments = { count: 0 };

  await page.route("**/*", async (route) => {
    const request = route.request();
    if (request.resourceType() !== "document" || (firstOnly && staleDocuments.count > 0)) {
      await route.fallback();
      return;
    }

    staleDocuments.count += 1;
    const response = await route.fetch();
    const body = (await response.text()).replace(COMMIT_SHA_META_PATTERN, `$1${STALE_COMMIT_SHA}$2`);
    await route.fulfill({ response, body });
  });

  return staleDocuments;
};

/**
 * Appends the deployment cache-busting parameter to a path.
 * @param {string} path - Relative page path.
 * @returns {string} Path with the cache-busting parameter.
 */
const withDeploymentRefreshParam = (path) =>
  `${path}${path.includes("?") ? "&" : "?"}${DEPLOYMENT_REFRESH_PARAM}=e2e`;
