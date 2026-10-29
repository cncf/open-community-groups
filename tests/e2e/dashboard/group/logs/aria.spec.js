import { expect, test } from "../../../fixtures.js";

import { setupAuditLog } from "../../../data-graphs/audit.js";
import { cleanupGroupSponsor, setupGroupSponsor } from "../../../data-graphs/groups.js";
import { TEST_COMMUNITY_IDS, TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

// Fixed date of the owned audit log, so the snapshot matches its date literally.
const OWNED_LOG_CREATED_AT = "2025-03-14 18:30:00+00";

test.describe("group dashboard logs ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectLogsViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectLogsViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the logs tab views and captures them. */
const expectLogsViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });

  await test.step("empty state", async () => {
    // Load the logs of a temporary group without audit history and check the layout.
    const content = await openGroupDashboardView(page, "tab=logs");

    // Capture the title, the filters button, the column headers and the empty state.
    await expectAriaSnapshot(page, content, "logs-empty");
  });

  await test.step("filters dialog", async () => {
    // Load the logs filtered by an action, open the filters and check the layout.
    const dialog = page.getByRole("dialog", { name: "Filter logs" });
    await openGroupDashboardView(page, "tab=logs&action=group_sponsor_added");
    await page.getByRole("button", { name: "Filters" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the filter fields, with the action filter selected.
    await expectAriaSnapshot(page, dialog, "logs-filters-dialog");
  });

  // Give the group an owned sponsor and the audit log of adding it. Audit logs are append-only, so
  // the log stays, as the logs of every dashboard action other tests take do.
  const sponsor = owned.track(setupGroupSponsor({ groupId }), cleanupGroupSponsor);
  setupSponsorAddedLog({ groupId, sponsorId: sponsor.sponsorId });

  await test.step("log row and details", async () => {
    // Load the owned log, open its details and check the layout.
    const table = page.getByRole("table", { name: "Audit logs table" });
    const row = table.getByRole("row").filter({ hasText: "Group sponsor added" });
    const details = row.locator("[data-audit-log-details-card]");
    await openGroupDashboardView(page, "tab=logs", { regions: [table] });
    await row.getByRole("button", { name: "View log details" }).click();
    await expect(details).toBeVisible();
    await expectPageLayout(page, { regions: [details] });

    // Capture the table with the log row and its open details.
    await expectAriaSnapshot(page, table, "logs-table");
  });
};

/**
 * Records the organizer adding a group sponsor on a fixed date, with details.
 * @param {{ groupId: string, sponsorId: string }} options - Group and sponsor of the log.
 */
const setupSponsorAddedLog = ({ groupId, sponsorId }) =>
  setupAuditLog({
    action: "group_sponsor_added",
    actorUserId: TEST_USER_IDS.organizer1,
    actorUsername: "e2e-organizer-1",
    communityId: TEST_COMMUNITY_IDS.community1,
    createdAt: OWNED_LOG_CREATED_AT,
    details: { tier: "gold", website: "https://sponsor.example.com" },
    groupId,
    resourceId: sponsorId,
    resourceType: "group_sponsor",
  });
