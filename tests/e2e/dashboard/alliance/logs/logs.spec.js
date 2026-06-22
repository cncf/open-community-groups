import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const ALLIANCE_LOGS_PATH = "/dashboard/alliance?tab=logs";
const FILTERED_ALLIANCE_LOGS_PATH =
  "/dashboard/alliance?tab=logs&action=alliance_updated&actor=e2e-admin-1";
const ALLIANCE_DETAILS_LOGS_PATH =
  "/dashboard/alliance?tab=logs&action=group_added&actor=e2e-admin-1";

test.describe("alliance dashboard logs view", () => {
  test("admin can view the seeded alliance logs list and active filters", async ({
    adminAlliancePage,
  }) => {
    // Load the filtered alliance logs URL.
    await navigateToPath(adminAlliancePage, FILTERED_ALLIANCE_LOGS_PATH);

    // Verify the filtered log row and durable filter URL.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Logs", { exact: true }),
    ).toBeVisible();
    await expect(adminAlliancePage).toHaveURL(
      /\/dashboard\/alliance\?tab=logs&action=alliance_updated&actor=e2e-admin-1/,
    );

    // Find the audit log row.
    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();
    await expect(auditLogRow).toContainText("Alliance updated");
    await expect(auditLogRow).toContainText("e2e-admin-1");
    await expect(auditLogRow).toContainText("GOUP Alliance");

    // Open the filters modal and verify the active filters.
    await adminAlliancePage.getByRole("button", { name: "Filters" }).click();

    // Find the filters modal.
    const filtersModal = adminAlliancePage.locator("#audit-log-filters-modal");
    await expect(filtersModal).toBeVisible();
    await expect(filtersModal.locator("#audit-action")).toHaveValue(
      "alliance_updated",
    );
    await expect(filtersModal.locator("#audit-actor")).toHaveValue(
      "e2e-admin-1",
    );
  });

  test("admin can open seeded alliance log details", async ({
    adminAlliancePage,
  }) => {
    // Load the alliance logs URL filtered to a seeded detail row.
    await navigateToPath(adminAlliancePage, ALLIANCE_DETAILS_LOGS_PATH);

    // Target the seeded log row and open its details.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");
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

  test("admin can browse the full seeded alliance logs list", async ({
    adminAlliancePage,
  }) => {
    // Load the unfiltered alliance logs URL.
    await navigateToPath(adminAlliancePage, ALLIANCE_LOGS_PATH);

    // Verify the seeded alliance and group log content is present.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");
    await expect(
      dashboardContent.locator("tr.audit-log-row").first(),
    ).toBeVisible();
    await expect(dashboardContent).toContainText("GOUP Alliance");
    await expect(
      dashboardContent
        .locator("tr.audit-log-row", {
          hasText: "Observability Guild",
        })
        .first(),
    ).toBeVisible();
  });
});
