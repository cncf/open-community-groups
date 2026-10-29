import { expect, test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot } from "../../../snapshots.js";
import { openCommunityDashboardView, setupAriaCommunity } from "../aria-helpers.js";

test.describe("community dashboard settings ARIA snapshots", () => {
  test("matches the desktop views", async ({ adminCommunityPage, owned }) => {
    await expectSettingsViews({ owned, page: adminCommunityPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ adminCommunityPage, owned }) => {
    await enableDesktopVersion(adminCommunityPage);
    await expectSettingsViews({ owned, page: adminCommunityPage });
  });
});

/** Checks the layout of the settings tab and captures its form. */
const expectSettingsViews = async ({ owned, page }) => {
  await test.step("settings form", async () => {
    // Load the settings of a temporary community and check the layout.
    const { displayName } = await setupAriaCommunity({ owned, page });
    const form = page.locator("#settings-form");
    await openCommunityDashboardView(page, "tab=settings", { regions: [form] });
    await expect(form.getByRole("textbox", { name: "Display Name *" })).toHaveValue(displayName);

    // Capture the general settings, branding, social links, advertisement and additional content sections.
    await expectAriaSnapshot(page, form, "settings-form");
  });
};
