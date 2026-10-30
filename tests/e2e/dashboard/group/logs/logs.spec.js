import { expect, test } from "../../../fixtures.js";

import { navigateToPath, waitForActionResponse } from "../../../utils.js";

const FILTERED_GROUP_LOGS_PATH = "/dashboard/group?tab=logs&action=group_updated&actor=e2e-organizer-1";
const GROUP_DETAILS_LOGS_PATH = "/dashboard/group?tab=logs&action=group_sponsor_added&actor=e2e-organizer-1";
const GROUP_LOGS_PATH = "/dashboard/group?tab=logs";

test.describe("group dashboard logs view", () => {
  test("empty state explains when a group has no audit history", async ({ organizerEmptyGroupPage }) => {
    // Load logs for the dedicated group without audit records.
    await navigateToPath(organizerEmptyGroupPage, GROUP_LOGS_PATH);
    const dashboardContent = organizerEmptyGroupPage.locator("#dashboard-content");

    // Verify the zero count and empty audit guidance remain visible.
    await expect(dashboardContent).toContainText("0 logs");
    await expect(dashboardContent).toContainText("No audit log entries found.");
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
    // Load the unfiltered group logs URL sorted oldest first so the seeded
    // rows stay on the first page even after the run generates new logs.
    await navigateToPath(organizerGroupPage, `${GROUP_LOGS_PATH}&sort=created-asc`);
    let dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can browse the group logs list even after new logs exist.
    await expect(dashboardContent.locator("tr.audit-log-row").first()).toBeVisible();
    await expect(
      dashboardContent
        .locator("tr.audit-log-row", {
          hasText: "Group sponsor added",
        })
        .first(),
    ).toBeVisible();

    // Load the filtered group logs URL.
    await navigateToPath(organizerGroupPage, FILTERED_GROUP_LOGS_PATH);

    // Find the dashboard content.
    dashboardContent = organizerGroupPage.locator("#dashboard-content");

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

  test("organizer sees the log date in the details popover on narrow screens", async ({
    organizerGroupPage,
  }) => {
    // Load a seeded detail row at the narrowest dashboard width, where the date column is hidden.
    await organizerGroupPage.setViewportSize({ width: 768, height: 900 });
    await navigateToPath(organizerGroupPage, GROUP_DETAILS_LOGS_PATH);
    const auditLogRow = organizerGroupPage
      .locator("#dashboard-content tr.audit-log-row", { hasText: "Tech Corp" })
      .first();

    // Open the row details.
    const detailsButton = auditLogRow.getByRole("button", { name: "View log details" });
    await detailsButton.click();
    await expect(detailsButton).toHaveAttribute("aria-expanded", "true");

    // Verify the popover lists the date with the other hidden columns.
    const detailsCard = auditLogRow.locator("[data-audit-log-details-card]");
    await expect(detailsCard).toBeVisible();
    await expect(detailsCard.getByText("Date", { exact: true })).toBeVisible();
    await expect(detailsCard.getByText("Type", { exact: true })).toBeVisible();

    // Verify the date row is hidden again once the date column returns.
    await organizerGroupPage.setViewportSize({ width: 1024, height: 900 });
    await expect(detailsCard.getByText("Date", { exact: true })).toBeHidden();
    await expect(detailsCard.getByText("Type", { exact: true })).toBeVisible();
  });

  test("organizer sees log details above the trigger when there is no room below", async ({
    organizerGroupPage,
  }) => {
    // Load the full logs list in a short viewport.
    const viewport = { width: 1024, height: 600 };
    await organizerGroupPage.setViewportSize(viewport);
    await navigateToPath(organizerGroupPage, GROUP_LOGS_PATH);
    const logRows = organizerGroupPage.locator("#dashboard-content tr.audit-log-row");
    await expect(logRows.first()).toBeVisible();

    // Open the last row details with the row at the viewport bottom.
    const lastRow = logRows.last();
    await scrollRowIntoView(lastRow, "end");
    await lastRow.getByRole("button", { name: "View log details" }).click();

    // Verify the card flips above the trigger and stays inside the viewport.
    const lastCard = lastRow.locator("[data-audit-log-details-card]");
    await expect(lastCard).toBeVisible();
    await expect(lastCard).toHaveAttribute("data-placement", "top");
    await expectInsideViewport(lastCard, viewport);

    // Open the first row details with the row just below the fixed header.
    const firstRow = logRows.first();
    await scrollRowIntoView(firstRow, "start");
    await firstRow.getByRole("button", { name: "View log details" }).click();

    // Verify the first card opens below its trigger and the last one closes.
    const firstCard = firstRow.locator("[data-audit-log-details-card]");
    await expect(firstCard).toBeVisible();
    await expect(firstCard).not.toHaveAttribute("data-placement");
    await expect(lastCard).toBeHidden();
  });
});

/**
 * Checks that an element's bounding box sits inside the viewport.
 * @param {import("@playwright/test").Locator} locator - Element to measure.
 * @param {{ height: number, width: number }} viewport - Current viewport size.
 */
const expectInsideViewport = async (locator, viewport) => {
  const box = await locator.boundingBox();

  expect(box).not.toBeNull();
  expect(box.y).toBeGreaterThanOrEqual(0);
  expect(box.y + box.height).toBeLessThanOrEqual(viewport.height);
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(viewport.width);
};

/**
 * Scrolls a table row to the bottom of the viewport, or just below the fixed dashboard header.
 * @param {import("@playwright/test").Locator} row - Row to scroll into view.
 * @param {"end"|"start"} block - Viewport edge the row is aligned to.
 */
const scrollRowIntoView = async (row, block) => {
  await row.evaluate((element, alignment) => {
    element.scrollIntoView({ block: alignment });
    if (alignment === "start") {
      const header = document.getElementById("dashboard-header");
      window.scrollBy(0, -((header?.getBoundingClientRect().height ?? 0) + 16));
    }
  }, block);
};
