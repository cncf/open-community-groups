import { expect, test } from "../../../fixtures";

import { navigateToPath } from "../../../utils";

const FILTERED_USER_LOGS_PATH = "/dashboard/user?tab=logs&action=user_details_updated";
const USER_DETAILS_LOGS_PATH = "/dashboard/user?tab=logs&action=session_proposal_added";
const USER_LOGS_PATH = "/dashboard/user?tab=logs";

test.describe("user dashboard logs view", () => {
  test("member can view the seeded user logs list and active filters", async ({
    member1Page,
  }) => {
    await navigateToPath(member1Page, FILTERED_USER_LOGS_PATH);

    const dashboardContent = member1Page.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Logs", { exact: true })).toBeVisible();
    await expect(member1Page).toHaveURL(
      /\/dashboard\/user\?tab=logs&action=user_details_updated/,
    );

    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();
    await expect(auditLogRow).toContainText("User details updated");
    await expect(auditLogRow).toContainText("E2E Member One");

    await member1Page.getByRole("button", { name: "Filters" }).click();

    const filtersModal = member1Page.locator("#audit-log-filters-modal");
    await expect(filtersModal).toBeVisible();
    await expect(filtersModal.locator("#audit-actor")).toHaveCount(0);
    await expect(filtersModal.locator("#audit-action")).toHaveValue("user_details_updated");
  });

  test("member can open seeded user log details", async ({ member1Page }) => {
    await navigateToPath(member1Page, USER_DETAILS_LOGS_PATH);

    const dashboardContent = member1Page.locator("#dashboard-content");
    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();

    await expect(auditLogRow).toContainText("Session proposal added");
    await expect(auditLogRow).toContainText("Cloud Native Operations Deep Dive");

    const detailsButton = auditLogRow.getByRole("button", { name: "View log details" });
    await expect(detailsButton).toBeVisible();
    await detailsButton.click();
    await expect(detailsButton).toHaveAttribute("aria-expanded", "true");

    const detailsPopover = dashboardContent.locator("[data-audit-log-details-card]").first();
    await expect(detailsPopover).toBeVisible();
    await expect(detailsPopover).toContainText("Seeded logs fixture");
    await expect(detailsPopover).toContainText("advanced");
  });

  test("member can browse the full seeded user logs list", async ({ member1Page }) => {
    await navigateToPath(member1Page, USER_LOGS_PATH);

    const dashboardContent = member1Page.locator("#dashboard-content");
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

  test("member sees an empty state when filters match no logs", async ({
    member1Page,
  }) => {
    await navigateToPath(member1Page, USER_LOGS_PATH);

    await member1Page.getByRole("button", { name: "Filters" }).click();

    const filtersModal = member1Page.locator("#audit-log-filters-modal");
    await expect(filtersModal).toBeVisible();
    await filtersModal.locator("#audit-date-from").fill("2099-01-01");
    await filtersModal.getByRole("button", { name: "Apply" }).click();

    const dashboardContent = member1Page.locator("#dashboard-content");
    await expect(member1Page).toHaveURL(
      /\/dashboard\/user\?tab=logs&date_from=2099-01-01/,
    );
    await expect(dashboardContent.getByText("Logs", { exact: true })).toBeVisible();
    await expect(dashboardContent).toContainText("0 logs");
    await expect(dashboardContent).toContainText("No logs match these filters.");
    await expect(dashboardContent.locator("tr.audit-log-row")).toHaveCount(0);
  });
});
