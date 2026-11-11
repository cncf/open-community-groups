import { expect, test, testAtBothWidths } from "../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToPath } from "../../utils.js";
import { loadPublicPage, PUBLIC_PAGES } from "./public-pages.js";

// Badge pages replace the site header with the badge header, the same at every viewport.
const BADGE_PAGES = new Set(["badge credential", "badge verification"]);

// These pages load no user menu, so the phone header has no menu button.
const NO_USER_MENU_PAGES = new Set(["login", "sign-up"]);

test.describe("public page layout and shell ARIA snapshots", () => {
  for (const publicPage of PUBLIC_PAGES) {
    testAtBothWidths(`${publicPage.name} keeps its layout and shell`, async ({ isMobile, page }) => {
      const hasFooter = (publicPage.landmarks?.siteFooter ?? 1) > 0;
      const header = page.getByRole("banner");
      const footer = page.getByRole("contentinfo", { name: "Site footer" });

      // Load the seeded public page.
      await loadPublicPage(page, publicPage);

      // Verify the stylesheet applies and the shell fits the viewport.
      await expectPageLayout(page, {
        regions: [header, page.locator("#main-content"), ...(hasFooter ? [footer] : [])],
      });

      // Capture the header, whose navigation links collapse on mobile.
      await expectAriaSnapshot(
        page,
        header,
        getHeaderSnapshotName(publicPage.name, isMobile ? "mobile" : "desktop"),
      );

      // Capture the footer shared by every page that renders it.
      if (hasFooter) {
        await expectAriaSnapshot(page, footer, "site-footer");
      }
    });
  }
});

test.describe("not found page ARIA snapshots", () => {
  testAtBothWidths("matches the message", async ({ page }) => {
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
  if (viewport === "mobile" && NO_USER_MENU_PAGES.has(pageName)) {
    return "auth-header-mobile";
  }
  return `${pageName === "home" ? "home" : "site"}-header-${viewport}`;
};

/** Opens a missing public page and returns its main content. */
const openNotFound = async (page) => {
  await navigateToPath(page, "/missing-public-page");
  await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeVisible();
  return page.locator("#main-content");
};
