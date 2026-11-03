import { expect } from "@playwright/test";

import { buildE2eUrl, waitForHtmxSettle } from "./utils.js";

// File extension of ARIA snapshot files, required by `toMatchAriaSnapshot({ name })`.
const ARIA_SNAPSHOT_EXTENSION = ".aria.yml";
// Event attendance controls hydrate through a plain fetch after the page loads.
const ATTENDANCE_READY_TIMEOUT_MS = 10_000;
// Cookie the user menu sets to load the desktop version (see static/js/common/viewport-mode.js).
const DESKTOP_VERSION_COOKIE = { name: "ocg_viewport_mode", value: "desktop" };
// Subpixel rounding allowed when comparing region edges with the viewport.
const LAYOUT_EDGE_TOLERANCE_PX = 0.5;

/**
 * Makes the pages of a context load in the desktop version, as the user menu's "Desktop version"
 * item does: the page lays out at 1280px on mobile and dashboards render their content instead of
 * the mobile notice. Call it before navigating; the context keeps the cookie until it closes.
 * @param {import("@playwright/test").Page} page - Page whose context loads the desktop version.
 */
export const enableDesktopVersion = async (page) => {
  await page.context().addCookies([{ ...DESKTOP_VERSION_COOKIE, url: buildE2eUrl("/") }]);
};

/**
 * Waits for the page to settle, then matches a region's accessibility tree against the
 * `<name>.aria.yml` file next to the spec (`<spec>-snapshots/`, see `playwright.config.js`).
 * Snapshots catch structure, roles, accessible names, text and link targets, not styling.
 * Dynamic values (counts, dates, times) are kept out by region choice or matched with
 * regexes in the file; see the README "ARIA snapshots" section.
 * @param {import("@playwright/test").Page} page - Page showing the region.
 * @param {import("@playwright/test").Locator} region - Region to snapshot; one element.
 * @param {string} name - Snapshot name without extension, unique within the spec file.
 */
export const expectAriaSnapshot = async (page, region, name) => {
  await waitForPageSettled(page);
  await expect(region).toBeVisible();
  await expect(region).toMatchAriaSnapshot({ name: `${name}${ARIA_SNAPSHOT_EXTENSION}` });
};

/**
 * Asserts the platform-independent layout of the current page: the application stylesheet
 * applies, nothing overflows the viewport horizontally, and every key region is visible and
 * horizontally inside the viewport.
 * @param {import("@playwright/test").Page} page - Page already loaded.
 * @param {{ regions?: import("@playwright/test").Locator[] }} [options] - Key regions, one
 *   element each.
 */
export const expectPageLayout = async (page, { regions = [] } = {}) => {
  await waitForPageSettled(page);

  // Verify the stylesheet applies: the skip link is visually hidden by the `sr-only` utility.
  const stylesheetApplies = await page.evaluate(() => {
    const skipLink = document.querySelector('a.sr-only[href^="#"]');
    if (!skipLink) {
      return false;
    }
    const style = getComputedStyle(skipLink);
    return style.position === "absolute" && skipLink.getBoundingClientRect().width <= 1;
  });
  expect(stylesheetApplies, "the application stylesheet hides the skip link (sr-only)").toBe(true);

  // Verify the page does not scroll horizontally at this viewport.
  const { innerWidth, scrollWidth } = await page.evaluate(() => ({
    innerWidth: window.innerWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }));
  expect(scrollWidth, `document width fits the ${innerWidth}px viewport`).toBeLessThanOrEqual(innerWidth);

  // Verify every key region is visible and horizontally inside the viewport.
  for (const region of regions) {
    await expect(region).toBeVisible();
    const box = await region.boundingBox();
    expect(box, `${region} has a layout box`).not.toBeNull();
    expect(box.x, `${region} starts inside the viewport`).toBeGreaterThanOrEqual(-LAYOUT_EDGE_TOLERANCE_PX);
    expect(box.x + box.width, `${region} ends inside the ${innerWidth}px viewport`).toBeLessThanOrEqual(
      innerWidth + LAYOUT_EDGE_TOLERANCE_PX,
    );
  }
};

/**
 * Waits for the work that changes a page after load: HTMX swaps and the event attendance
 * controls leaving their "Checking..." state.
 * @param {import("@playwright/test").Page} page - Page already loaded.
 */
export const waitForPageSettled = async (page) => {
  await page.waitForLoadState("load");
  await waitForHtmxSettle(page);
  await waitForAttendanceReady(page);
};

/**
 * Waits for event attendance controls to leave the "Checking..." state. Availability loads
 * through a plain fetch that the HTMX settle wait does not track, so wait for every container
 * to be hydrated and its loading button hidden, then settle the follow-up HTMX re-check.
 * Pages without attendance controls return at once.
 * @param {import("@playwright/test").Page} page - Page already loaded.
 */
const waitForAttendanceReady = async (page) => {
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll("[data-attendance-container]")].every((container) => {
        const loadingButton = container.querySelector('[data-attendance-role="loading-btn"]');
        return (
          container.dataset.availabilityHydrated !== "false" &&
          (!loadingButton || loadingButton.classList.contains("hidden"))
        );
      }),
    undefined,
    { timeout: ATTENDANCE_READY_TIMEOUT_MS },
  );
  await waitForHtmxSettle(page);
};
