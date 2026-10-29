import { expect, test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot } from "../../../snapshots.js";
import { openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

test.describe("group dashboard settings ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectSettingsViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectSettingsViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the settings tab and captures its form. */
const expectSettingsViews = async ({ owned, page }) => {
  await test.step("settings form", async () => {
    // Load the settings of a temporary group and check the layout.
    await setupAriaGroup({ owned, page });
    const form = page.locator("#groups-form");
    await openGroupDashboardView(page, "tab=settings", { regions: [form] });
    await expect(form.getByRole("textbox", { name: "Name *" })).toHaveValue(/E2E temporary group/);

    // Capture the group details, location, payments, social links, content and parent group sections.
    await expectAriaSnapshot(page, form, "settings-form");
  });
};
