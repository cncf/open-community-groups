import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const COMMUNITY_LOGS_PATH = "/dashboard/community?tab=logs";
const FILTERED_COMMUNITY_LOGS_PATH =
  "/dashboard/community?tab=logs&action=community_updated&actor=e2e-admin-1";
const COMMUNITY_DETAILS_LOGS_PATH =
  "/dashboard/community?tab=logs&action=group_added&actor=e2e-admin-1";

test.describe("community dashboard logs view", () => {
  test("admin can view the seeded community logs list and active filters", async ({
    adminCommunityPage,
  }) => {
    // Load the filtered community logs URL.
    await navigateToPath(adminCommunityPage, FILTERED_COMMUNITY_LOGS_PATH);

    // Verify the filtered log row and durable filter URL.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Logs", { exact: true }),
    ).toBeVisible();
    await expect(adminCommunityPage).toHaveURL(
      /\/dashboard\/community\?tab=logs&action=community_updated&actor=e2e-admin-1/,
    );

    // Find the audit log row.
    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();
    await expect(auditLogRow).toContainText("Community updated");
    await expect(auditLogRow).toContainText("e2e-admin-1");
    await expect(auditLogRow).toContainText("Platform Engineering Community");

    // Open the filters modal and verify the active filters.
    await adminCommunityPage.getByRole("button", { name: "Filters" }).click();

    // Find the filters modal.
    const filtersModal = adminCommunityPage.locator("#audit-log-filters-modal");
    await expect(filtersModal).toBeVisible();
    await expect(filtersModal.locator("#audit-action")).toHaveValue(
      "community_updated",
    );
    await expect(filtersModal.locator("#audit-actor")).toHaveValue(
      "e2e-admin-1",
    );
  });

  test("admin can open seeded community log details", async ({
    adminCommunityPage,
  }) => {
    // Load the community logs URL filtered to a seeded detail row.
    await navigateToPath(adminCommunityPage, COMMUNITY_DETAILS_LOGS_PATH);

    // Target the seeded log row and open its details.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    const auditLogRow = dashboardContent.locator("tr.audit-log-row", {
      hasText: "Observability Guild",
    });

    // Assert the expected text is rendered.
    await expect(auditLogRow).toContainText("Group added");
    await expect(auditLogRow).toContainText("Observability Guild");

    // Find the View log details control.
    const detailsButton = auditLogRow.getByRole("button", {
      name: "View log details",
    });
    await expect(detailsButton).toBeVisible();
    await detailsButton.click();
    await expect(detailsButton).toHaveAttribute("aria-expanded", "true");

    // Set up details popover id.
    const detailsPopoverId = await detailsButton.getAttribute("aria-controls");
    expect(detailsPopoverId).not.toBeNull();

    // Verify the details popover contains the changed fields.
    const detailsPopover = dashboardContent.locator(`#${detailsPopoverId}`);
    await expect(detailsPopover).toBeVisible();
    await expect(detailsPopover).toContainText("North America");
    await expect(detailsPopover).toContainText("Active");
  });

  test("admin can browse the full seeded community logs list", async ({
    adminCommunityPage,
  }) => {
    // Load the unfiltered community logs URL.
    await navigateToPath(adminCommunityPage, COMMUNITY_LOGS_PATH);

    // Verify the seeded community and group log content is present.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.locator("tr.audit-log-row").first(),
    ).toBeVisible();
    await expect(dashboardContent).toContainText(
      "Platform Engineering Community",
    );
    await expect(
      dashboardContent
        .locator("tr.audit-log-row", {
          hasText: "Observability Guild",
        })
        .first(),
    ).toBeVisible();
  });
});
