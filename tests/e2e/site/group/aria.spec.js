import { expect, test } from "../../fixtures.js";

import { TEST_COMMUNITY_NAME, TEST_GROUP_NAMES, TEST_GROUP_SLUGS } from "../../seed.js";
import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { getIntroSection, navigateToGroup } from "../../utils.js";

// Events, organizers and sponsors are left out: other tests add rows to the seeded group.
test.describe("group page ARIA snapshots", () => {
  test("matches the desktop regions", async ({ page }) => {
    // Load the group page and check its layout.
    const { breadcrumb, summary } = await openGroup(page);

    // Capture the breadcrumb links.
    await expectAriaSnapshot(page, breadcrumb, "group-breadcrumb-desktop");

    // Capture the summary; its member count and creation month vary.
    await expectAriaSnapshot(page, summary, "group-summary");
  });

  test("matches the mobile regions @mobile", async ({ page }) => {
    // Load the group page and check its layout.
    const { breadcrumb, summary } = await openGroup(page);

    // Capture the breadcrumb, which collapses into a select on mobile.
    await expectAriaSnapshot(page, breadcrumb, "group-breadcrumb-mobile");

    // Capture the summary; its member count and creation month vary.
    await expectAriaSnapshot(page, summary, "group-summary");
  });
});

/** Opens the seeded group page, checks its layout and returns its key regions. */
const openGroup = async (page) => {
  const breadcrumb = page.getByRole("navigation", { name: "Breadcrumb" });
  const summary = getIntroSection(page);
  await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
  await expect(page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha })).toBeVisible();
  await expectPageLayout(page, { regions: [breadcrumb, summary] });
  return { breadcrumb, summary };
};
