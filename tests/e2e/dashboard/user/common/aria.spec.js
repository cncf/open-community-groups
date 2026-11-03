import { expect, test } from "../../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { navigateToPath } from "../../../utils.js";
import { getDashboardMenu, getMobileNotice } from "../aria-helpers.js";

// Every user dashboard tab; on mobile all but Check-In show the mobile notice instead of the content.
const USER_TABS = [
  "account",
  "badges",
  "check-in",
  "events",
  "groups",
  "inbox",
  "invitations",
  "logs",
  "notifications",
  "purchases",
  "session-proposals",
  "submissions",
  "surveys",
];

// The tabs' own aria.spec.js files cover their content, also in the mobile desktop version.
test.describe("user dashboard shell ARIA snapshots", () => {
  test("matches the desktop header and menu", async ({ emptyUserPage }) => {
    // Load the default tab as a user without data, so the menu shows no survey count.
    const header = emptyUserPage.locator("#dashboard-header");
    const menu = getDashboardMenu(emptyUserPage);
    await navigateToPath(emptyUserPage, "/dashboard/user");
    await expect(emptyUserPage.locator("#user-details-form")).toBeVisible();
    await expectPageLayout(emptyUserPage, {
      regions: [header, menu, emptyUserPage.locator("#dashboard-content")],
    });

    // Capture the header with the user menu button.
    await expectAriaSnapshot(emptyUserPage, header, "user-dashboard-header-desktop");

    // Capture the menu sections, with Profile marked as the current tab.
    await expectAriaSnapshot(emptyUserPage, menu, "user-dashboard-menu-desktop");
  });

  test("matches the mobile header, notice and menu drawer @mobile", async ({ emptyUserPage }) => {
    // Load the default tab, which shows the mobile notice instead of the content.
    const header = emptyUserPage.locator("#dashboard-header");
    const menu = getDashboardMenu(emptyUserPage);
    const notice = getMobileNotice(emptyUserPage);
    await navigateToPath(emptyUserPage, "/dashboard/user");
    await expect(notice).toBeVisible();
    await expect(emptyUserPage.locator("#dashboard-main-content")).toBeHidden();
    await expectPageLayout(emptyUserPage, { regions: [header, notice] });

    // Capture the header with the menu button, and the notice pointing to the desktop version.
    await expectAriaSnapshot(emptyUserPage, header, "user-dashboard-header-mobile");
    await expectAriaSnapshot(emptyUserPage, notice, "user-dashboard-mobile-notice");

    // Open the menu drawer and capture it: only Check-In is offered on mobile.
    await emptyUserPage.getByRole("button", { name: "Open dashboard menu" }).click();
    await expect(menu).toBeInViewport({ ratio: 1 });
    await expect(emptyUserPage.locator("#dashboard-menu-backdrop")).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [menu] });
    await expectAriaSnapshot(emptyUserPage, menu, "user-dashboard-menu-mobile");
  });

  test("every tab fits the mobile viewport @mobile", async ({ member1Page }) => {
    const header = member1Page.locator("#dashboard-header");
    const main = member1Page.locator("#dashboard-main-content");
    const notice = getMobileNotice(member1Page);

    for (const tab of USER_TABS) {
      await test.step(tab, async () => {
        // Load the tab as the user with the most dashboard data.
        await navigateToPath(member1Page, `/dashboard/user?tab=${tab}`);

        // Verify Check-In renders its content and every other tab the mobile notice, within the viewport.
        if (tab === "check-in") {
          await expect(notice).toBeHidden();
          await expectPageLayout(member1Page, { regions: [header, main] });
        } else {
          await expect(main).toBeHidden();
          await expectPageLayout(member1Page, { regions: [header, notice] });
        }
      });
    }
  });
});
