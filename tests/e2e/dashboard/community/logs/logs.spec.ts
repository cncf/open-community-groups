import { expect, test } from "../../../fixtures";

import { navigateToPath } from "../../../utils";

const COMMUNITY_LOGS_PATH = "/dashboard/community?tab=logs";
const FILTERED_COMMUNITY_LOGS_PATH =
  "/dashboard/community?tab=logs&action=community_updated&actor=e2e-admin-1";
const COMMUNITY_DETAILS_LOGS_PATH =
  "/dashboard/community?tab=logs&action=group_added&actor=e2e-admin-1";

test.describe("community dashboard logs view", () => {
  test("admin can view the seeded community logs list and active filters", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, FILTERED_COMMUNITY_LOGS_PATH);

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Logs", { exact: true })).toBeVisible();
    await expect(adminCommunityPage).toHaveURL(
      /\/dashboard\/community\?tab=logs&action=community_updated&actor=e2e-admin-1/,
    );

    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();
    await expect(auditLogRow).toContainText("Community updated");
    await expect(auditLogRow).toContainText("e2e-admin-1");
    await expect(auditLogRow).toContainText("Platform Engineering Community");

    await adminCommunityPage.getByRole("button", { name: "Filters" }).click();

    const filtersModal = adminCommunityPage.locator("#audit-log-filters-modal");
    await expect(filtersModal).toBeVisible();
    await expect(filtersModal.locator("#audit-action")).toHaveValue("community_updated");
    await expect(filtersModal.locator("#audit-actor")).toHaveValue("e2e-admin-1");
  });

  test("admin can open seeded community log details", async ({ adminCommunityPage }) => {
    await navigateToPath(adminCommunityPage, COMMUNITY_DETAILS_LOGS_PATH);

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    const auditLogRow = dashboardContent.locator("tr.audit-log-row", {
      hasText: "Observability Guild",
    });

    await expect(auditLogRow).toContainText("Group added");
    await expect(auditLogRow).toContainText("Observability Guild");

    const detailsButton = auditLogRow.getByRole("button", { name: "View log details" });
    await expect(detailsButton).toBeVisible();
    await detailsButton.click();
    await expect(detailsButton).toHaveAttribute("aria-expanded", "true");

    const detailsPopoverId = await detailsButton.getAttribute("aria-controls");
    expect(detailsPopoverId).not.toBeNull();

    const detailsPopover = dashboardContent.locator(`#${detailsPopoverId!}`);
    await expect(detailsPopover).toBeVisible();
    await expect(detailsPopover).toContainText("North America");
    await expect(detailsPopover).toContainText("Active");
  });

  test("admin can browse the full seeded community logs list", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, COMMUNITY_LOGS_PATH);

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.locator("tr.audit-log-row").filter({
        hasText: "Platform Engineering Community",
      }),
    ).toHaveCount(1);
    await expect(
      dashboardContent.locator("tr.audit-log-row").filter({
        hasText: "Observability Guild",
      }),
    ).toHaveCount(1);
  });
});
