import { expect, test } from "../../../fixtures.js";

import { expectPaginationNavigation, navigateToPath } from "../../../utils.js";

const FILTERED_USER_LOGS_PATH = "/dashboard/user?tab=logs&action=user_details_updated";
const USER_LOGS_PATH = "/dashboard/user?tab=logs";

test.describe("user dashboard logs view", () => {
  test("empty state explains when a user has no audit history", async ({ emptyUserPage }) => {
    // Load logs for the dedicated user without audit records.
    await navigateToPath(emptyUserPage, USER_LOGS_PATH);
    const dashboardContent = emptyUserPage.locator("#dashboard-content");

    // Verify the zero count and empty audit guidance remain visible.
    await expect(dashboardContent).toContainText("0 logs");
    await expect(dashboardContent).toContainText("No audit log entries found.");
  });

  test("member can move between user log result pages", async ({ member1Page }) => {
    // Sort oldest first so the first pages hold distinct seeded rows, not rows added by other tests.
    await expectPaginationNavigation(
      member1Page,
      `${USER_LOGS_PATH}&sort=created-asc&limit=1&offset=0`,
      "#dashboard-content tr.audit-log-row",
    );
  });

  test("member can view the seeded user logs list and active filters", async ({ member1Page }) => {
    // Load the unfiltered user logs oldest first so rows added by other tests come after the seeded ones.
    await navigateToPath(member1Page, `${USER_LOGS_PATH}&sort=created-asc`);
    let dashboardContent = member1Page.locator("#dashboard-content");

    // Verify the seeded user logs lead the list.
    const auditLogRows = dashboardContent.locator("tr.audit-log-row");
    await expect(auditLogRows.nth(0)).toContainText("User details updated");
    await expect(auditLogRows.nth(1)).toContainText("Session proposal added");

    // Verify the seeded session proposal row renders its target and detail fields.
    const sessionProposalRow = auditLogRows.nth(1);
    await expect(sessionProposalRow).toContainText("Cloud Native Operations Deep Dive");
    const detailsCard = sessionProposalRow.locator("[data-audit-log-details-card]");
    await expect(detailsCard).toContainText("Seeded logs fixture");
    await expect(detailsCard).toContainText("advanced");

    // Load the filtered user logs URL.
    await navigateToPath(member1Page, FILTERED_USER_LOGS_PATH);

    // Find the dashboard content.
    dashboardContent = member1Page.locator("#dashboard-content");

    // Verify member can view the seeded user logs list and active filters.
    await expect(dashboardContent.getByText("Logs", { exact: true })).toBeVisible();
    await expect(member1Page).toHaveURL(/\/dashboard\/user\?tab=logs&action=user_details_updated/);

    // Find the audit log row.
    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();
    await expect(auditLogRow).toContainText("User details updated");
    await expect(auditLogRow).toContainText("E2E Member One");

    // Click Filters.
    await member1Page.getByRole("button", { name: "Filters" }).click();

    // Find the filters modal.
    const filtersModal = member1Page.locator("#audit-log-filters-modal");
    await expect(filtersModal).toBeVisible();
    await expect(filtersModal.locator("#audit-actor")).toHaveCount(0);
    await expect(filtersModal.locator("#audit-action")).toHaveValue("user_details_updated");
  });

  test("member can apply empty log filters and reset them", async ({ member1Page }) => {
    // Load the unfiltered user logs URL before applying empty filters.
    await navigateToPath(member1Page, USER_LOGS_PATH);

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");
    await member1Page.getByRole("button", { name: "Filters" }).click();

    // Find the filters modal.
    const filtersModal = member1Page.locator("#audit-log-filters-modal");
    await filtersModal.locator("#audit-action").selectOption("community_team_invitation_accepted");
    await filtersModal.getByRole("button", { name: "Apply" }).click();

    // Verify member can apply empty log filters and reset them.
    await expect(member1Page).toHaveURL(
      /\/dashboard\/user\?tab=logs&action=community_team_invitation_accepted/,
    );
    await expect(
      dashboardContent.locator("td:visible", {
        hasText: "No audit log entries found.",
      }),
    ).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: "Filters" })).toBeVisible();

    // Click Filters.
    await dashboardContent.getByRole("button", { name: "Filters" }).click();
    await filtersModal.getByRole("link", { name: "Reset" }).click();

    // Assert that the browser lands on the right URL.
    await expect(member1Page).toHaveURL(/\/dashboard\/user\?tab=logs(?:&|$)/);
    await expect(
      dashboardContent
        .locator("tr.audit-log-row")
        .filter({
          hasText: "User details updated",
        })
        .first(),
    ).toBeVisible();
  });
});
