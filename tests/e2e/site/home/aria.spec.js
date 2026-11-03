import { expect, test } from "../../fixtures.js";

import { TEST_SITE_TITLE } from "../../seed.js";
import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToSiteHome } from "../../utils.js";

// The communities list and the event and group cards are left out: other tests add rows there.
test.describe("site home page ARIA snapshots", () => {
  test("matches the desktop introduction", async ({ page }) => {
    // Load the home page and check its layout.
    const introduction = await openSiteHome(page);

    // Capture the introduction; its stats are counts other tests change.
    await expectAriaSnapshot(page, introduction, "home-introduction");
  });

  test("matches the mobile introduction @mobile", async ({ page }) => {
    // Load the home page and check its layout.
    const introduction = await openSiteHome(page);

    // Capture the introduction; its stats are counts other tests change.
    await expectAriaSnapshot(page, introduction, "home-introduction");
  });
});

/** Opens the site home page, checks its layout and returns the introduction region. */
const openSiteHome = async (page) => {
  const introduction = page.getByRole("region", { name: "Site introduction" });
  await navigateToSiteHome(page);
  await expect(page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE })).toBeVisible();
  await expectPageLayout(page, { regions: [introduction] });
  return introduction;
};
