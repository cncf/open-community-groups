import { test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot } from "../../../snapshots.js";
import { openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

test.describe("group dashboard analytics ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectAnalyticsViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectAnalyticsViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the analytics tab and captures it. */
const expectAnalyticsViews = async ({ owned, page }) => {
  await test.step("analytics without data", async () => {
    // Load the analytics of a temporary group, whose statistics are all zero, and check the layout.
    await setupAriaGroup({ owned, page });
    const content = await openGroupDashboardView(page, "tab=analytics");

    // Capture the title, the totals and the chart sections without data.
    await expectAriaSnapshot(page, content, "analytics-empty");
  });
};
