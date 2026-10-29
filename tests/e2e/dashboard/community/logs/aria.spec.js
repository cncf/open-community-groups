import { expect, test } from "../../../fixtures.js";

import { setupAuditLog } from "../../../data-graphs/audit.js";
import { setupTemporaryGroup } from "../../../data-graphs/groups.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openCommunityDashboardView, setupAriaCommunity } from "../aria-helpers.js";

// Fixed date of the owned audit log, so its row and details need no date regex.
const OWNED_LOG_CREATED_AT = "2025-03-14 18:30:00+00";

test.describe("community dashboard logs ARIA snapshots", () => {
  test("matches the desktop views", async ({ adminCommunityPage, owned }) => {
    await expectLogsViews({ owned, page: adminCommunityPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ adminCommunityPage, owned }) => {
    await enableDesktopVersion(adminCommunityPage);
    await expectLogsViews({ owned, page: adminCommunityPage });
  });
});

/** Checks the layout of the logs tab views and captures them. */
const expectLogsViews = async ({ owned, page }) => {
  const { communityId, groupCategoryId } = await setupAriaCommunity({ owned, page });

  await test.step("empty state", async () => {
    // Load the logs of a temporary community without audit history and check the layout.
    const content = await openCommunityDashboardView(page, "tab=logs");

    // Capture the title, the filters button, the column headers and the empty state.
    await expectAriaSnapshot(page, content, "logs-empty");
  });

  await test.step("filters dialog", async () => {
    // Load the logs filtered by an action, open the filters and check the layout.
    const dialog = page.getByRole("dialog", { name: "Filter logs" });
    await openCommunityDashboardView(page, "tab=logs&action=group_added");
    await page.getByRole("button", { name: "Filters" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the filter fields, with the action filter selected.
    await expectAriaSnapshot(page, dialog, "logs-filters-dialog");
  });

  // Give the community a group and the audit log of adding it. Audit logs are append-only, so the
  // log stays, as the logs of every dashboard action other tests take do.
  const { groupId } = setupTemporaryGroup({ communityId, groupCategoryId });
  setupGroupAddedLog({ communityId, groupId });

  await test.step("log row and details", async () => {
    // Load the owned log, open its details and check the layout.
    const table = page.getByRole("table", { name: "Audit logs table" });
    const row = table.getByRole("row").filter({ hasText: "Group added" });
    const details = row.locator("[data-audit-log-details-card]");
    await openCommunityDashboardView(page, "tab=logs", { regions: [table] });
    await row.getByRole("button", { name: "View log details" }).click();
    await expect(details).toBeVisible();
    await expectPageLayout(page, { regions: [details] });

    // Capture the table with the log row and its open details.
    await expectAriaSnapshot(page, table, "logs-table");
  });
};

/**
 * Records the first admin adding a group to the community on a fixed date, with details.
 * @param {{ communityId: string, groupId: string }} options - Community and group of the log.
 */
const setupGroupAddedLog = ({ communityId, groupId }) =>
  setupAuditLog({
    action: "group_added",
    actorUserId: TEST_USER_IDS.admin1,
    actorUsername: "e2e-admin-1",
    communityId,
    createdAt: OWNED_LOG_CREATED_AT,
    details: { region: "North America", status: "Active" },
    resourceId: groupId,
    resourceType: "group",
  });
