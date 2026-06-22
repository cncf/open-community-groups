import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const FILTERED_USER_LOGS_PATH =
  "/dashboard/user?tab=logs&action=user_details_updated";
const USER_DETAILS_LOGS_PATH =
  "/dashboard/user?tab=logs&action=session_proposal_added";
const USER_LOGS_PATH = "/dashboard/user?tab=logs";

test.describe("user dashboard logs view", () => {
  test("member can view the seeded user logs list and active filters", async ({
    member1Page,
  }) => {
    // Load the filtered user logs URL.
    await navigateToPath(member1Page, FILTERED_USER_LOGS_PATH);

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");

    // Verify member can view the seeded user logs list and active filters.
    await expect(
      dashboardContent.getByText("Logs", { exact: true }),
    ).toBeVisible();
    await expect(member1Page).toHaveURL(
      /\/dashboard\/user\?tab=logs&action=user_details_updated/,
    );

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
    await expect(filtersModal.locator("#audit-action")).toHaveValue(
      "user_details_updated",
    );
  });

  test("member can open seeded user log details", async ({ member1Page }) => {
    // Load the user logs URL filtered to a seeded detail row.
    await navigateToPath(member1Page, USER_DETAILS_LOGS_PATH);

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");
    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();

    // Verify member can open seeded user log details.
    await expect(auditLogRow).toContainText("Session proposal added");
    await expect(auditLogRow).toContainText(
      "Cloud Native Operations Deep Dive",
    );

    // Find the View log details control.
    const detailsButton = auditLogRow.getByRole("button", {
      name: "View log details",
    });
    await expect(detailsButton).toBeVisible();
    await detailsButton.click();
    await expect(detailsButton).toHaveAttribute("aria-expanded", "true");

    // Set up details popover.
    const detailsPopover = dashboardContent
      .locator("[data-audit-log-details-card]")
      .first();
    await expect(detailsPopover).toBeVisible();
    await expect(detailsPopover).toContainText("Seeded logs fixture");
    await expect(detailsPopover).toContainText("advanced");
  });

  test("member can browse the full seeded user logs list", async ({
    member1Page,
  }) => {
    // Load the unfiltered user logs URL.
    await navigateToPath(member1Page, USER_LOGS_PATH);

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");

    // Verify member can browse the full seeded user logs list.
    await expect(
      dashboardContent.locator("tr.audit-log-row").filter({
        hasText: "User details updated",
      }),
    ).toHaveCount(1);
    await expect(
      dashboardContent.locator("tr.audit-log-row").filter({
        hasText: "Session proposal added",
      }),
    ).toHaveCount(1);
  });

  test("member can apply empty log filters and reset them", async ({
    member1Page,
  }) => {
    // Load the unfiltered user logs URL before applying empty filters.
    await navigateToPath(member1Page, USER_LOGS_PATH);

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");
    await member1Page.getByRole("button", { name: "Filters" }).click();

    // Find the filters modal.
    const filtersModal = member1Page.locator("#audit-log-filters-modal");
    await filtersModal
      .locator("#audit-action")
      .selectOption("alliance_team_invitation_accepted");
    await filtersModal.getByRole("button", { name: "Apply" }).click();

    // Verify member can apply empty log filters and reset them.
    await expect(member1Page).toHaveURL(
      /\/dashboard\/user\?tab=logs&action=alliance_team_invitation_accepted/,
    );
    await expect(
      dashboardContent.locator("td:visible", {
        hasText: "No audit log entries found.",
      }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Filters" }),
    ).toBeVisible();

    // Click Filters.
    await dashboardContent.getByRole("button", { name: "Filters" }).click();
    await filtersModal.getByRole("link", { name: "Reset" }).click();

    // Assert that the browser lands on the right URL.
    await expect(member1Page).toHaveURL(/\/dashboard\/user\?tab=logs(?:&|$)/);
    await expect(
      dashboardContent.locator("tr.audit-log-row").filter({
        hasText: "User details updated",
      }),
    ).toHaveCount(1);
  });
});
