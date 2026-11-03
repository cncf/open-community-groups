import { expect, test } from "../../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { navigateToPath } from "../../../utils.js";
import { getDashboardMenu, getMobileNotice, setupAriaGroup } from "../aria-helpers.js";

// Every group dashboard tab; on mobile all but Check-In show the mobile notice instead of the content.
const GROUP_TABS = [
  "analytics",
  "artwork",
  "awards",
  "badges",
  "check-in",
  "cohosts",
  "events",
  "inbox",
  "logs",
  "members",
  "refunds",
  "settings",
  "sponsors",
  "team",
];

// The tabs' own aria.spec.js files cover their content, also in the mobile desktop version.
test.describe("group dashboard shell ARIA snapshots", () => {
  test("matches the desktop header and menu", async ({ organizerGroupPage, owned }) => {
    // Load the default tab of a temporary group, so the menu shows no inbox count.
    await setupAriaGroup({ owned, page: organizerGroupPage });
    const header = organizerGroupPage.locator("#dashboard-header");
    const menu = getDashboardMenu(organizerGroupPage);
    await navigateToPath(organizerGroupPage, "/dashboard/group");
    await expect(organizerGroupPage.locator("#dashboard-content")).toBeVisible();
    await expectPageLayout(organizerGroupPage, {
      regions: [header, menu, organizerGroupPage.locator("#dashboard-main-content")],
    });

    // Capture the header with the user menu button.
    await expectAriaSnapshot(organizerGroupPage, header, "group-dashboard-header-desktop");

    // Capture the selectors and the menu sections of an admin, with the default tab current.
    await expectAriaSnapshot(organizerGroupPage, menu, "group-dashboard-menu-desktop");
  });

  test("matches the mobile header, notice and menu drawer @mobile", async ({ organizerGroupPage, owned }) => {
    // Load the default tab, which shows the mobile notice instead of the content.
    await setupAriaGroup({ owned, page: organizerGroupPage });
    const header = organizerGroupPage.locator("#dashboard-header");
    const menu = getDashboardMenu(organizerGroupPage);
    const notice = getMobileNotice(organizerGroupPage);
    await navigateToPath(organizerGroupPage, "/dashboard/group");
    await expect(notice).toBeVisible();
    await expect(organizerGroupPage.locator("#dashboard-main-content")).toBeHidden();
    await expectPageLayout(organizerGroupPage, { regions: [header, notice] });

    // Capture the header with the menu button, and the notice pointing to the desktop version.
    await expectAriaSnapshot(organizerGroupPage, header, "group-dashboard-header-mobile");
    await expectAriaSnapshot(organizerGroupPage, notice, "group-dashboard-mobile-notice");

    // Open the menu drawer and capture it: the selectors and Check-In are offered on mobile.
    await organizerGroupPage.getByRole("button", { name: "Open dashboard menu" }).click();
    await expect(menu).toBeInViewport({ ratio: 1 });
    await expect(organizerGroupPage.locator("#dashboard-menu-backdrop")).toBeVisible();
    await expectPageLayout(organizerGroupPage, { regions: [menu] });
    await expectAriaSnapshot(organizerGroupPage, menu, "group-dashboard-menu-mobile");
  });

  test("every tab fits the mobile viewport @mobile", async ({ organizerGroupPage }) => {
    const header = organizerGroupPage.locator("#dashboard-header");
    const main = organizerGroupPage.locator("#dashboard-main-content");
    const notice = getMobileNotice(organizerGroupPage);

    for (const tab of GROUP_TABS) {
      await test.step(tab, async () => {
        // Load the tab of the seeded group with the most dashboard data.
        await navigateToPath(organizerGroupPage, `/dashboard/group?tab=${tab}`);

        // Verify Check-In renders its content and every other tab the mobile notice, within the viewport.
        if (tab === "check-in") {
          await expect(notice).toBeHidden();
          await expectPageLayout(organizerGroupPage, { regions: [header, main] });
        } else {
          await expect(main).toBeHidden();
          await expectPageLayout(organizerGroupPage, { regions: [header, notice] });
        }
      });
    }
  });
});
