import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const FILTERED_GROUP_LOGS_PATH =
  "/dashboard/group?tab=logs&action=group_updated&actor=e2e-organizer-1";
const GROUP_DETAILS_LOGS_PATH =
  "/dashboard/group?tab=logs&action=group_sponsor_added&actor=e2e-organizer-1";
const GROUP_LOGS_PATH = "/dashboard/group?tab=logs";

test.describe("group dashboard logs view", () => {
  test("organizer can view the seeded group logs list and active filters", async ({
    organizerGroupPage,
  }) => {
    // Load the filtered group logs URL.
    await navigateToPath(organizerGroupPage, FILTERED_GROUP_LOGS_PATH);

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can view the seeded group logs list and active filters.
    await expect(
      dashboardContent.getByText("Logs", { exact: true }),
    ).toBeVisible();
    await expect(organizerGroupPage).toHaveURL(
      /\/dashboard\/group\?tab=logs&action=group_updated&actor=e2e-organizer-1/,
    );

    // Find the audit log row.
    const auditLogRow = dashboardContent.locator("tr.audit-log-row").first();
    await expect(auditLogRow).toContainText("Group updated");
    await expect(auditLogRow).toContainText("e2e-organizer-1");
    await expect(auditLogRow).toContainText("Platform Ops Meetup");

    // Click Filters.
    await organizerGroupPage.getByRole("button", { name: "Filters" }).click();

    // Find the filters modal.
    const filtersModal = organizerGroupPage.locator("#audit-log-filters-modal");
    await expect(filtersModal).toBeVisible();
    await expect(filtersModal.locator("#audit-action")).toHaveValue(
      "group_updated",
    );
    await expect(filtersModal.locator("#audit-actor")).toHaveValue(
      "e2e-organizer-1",
    );
  });

  test("organizer can open seeded group log details", async ({
    organizerGroupPage,
  }) => {
    // Load the group logs URL filtered to a seeded detail row.
    await navigateToPath(organizerGroupPage, GROUP_DETAILS_LOGS_PATH);

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const auditLogRow = dashboardContent
      .locator("tr.audit-log-row", {
        hasText: "Tech Corp",
      })
      .first();

    // Verify organizer can open seeded group log details.
    await expect(auditLogRow).toContainText("Group sponsor added");
    await expect(auditLogRow).toContainText("Tech Corp");

    // Find the View log details control.
    const detailsButton = auditLogRow.getByRole("button", {
      name: "View log details",
    });
    await expect(detailsButton).toBeVisible();
    await detailsButton.click();
    await expect(detailsButton).toHaveAttribute("aria-expanded", "true");

    // Set up the details popover controlled by the clicked button so the
    // assertion targets this row even when other rows render details cards.
    const popoverId = await detailsButton.getAttribute("aria-controls");

    // Fail clearly if the log details popover was not rendered.
    if (!popoverId) {
      throw new Error("Expected audit log details button to control a popover");
    }
    const detailsPopover = dashboardContent.locator(`#${popoverId}`);
    await expect(detailsPopover).toBeVisible();
    await expect(detailsPopover).toContainText("gold");
    await expect(detailsPopover).toContainText("https://techcorp.example.com");
  });

  test("organizer sees one group log details popover at a time", async ({
    organizerGroupPage,
  }) => {
    // Use a desktop viewport before opening the full logs list.
    await organizerGroupPage.setViewportSize({ width: 1100, height: 720 });
    await navigateToPath(organizerGroupPage, GROUP_LOGS_PATH);

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const detailsButtons = dashboardContent.getByRole("button", {
      name: "View log details",
    });
    const firstDetailsButton = detailsButtons.nth(0);
    const secondDetailsButton = detailsButtons.nth(1);

    // Resolve the popover controlled by a details button.
    const getDetailsPopover = async (detailsButton) => {
      const popoverId = await detailsButton.getAttribute("aria-controls");

      // Fail clearly if the log details popover was not rendered.
      if (!popoverId) {
        throw new Error(
          "Expected audit log details button to control a popover",
        );
      }

      // Return the values used by the caller.
      return dashboardContent.locator(`#${popoverId}`);
    };
    const firstDetailsPopover = await getDetailsPopover(firstDetailsButton);
    const secondDetailsPopover = await getDetailsPopover(secondDetailsButton);

    // Click the first details button.
    await firstDetailsButton.click();
    await expect(firstDetailsPopover).toBeVisible();

    // Hover the second log entry.
    await secondDetailsButton.hover();
    await expect(firstDetailsPopover).toBeHidden();
    await expect(secondDetailsPopover).toBeVisible();
  });

  test("organizer can browse the full seeded group logs list", async ({
    organizerGroupPage,
  }) => {
    // Load the unfiltered group logs URL sorted oldest first so the seeded
    // rows stay on the first page even after the run generates new logs.
    await navigateToPath(
      organizerGroupPage,
      `${GROUP_LOGS_PATH}&sort=created-asc`,
    );

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can browse the group logs list even after new logs exist.
    await expect(
      dashboardContent.locator("tr.audit-log-row").first(),
    ).toBeVisible();
    await expect(
      dashboardContent
        .locator("tr.audit-log-row", {
          hasText: "Group sponsor added",
        })
        .first(),
    ).toBeVisible();
  });
});
