import { expect, test } from "../../../fixtures.js";

import {
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";

const FILTERED_GROUP_LOGS_PATH = "/dashboard/group?tab=logs&action=group_updated&actor=e2e-organizer-1";
const GROUP_DETAILS_LOGS_PATH = "/dashboard/group?tab=logs&action=group_sponsor_added&actor=e2e-organizer-1";
const GROUP_LOGS_PATH = "/dashboard/group?tab=logs";

test.describe("group dashboard logs view", () => {
  test("empty state explains when a group has no audit history", async ({
    organizerEmptyGroupPage,
  }) => {
    // Load logs for the dedicated group without audit records.
    await navigateToPath(organizerEmptyGroupPage, GROUP_LOGS_PATH);
    const dashboardContent = organizerEmptyGroupPage.locator(
      "#dashboard-content",
    );

    // Verify the zero count and empty audit guidance remain visible.
    await expect(dashboardContent).toContainText("0 logs");
    await expect(dashboardContent).toContainText(
      "No audit log entries found.",
    );
  });

  test("group logs table exposes its responsive columns", async ({ organizerGroupPage }) => {
    // Load group logs before checking table structure.
    await navigateToPath(organizerGroupPage, GROUP_LOGS_PATH);

    // Find the logs table and its complete ordered header set.
    const logsTable = organizerGroupPage.locator("#dashboard-content").getByRole("table");
    const headers = ["Action", "Actor", "Target", "Date", "Details"];

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableHeaders(logsTable, headers);
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      logsTable,
      1024,
      ["Action", "Actor", "Date", "Details"],
      ["Target"],
    );
    await expectTableColumnsAtViewport(organizerGroupPage, logsTable, 1280, headers, []);
  });

  test("organizer can move between group log result pages", async ({ organizerGroupPage }) => {
    // Load the first single-result page of seeded audit-log rows.
    await navigateToPath(organizerGroupPage, `${GROUP_LOGS_PATH}&limit=1&offset=0`);
    const pagination = organizerGroupPage.locator(".pagination");
    const logRows = organizerGroupPage.locator("#dashboard-content tr.audit-log-row");

    // Verify the first page shows one row with disabled backward controls.
    await expect(logRows).toHaveCount(1);
    await expect(pagination.getByRole("button", { name: "First" })).toBeDisabled();
    await expect(pagination.getByRole("button", { name: "Prev" })).toBeDisabled();

    // Adjacent log rows can render identical text, so verify paging through offsets.
    await waitForActionResponse(
      organizerGroupPage,
      () => pagination.getByRole("link", { name: "Next" }).click(),
      { method: "GET", urlIncludes: "offset=1" },
    );

    // Verify the second page keeps one row and enables backward controls.
    await expect(logRows).toHaveCount(1);
    const previousLink = pagination.getByRole("link", { name: "Prev" });
    await expect(previousLink).toHaveAttribute("href", /limit=1.*offset=0|offset=0.*limit=1/);

    // Return to the first page and verify the boundary controls reset.
    await waitForActionResponse(organizerGroupPage, () => previousLink.click(), {
      method: "GET",
      urlIncludes: "offset=0",
    });
    await expect(logRows).toHaveCount(1);
    await expect(pagination.getByRole("button", { name: "Prev" })).toBeDisabled();
  });

  test("organizer can view the seeded group logs list and active filters", async ({ organizerGroupPage }) => {
    // Load the filtered group logs URL.
    await navigateToPath(organizerGroupPage, FILTERED_GROUP_LOGS_PATH);

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can view the seeded group logs list and active filters.
    await expect(dashboardContent.getByText("Logs", { exact: true })).toBeVisible();
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
    await expect(filtersModal.locator("#audit-action")).toHaveValue("group_updated");
    await expect(filtersModal.locator("#audit-actor")).toHaveValue("e2e-organizer-1");
  });

  test("organizer can open seeded group log details", async ({ organizerGroupPage }) => {
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

  test("organizer sees one group log details popover at a time", async ({ organizerGroupPage }) => {
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
        throw new Error("Expected audit log details button to control a popover");
      }

      // Return the values used by the caller.
      return dashboardContent.locator(`#${popoverId}`);
    };
    const firstDetailsPopover = await getDetailsPopover(firstDetailsButton);
    const secondDetailsPopover = await getDetailsPopover(secondDetailsButton);

    // Click the first details button.
    await firstDetailsButton.click();
    await expect(firstDetailsPopover).toBeVisible();

    // Open the second log entry with the keyboard.
    await secondDetailsButton.focus();
    await secondDetailsButton.press("Enter");
    await expect(firstDetailsPopover).toBeHidden();
    await expect(secondDetailsPopover).toBeVisible();
  });

  test("organizer can browse the full seeded group logs list", async ({ organizerGroupPage }) => {
    // Load the unfiltered group logs URL sorted oldest first so the seeded
    // rows stay on the first page even after the run generates new logs.
    await navigateToPath(organizerGroupPage, `${GROUP_LOGS_PATH}&sort=created-asc`);

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can browse the group logs list even after new logs exist.
    await expect(dashboardContent.locator("tr.audit-log-row").first()).toBeVisible();
    await expect(
      dashboardContent
        .locator("tr.audit-log-row", {
          hasText: "Group sponsor added",
        })
        .first(),
    ).toBeVisible();
  });
});
