import { expect, test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openCommunityDashboardView, setupAriaCommunity } from "../aria-helpers.js";

// Nested analytics tabs after the default Groups one: summary card label and section key.
const ANALYTICS_SECTIONS = [
  { key: "members", label: "Members" },
  { key: "events", label: "Events" },
  { key: "attendees", label: "Attendees" },
  { key: "page-views", label: "Page views" },
];

test.describe("community dashboard analytics ARIA snapshots", () => {
  test("matches the desktop views", async ({ adminCommunityPage, owned }) => {
    await expectAnalyticsViews({ owned, page: adminCommunityPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ adminCommunityPage, owned }) => {
    await enableDesktopVersion(adminCommunityPage);
    await expectAnalyticsViews({ owned, page: adminCommunityPage });
  });
});

/** Checks the layout of the analytics tab and its nested tabs, and captures them. */
const expectAnalyticsViews = async ({ owned, page }) => {
  await setupAriaCommunity({ owned, page });

  await test.step("analytics without data", async () => {
    // Load the analytics of a temporary community, whose statistics are all zero, and check the layout.
    const content = await openCommunityDashboardView(page, "tab=analytics");

    // Capture the title, the summary cards and the default Groups charts without data.
    await expectAriaSnapshot(page, content, "analytics-groups-empty");
  });

  for (const { key, label } of ANALYTICS_SECTIONS) {
    await test.step(`${label} nested tab`, async () => {
      // Open the nested tab from its summary card and check the layout.
      const section = page.locator(`[data-analytics-content="${key}"]`);
      await page.locator(`button[data-analytics-tab="${key}"]`).filter({ visible: true }).click();
      await expect(section).toBeVisible();
      await expectPageLayout(page, { regions: [section] });

      // Capture the section charts without data.
      await expectAriaSnapshot(page, section, `analytics-${key}-empty`);
    });
  }
};
