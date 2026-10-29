import { expect, test } from "../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToPath } from "../../utils.js";

test.describe("site stats page ARIA snapshots", () => {
  test("matches the desktop totals", async ({ page }) => {
    // Load the stats page and check its layout.
    const main = await openStats(page);

    // Capture the heading and totals; the totals are counts other tests change.
    await expectAriaSnapshot(page, main, "stats-main");
  });

  test("matches the mobile totals @mobile", async ({ page }) => {
    // Load the stats page and check its layout.
    const main = await openStats(page);

    // Capture the heading and totals; the totals are counts other tests change.
    await expectAriaSnapshot(page, main, "stats-main");
  });
});

/** Opens the stats page, checks its layout and returns the main content. */
const openStats = async (page) => {
  const main = page.locator("#main-content");
  await navigateToPath(page, "/stats");
  await expect(main.getByText("Global growth trends across all communities.", { exact: true })).toBeVisible();
  await expectPageLayout(page, { regions: [main] });
  return main;
};
