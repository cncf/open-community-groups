import { expect, test } from "../../../fixtures.js";

import {
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";

const NOTIFICATION_SUBJECT = "E2E member notification";
const NOTIFICATION_BODY = "Reminder for all members from the e2e suite.";

test.describe("group dashboard members view", () => {
  test("empty state explains when a group has no members", async ({
    organizerEmptyGroupPage,
  }) => {
    // Load members for the dedicated group without membership records.
    await navigateToPath(
      organizerEmptyGroupPage,
      "/dashboard/group?tab=members",
    );
    const dashboardContent = organizerEmptyGroupPage.locator(
      "#dashboard-content",
    );

    // Verify the result count, guidance, and unavailable notification action.
    await expect(dashboardContent).toContainText("0 members");
    await expect(dashboardContent).toContainText("No members yet.");
    await expect(
      dashboardContent.getByRole("button", { name: "Send email" }),
    ).toBeDisabled();
  });

  test("members table exposes its responsive columns", async ({ organizerGroupPage }) => {
    // Load the members dashboard before checking table structure.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=members");

    // Find the members table.
    const membersTable = organizerGroupPage.getByRole("table", {
      name: "Members list",
    });

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableHeaders(membersTable, ["Member", "Position", "Joined"]);
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      membersTable,
      1024,
      ["Member", "Position"],
      ["Joined"],
    );
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      membersTable,
      1280,
      ["Member", "Position", "Joined"],
      [],
    );
  });

  test("organizer can move between member result pages", async ({ organizerGroupPage }) => {
    // Paginate the seeded member rows with one result per page.
    await expectPaginationNavigation(
      organizerGroupPage,
      "/dashboard/group?tab=members&limit=1&offset=0",
      "#dashboard-content tbody tr",
    );
  });

  test("organizer can send a notification to group members", async ({ organizerGroupPage }) => {
    // Load the members tab before opening the email modal.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=members");

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can send a notification to group members.
    await expect(dashboardContent.getByText("Members", { exact: true })).toBeVisible();

    // Find the Send email control.
    const openModalButton = organizerGroupPage.getByRole("button", {
      name: "Send email",
    });
    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();

    // Find the notification modal.
    const notificationModal = organizerGroupPage.locator("#notification-modal");
    await expect(notificationModal).toBeVisible();

    // Fill Subject.
    await notificationModal.getByLabel("Subject").fill(NOTIFICATION_SUBJECT);
    await notificationModal.getByLabel("Body").fill(NOTIFICATION_BODY);

    // Click Send email.
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.getByRole("button", { name: "Send email" }).nth(1).click(),
      {
        method: "POST",
        urlIncludes: "/dashboard/group/notifications",
      },
    );

    // Assert that the content is hidden.
    await expect(notificationModal).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Email sent successfully to all group members.",
    );
  });

  test("viewer sees read-only controls in the members view", async ({ groupViewerPage }) => {
    // Load the members tab as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=members");

    // Find the dashboard content.
    const dashboardContent = groupViewerPage.locator("#dashboard-content");

    // Verify viewer sees read-only controls in the members view.
    await expect(dashboardContent.getByText("Members", { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: "Send email" })).toBeDisabled();
    await expect(dashboardContent.getByRole("button", { name: "Send email" })).toHaveAttribute(
      "title",
      "Your role cannot send emails to members.",
    );
  });
});
