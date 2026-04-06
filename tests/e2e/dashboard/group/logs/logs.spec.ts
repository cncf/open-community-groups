import { expect, test } from "../../../fixtures";

import { navigateToPath } from "../../../utils";

const FILTERED_GROUP_LOGS_PATH =
  "/dashboard/group?tab=logs&action=group_updated&actor=e2e-organizer-1";
const GROUP_DETAILS_LOGS_PATH =
  "/dashboard/group?tab=logs&action=group_sponsor_added&actor=e2e-organizer-1";
const GROUP_LOGS_PATH = "/dashboard/group?tab=logs";

test.describe("group dashboard logs view", () => {
  test("organizer can view the seeded group logs list and active filters", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, FILTERED_GROUP_LOGS_PATH);

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Logs", { exact: true })).toBeVisible();
    await expect(organizerGroupPage).toHaveURL(
      /\/dashboard\/group\?tab=logs&action=group_updated&actor=e2e-organizer-1/,
    );

    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();
    await expect(auditLogRow).toContainText("Group updated");
    await expect(auditLogRow).toContainText("e2e-organizer-1");
    await expect(auditLogRow).toContainText("Platform Ops Meetup");

    await organizerGroupPage.getByRole("button", { name: "Filters" }).click();

    const filtersModal = organizerGroupPage.locator("#audit-log-filters-modal");
    await expect(filtersModal).toBeVisible();
    await expect(filtersModal.locator("#audit-action")).toHaveValue("group_updated");
    await expect(filtersModal.locator("#audit-actor")).toHaveValue("e2e-organizer-1");
  });

  test("organizer can open seeded group log details", async ({ organizerGroupPage }) => {
    await navigateToPath(organizerGroupPage, GROUP_DETAILS_LOGS_PATH);

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();

    await expect(auditLogRow).toContainText("Group sponsor added");
    await expect(auditLogRow).toContainText("Tech Corp");

    const detailsButton = auditLogRow.getByRole("button", { name: "View log details" });
    await expect(detailsButton).toBeVisible();
    await detailsButton.click();
    await expect(detailsButton).toHaveAttribute("aria-expanded", "true");

    const detailsPopover = dashboardContent.locator("[data-audit-log-details-card]").first();
    await expect(detailsPopover).toBeVisible();
    await expect(detailsPopover).toContainText("gold");
    await expect(detailsPopover).toContainText("https://techcorp.example.com");
  });

  test("organizer can browse the full seeded group logs list", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, GROUP_LOGS_PATH);

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(
      dashboardContent.locator("tr.audit-log-row").filter({
        hasText: "Group updated",
      }),
    ).toHaveCount(1);
    await expect(
      dashboardContent.locator("tr.audit-log-row").filter({
        hasText: "Group sponsor added",
      }),
    ).toHaveCount(1);
  });
});
