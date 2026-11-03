import { expect, test } from "../../../fixtures.js";

import { cleanupGroupSponsor, setupGroupSponsor } from "../../../data-graphs/groups.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

test.describe("group dashboard sponsors ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectSponsorsViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectSponsorsViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the sponsors tab views and captures them. */
const expectSponsorsViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });

  await test.step("empty state", async () => {
    // Load the sponsors of a temporary group without sponsors and check the layout.
    const content = await openGroupDashboardView(page, "tab=sponsors");

    // Capture the title, the add button, the column headers and the empty state.
    await expectAriaSnapshot(page, content, "sponsors-empty");
  });

  await test.step("add sponsor form", async () => {
    // Open the add form and check the layout.
    const form = page.locator("#sponsor-form");
    await page.getByRole("button", { name: "Add Sponsor" }).click();
    await expect(form.getByRole("button", { name: "Add Sponsor" })).toBeVisible();
    await expectPageLayout(page, { regions: [form] });

    // Capture the empty sponsor fields and the form actions.
    await expectAriaSnapshot(page, form, "sponsors-add-form");
  });

  const sponsor = owned.track(setupGroupSponsor({ groupId }), cleanupGroupSponsor);

  await test.step("sponsors list", async () => {
    // Load the owned featured sponsor and check the layout.
    const table = page.getByRole("table", { name: "Sponsors list" });
    await openGroupDashboardView(page, "tab=sponsors", { regions: [table] });

    // Capture the column headers and the sponsor row with its actions.
    await expectAriaSnapshot(page, table, "sponsors-list");
  });

  await test.step("update sponsor form", async () => {
    // Open the update form of the owned sponsor and check the layout.
    const form = page.locator("#sponsor-form");
    await page.getByRole("button", { name: `Edit sponsor: ${sponsor.name}` }).click();
    await expect(form.getByRole("button", { name: "Update Sponsor" })).toBeVisible();
    await expectPageLayout(page, { regions: [form] });

    // Capture the fields filled with the sponsor.
    await expectAriaSnapshot(page, form, "sponsors-update-form");
  });
};
