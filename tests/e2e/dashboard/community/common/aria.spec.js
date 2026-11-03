import { expect, test } from "../../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { navigateToPath } from "../../../utils.js";
import { getDashboardMenu, getMobileNotice, setupAriaCommunity } from "../aria-helpers.js";

// Every community dashboard tab; on mobile they all show the mobile notice instead of the content.
const COMMUNITY_TABS = [
  "analytics",
  "contact",
  "event-categories",
  "group-categories",
  "groups",
  "logs",
  "regions",
  "settings",
  "team",
];

// The tabs' own aria.spec.js files cover their content, also in the mobile desktop version.
test.describe("community dashboard shell ARIA snapshots", () => {
  test("matches the desktop header and menu", async ({ adminCommunityPage, owned }) => {
    // Load the default tab of a temporary community.
    await setupAriaCommunity({ owned, page: adminCommunityPage });
    const header = adminCommunityPage.locator("#dashboard-header");
    const menu = getDashboardMenu(adminCommunityPage);
    await navigateToPath(adminCommunityPage, "/dashboard/community");
    await expect(adminCommunityPage.locator("#dashboard-content")).toBeVisible();
    await expectPageLayout(adminCommunityPage, {
      regions: [header, menu, adminCommunityPage.locator("#dashboard-main-content")],
    });

    // Capture the header with the user menu button.
    await expectAriaSnapshot(adminCommunityPage, header, "community-dashboard-header-desktop");

    // Capture the community selector and the menu sections of an admin, with the default tab current.
    await expectAriaSnapshot(adminCommunityPage, menu, "community-dashboard-menu-desktop");
  });

  test("matches the mobile header and notice @mobile", async ({ adminCommunityPage, owned }) => {
    // Load the default tab, which shows the mobile notice instead of the content.
    await setupAriaCommunity({ owned, page: adminCommunityPage });
    const header = adminCommunityPage.locator("#dashboard-header");
    const notice = getMobileNotice(adminCommunityPage);
    await navigateToPath(adminCommunityPage, "/dashboard/community");
    await expect(notice).toBeVisible();
    await expect(adminCommunityPage.locator("#dashboard-main-content")).toBeHidden();
    await expectPageLayout(adminCommunityPage, { regions: [header, notice] });

    // Capture the header without a menu button (no community section is offered on mobile),
    // and the notice pointing to the desktop version.
    await expectAriaSnapshot(adminCommunityPage, header, "community-dashboard-header-mobile");
    await expectAriaSnapshot(adminCommunityPage, notice, "community-dashboard-mobile-notice");
    await expect(adminCommunityPage.getByRole("button", { name: "Open dashboard menu" })).toHaveCount(0);
  });

  test("every tab fits the mobile viewport @mobile", async ({ adminCommunityPage }) => {
    const header = adminCommunityPage.locator("#dashboard-header");
    const main = adminCommunityPage.locator("#dashboard-main-content");
    const notice = getMobileNotice(adminCommunityPage);

    for (const tab of COMMUNITY_TABS) {
      await test.step(tab, async () => {
        // Load the tab of the seeded community with the most dashboard data.
        await navigateToPath(adminCommunityPage, `/dashboard/community?tab=${tab}`);

        // Verify the tab renders the mobile notice instead of its content, within the viewport.
        await expect(main).toBeHidden();
        await expectPageLayout(adminCommunityPage, { regions: [header, notice] });
      });
    }
  });
});
