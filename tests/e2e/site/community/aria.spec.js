import { expect, test } from "../../fixtures.js";

import { TEST_COMMUNITY_DESCRIPTION, TEST_COMMUNITY_NAME, TEST_COMMUNITY_TITLE } from "../../seed.js";
import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToCommunityHome } from "../../utils.js";

// Event and group cards are left out: other tests add events and groups to the seeded community.
test.describe("community page ARIA snapshots", () => {
  test("matches the desktop regions", async ({ page }) => {
    // Load the community page and check its layout.
    const { about, breadcrumb } = await openCommunityHome(page);

    // Capture the breadcrumb links.
    await expectAriaSnapshot(page, breadcrumb, "community-breadcrumb-desktop");

    // Capture the about section; its stats are counts other tests change.
    await expectAriaSnapshot(page, about, "community-about");
  });

  test("matches the mobile regions @mobile", async ({ page }) => {
    // Load the community page and check its layout.
    const { about, breadcrumb } = await openCommunityHome(page);

    // Capture the breadcrumb, which collapses into a select on mobile.
    await expectAriaSnapshot(page, breadcrumb, "community-breadcrumb-mobile");

    // Capture the about section; its stats are counts other tests change.
    await expectAriaSnapshot(page, about, "community-about");
  });
});

/** Opens the seeded community page, checks its layout and returns its key regions. */
const openCommunityHome = async (page) => {
  const about = page.getByRole("region", { name: "About this community" });
  const breadcrumb = page.getByRole("navigation", { name: "Breadcrumb" });
  await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
  await expect(page.getByRole("heading", { level: 1, name: TEST_COMMUNITY_TITLE })).toBeVisible();
  await expect(about.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true })).toBeVisible();
  await expectPageLayout(page, { regions: [breadcrumb, about] });
  return { about, breadcrumb };
};
