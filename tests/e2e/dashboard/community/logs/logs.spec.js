import { expect, test } from "../../../fixtures.js";

import {
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
} from "../../../utils.js";

const COMMUNITY_LOGS_PATH = "/dashboard/community?tab=logs";
const FILTERED_COMMUNITY_LOGS_PATH =
  "/dashboard/community?tab=logs&action=community_updated&actor=e2e-admin-1";
const COMMUNITY_DETAILS_LOGS_PATH = "/dashboard/community?tab=logs&action=group_added&actor=e2e-admin-1";

test.describe("community dashboard logs view", () => {
  test("empty state explains when a community has no audit history", async ({
    adminEmptyCommunityPage,
  }) => {
    // Load logs for the dedicated community without audit records.
    await navigateToPath(adminEmptyCommunityPage, COMMUNITY_LOGS_PATH);
    const dashboardContent = adminEmptyCommunityPage.locator(
      "#dashboard-content",
    );

    // Verify the zero count and empty audit guidance remain visible.
    await expect(dashboardContent).toContainText("0 logs");
    await expect(dashboardContent).toContainText(
      "No audit log entries found.",
    );
  });

  test("community logs table exposes its responsive columns", async ({ adminCommunityPage }) => {
    // Load community logs before checking table structure.
    await navigateToPath(adminCommunityPage, COMMUNITY_LOGS_PATH);

    // Find the logs table and its complete ordered header set.
    const logsTable = adminCommunityPage.locator("#dashboard-content").getByRole("table");
    const headers = ["Action", "Actor", "Target", "Date", "Details"];

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableHeaders(logsTable, headers);
    await expectTableColumnsAtViewport(
      adminCommunityPage,
      logsTable,
      1024,
      ["Action", "Actor", "Date", "Details"],
      ["Target"],
    );
    await expectTableColumnsAtViewport(adminCommunityPage, logsTable, 1280, headers, []);
  });

  test("admin can move between community log result pages", async ({ adminCommunityPage }) => {
    // Paginate the seeded audit-log rows with one result per page.
    await expectPaginationNavigation(
      adminCommunityPage,
      `${COMMUNITY_LOGS_PATH}&limit=1&offset=0`,
      "#dashboard-content tr.audit-log-row",
    );
  });

  test("admin can view the seeded community logs list and active filters", async ({ adminCommunityPage }) => {
    // Load the filtered community logs URL.
    await navigateToPath(adminCommunityPage, FILTERED_COMMUNITY_LOGS_PATH);

    // Verify the filtered log row and durable filter URL.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Logs", { exact: true })).toBeVisible();
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
    await expect(filtersModal.locator("#audit-action")).toHaveValue("community_updated");
    await expect(filtersModal.locator("#audit-actor")).toHaveValue("e2e-admin-1");
  });

  test("admin can open seeded community log details", async ({ adminCommunityPage }) => {
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

  test("admin can browse the full seeded community logs list", async ({ adminCommunityPage }) => {
    // Load the unfiltered community logs URL.
    await navigateToPath(adminCommunityPage, COMMUNITY_LOGS_PATH);

    // Verify the seeded community and group log content is present.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.locator("tr.audit-log-row").first()).toBeVisible();
    await expect(dashboardContent).toContainText("Platform Engineering Community");
    await expect(
      dashboardContent
        .locator("tr.audit-log-row", {
          hasText: "Observability Guild",
        })
        .first(),
    ).toBeVisible();
  });

  test("admin can filter community logs by action and actor and reset them", async ({
    adminCommunityPage,
  }) => {
    // Load the unfiltered community logs URL before applying filters.
    await navigateToPath(adminCommunityPage, COMMUNITY_LOGS_PATH);

    // Verify both seeded actions are listed before filtering.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.locator("tr.audit-log-row", { hasText: "Community updated" }).first(),
    ).toBeVisible();
    await expect(
      dashboardContent.locator("tr.audit-log-row", { hasText: "Group added" }).first(),
    ).toBeVisible();

    // Fill the action and actor filters through the modal and apply them.
    await adminCommunityPage.getByRole("button", { name: "Filters" }).click();
    const filtersModal = adminCommunityPage.locator("#audit-log-filters-modal");
    await expect(filtersModal).toBeVisible();
    await filtersModal.locator("#audit-action").selectOption("group_added");
    await filtersModal.locator("#audit-actor").fill("e2e-admin-1");
    await filtersModal.getByRole("button", { name: "Apply" }).click();

    // Verify the filtered list only keeps the matching action rows.
    await expect(adminCommunityPage).toHaveURL(
      /\/dashboard\/community\?tab=logs&action=group_added&actor=e2e-admin-1/,
    );
    await expect(
      dashboardContent.locator("tr.audit-log-row", { hasText: "Group added" }).first(),
    ).toBeVisible();
    await expect(
      dashboardContent.locator("tr.audit-log-row", { hasText: "Community updated" }),
    ).toHaveCount(0);

    // Verify the active filters indicator and the persisted modal values.
    await expect(adminCommunityPage.locator("#audit-log-filters-active-indicator")).toBeVisible();
    await adminCommunityPage.getByRole("button", { name: "Filters" }).click();
    await expect(filtersModal.locator("#audit-action")).toHaveValue("group_added");
    await expect(filtersModal.locator("#audit-actor")).toHaveValue("e2e-admin-1");

    // Reset the filters and verify the full list comes back.
    await filtersModal.getByRole("link", { name: "Reset" }).click();
    await expect(adminCommunityPage).toHaveURL(/\/dashboard\/community\?tab=logs(?:&|$)/);
    await expect(
      dashboardContent.locator("tr.audit-log-row", { hasText: "Community updated" }).first(),
    ).toBeVisible();
    await expect(adminCommunityPage.locator("#audit-log-filters-active-indicator")).toBeHidden();
  });
});
