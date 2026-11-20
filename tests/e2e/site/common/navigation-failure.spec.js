import { expect, test } from "../../fixtures.js";

import { TEST_SITE_TITLE } from "../../seed.js";
import {
  buildE2eUrl,
  dismissAlert,
  expectDialogClosed,
  fulfillRateLimited,
  navigateToSiteHome,
  RATE_LIMIT_MESSAGE,
  waitForActionResponse,
  waitForResponseMatching,
} from "../../utils.js";
import { getAccountSheet } from "./helpers.js";

// Failed boosted navigations that show the generic message, with the answer each one gets.
const GENERIC_FAILURES = [
  { answer: (route) => route.abort(), name: "a network error", status: null },
  { answer: (route) => route.fulfill({ body: "", status: 500 }), name: "a server error", status: 500 },
];

// Alert shown when a navigation fails without the server's wait message.
const NAVIGATION_ERROR_MESSAGE = "Something went wrong loading the page. Please try again later.";

/** Selects the Explore link of the desktop header navigation. */
const getHeaderExploreLink = (page) =>
  page.getByRole("navigation", { name: "Main navigation" }).getByRole("link", { name: "Explore" });

/**
 * Routes a page's requests so HTMX requests get the given answer while document loads reach the
 * server, as a rate limit only some requests hit would.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {string} pathname - Path of the routed requests.
 * @param {(route: import("@playwright/test").Route) => Promise<void>} answer - Answer to HTMX requests.
 * @param {string} [header] - Request header that marks the HTMX requests to answer.
 * @returns {Promise<void>} Resolves once the route is registered.
 */
const routeHtmxRequests = (page, pathname, answer, header = "hx-request") =>
  page.route(
    (url) => url.pathname === pathname,
    (route) => (route.request().headers()[header] === "true" ? answer(route) : route.continue()),
  );

test.describe("failed boosted navigation", () => {
  test("keeps the page and shows the wait message when a navigation is rate-limited", async ({ page }) => {
    // Load the home page and hold the boosted Explore request until its pending state shows.
    await navigateToSiteHome(page);
    let releaseResponse;
    const responseReleased = new Promise((resolve) => {
      releaseResponse = resolve;
    });
    await routeHtmxRequests(page, "/explore", async (route) => {
      await responseReleased;
      await fulfillRateLimited(route);
    });

    // Follow the header link and verify it reports the pending navigation.
    const exploreLink = getHeaderExploreLink(page);
    const rejection = waitForResponseMatching(page, { method: "GET", pathname: "/explore", status: 429 });
    await exploreLink.click();
    await expect(exploreLink).toHaveAttribute("aria-busy", "true");
    releaseResponse();
    await rejection;

    // Verify the server's message, then the same page with the link no longer pending.
    await dismissAlert(page, { message: RATE_LIMIT_MESSAGE });
    await expect(page).toHaveURL(buildE2eUrl("/"));
    await expect(page).toHaveTitle(TEST_SITE_TITLE);
    await expect(exploreLink).not.toHaveAttribute("aria-busy", /.*/);
  });

  for (const { answer, name, status } of GENERIC_FAILURES) {
    test(`keeps the page and shows the generic message after ${name}`, async ({ page }) => {
      // Load the home page and fail the boosted Explore request.
      await navigateToSiteHome(page);
      await routeHtmxRequests(page, "/explore", answer);

      // Follow the header link, waiting for the failed response when one arrives.
      const exploreLink = getHeaderExploreLink(page);
      if (status) {
        await waitForActionResponse(page, () => exploreLink.click(), {
          method: "GET",
          pathname: "/explore",
          status,
        });
      } else {
        await exploreLink.click();
      }

      // Verify the generic message and the same page.
      await dismissAlert(page, { message: NAVIGATION_ERROR_MESSAGE });
      await expect(page).toHaveURL(buildE2eUrl("/"));
      await expect(page).toHaveTitle(TEST_SITE_TITLE);
    });
  }

  test("closes the account sheet before showing the wait message @mobile", async ({ page }) => {
    // Load the home page, reject the boosted Explore request and open the account sheet.
    await navigateToSiteHome(page);
    await routeHtmxRequests(page, "/explore", (route) => fulfillRateLimited(route));
    const { userButton, userMenu } = getAccountSheet(page);
    await userButton.click();
    await expect(userMenu).toBeVisible();

    // Follow the Explore row of the sheet.
    await waitForActionResponse(page, () => userMenu.getByRole("menuitem", { name: "Explore" }).click(), {
      method: "GET",
      pathname: "/explore",
      status: 429,
    });

    // Verify the sheet released the page before the alert, and focus returns to the trigger.
    await expectDialogClosed(page, userMenu);
    await dismissAlert(page, { message: RATE_LIMIT_MESSAGE });
    await expect(userButton).toBeFocused();
    await expect(page).toHaveURL(buildE2eUrl("/"));
  });

  test("reloads the page when Back finds no cached copy and its refetch is rate-limited", async ({
    page,
  }) => {
    // Reach Explore through the boosted header link, so HTMX owns the history entry of Home.
    await navigateToSiteHome(page);
    await waitForActionResponse(page, () => getHeaderExploreLink(page).click(), {
      method: "GET",
      pathname: "/explore",
      status: 200,
    });
    await expect(page).toHaveURL(/\/explore/);

    // Drop the cached copy of Home, mark this document, and reject the history refetch.
    await page.evaluate(() => {
      sessionStorage.removeItem("htmx-history-cache");
      window.__ocgBeforeReload = true;
    });
    await routeHtmxRequests(page, "/", (route) => fulfillRateLimited(route), "hx-history-restore-request");

    // Go back and wait for the rejected refetch and the reload that follows it.
    const rejection = waitForResponseMatching(page, { method: "GET", pathname: "/", status: 429 });
    const reloaded = page.waitForEvent("load");
    await page.goBack();
    await rejection;
    await reloaded;

    // Verify a new document shows Home.
    await expect(page).toHaveURL(buildE2eUrl("/"));
    await expect(page).toHaveTitle(TEST_SITE_TITLE);
    expect(await page.evaluate(() => window.__ocgBeforeReload)).toBeUndefined();
  });
});
