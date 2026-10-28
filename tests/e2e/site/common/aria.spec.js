import { expect, test } from "../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToPath } from "../../utils.js";
import { PUBLIC_PAGES } from "./public-pages.js";

// Badge pages replace the site header with the badge header, the same at every viewport.
const BADGE_PAGES = new Set(["badge credential", "badge verification"]);

// Untagged tests run on chromium-deep and @mobile ones on chromium-mobile-deep.
const VIEWPORTS = [
  { name: "desktop", tag: "" },
  { name: "mobile", tag: " @mobile" },
];

test.describe("public page layout and shell ARIA snapshots", () => {
  for (const publicPage of PUBLIC_PAGES) {
    for (const viewport of VIEWPORTS) {
      test(`${publicPage.name} keeps its ${viewport.name} layout and shell${viewport.tag}`, async ({
        page,
      }) => {
        const hasFooter = (publicPage.landmarks?.siteFooter ?? 1) > 0;
        const header = page.getByRole("banner");
        const footer = page.getByRole("contentinfo", { name: "Site footer" });

        // Load the seeded public page.
        await navigateToPath(page, publicPage.path);
        await expect(publicPage.ready(page)).toBeVisible({ timeout: 15_000 });

        // Verify the stylesheet applies and the shell fits the viewport.
        await expectPageLayout(page, {
          regions: [header, page.locator("#main-content"), ...(hasFooter ? [footer] : [])],
        });

        // Capture the header, whose navigation links collapse on mobile.
        await expectAriaSnapshot(page, header, getHeaderSnapshotName(publicPage.name, viewport.name));

        // Capture the footer shared by every page that renders it.
        if (hasFooter) {
          await expectAriaSnapshot(page, footer, "site-footer");
        }
      });
    }
  }
});

test.describe("not found page ARIA snapshots", () => {
  test("matches the desktop message", async ({ page }) => {
    // Load a missing page.
    const main = await openNotFound(page);

    // Capture the message and the way back home.
    await expectAriaSnapshot(page, main, "not-found-main");
  });

  test("matches the mobile message @mobile", async ({ page }) => {
    // Load a missing page.
    const main = await openNotFound(page);

    // Capture the message and the way back home.
    await expectAriaSnapshot(page, main, "not-found-main");
  });
});

/**
 * Names the header snapshot of a page. The site header collapses its navigation links on mobile,
 * and the home header also drops the logo link.
 */
const getHeaderSnapshotName = (pageName, viewport) => {
  if (BADGE_PAGES.has(pageName)) {
    return "badge-header";
  }
  return `${pageName === "home" ? "home" : "site"}-header-${viewport}`;
};

/** Opens a missing public page and returns its main content. */
const openNotFound = async (page) => {
  await navigateToPath(page, "/missing-public-page");
  await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeVisible();
  return page.locator("#main-content");
};
