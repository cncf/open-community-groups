import { expect, test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// Seeded session proposal log of the first member, listed second when sorted oldest first; logs
// that other tests add come after the seeded ones.
const SEEDED_PROPOSAL_LOG = "Cloud Native Operations Deep Dive";

test.describe("user dashboard logs ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member1Page }) => {
    await expectLogsViews({ emptyUserPage, member1Page });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ emptyUserPage, member1Page }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member1Page);
    await expectLogsViews({ emptyUserPage, member1Page });
  });
});

/** Checks the layout of the logs tab views and captures them. */
const expectLogsViews = async ({ emptyUserPage, member1Page }) => {
  await test.step("empty state", async () => {
    // Load the logs of a user without audit history and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=logs");

    // Capture the title, the filters button, the column headers and the empty state.
    await expectAriaSnapshot(emptyUserPage, content, "logs-empty");
  });

  await test.step("filters dialog", async () => {
    // Load the logs filtered by an action, open the filters and check the layout.
    const dialog = emptyUserPage.getByRole("dialog", { name: "Filter logs" });
    await openUserDashboardView(emptyUserPage, "tab=logs&action=user_details_updated");
    await emptyUserPage.getByRole("button", { name: "Filters" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [dialog] });

    // Capture the filter fields, with the action filter selected.
    await expectAriaSnapshot(emptyUserPage, dialog, "logs-filters-dialog");
  });

  await test.step("log details", async () => {
    // Load the first member's logs oldest first and open the seeded proposal log details.
    const content = await openUserDashboardView(member1Page, "tab=logs&sort=created-asc");
    const row = content.getByRole("row").filter({ hasText: SEEDED_PROPOSAL_LOG }).first();
    const details = row.locator("[data-audit-log-details-card]");
    await row.getByRole("button", { name: "View log details" }).click();
    await expect(details).toBeVisible();
    await expectPageLayout(member1Page, { regions: [details] });

    // Capture the detail fields of the seeded log.
    await expectAriaSnapshot(member1Page, details, "logs-details");
  });
};
