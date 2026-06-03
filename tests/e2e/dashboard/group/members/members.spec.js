import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const NOTIFICATION_SUBJECT = "E2E member notification";
const NOTIFICATION_BODY = "Reminder for all members from the e2e suite.";

test.describe("group dashboard members view", () => {
  test("organizer can send a notification to group members", async ({
    organizerGroupPage,
  }) => {
    // Load the members tab before opening the email modal.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=members");

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can send a notification to group members.
    await expect(
      dashboardContent.getByText("Members", { exact: true }),
    ).toBeVisible();

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
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/notifications") &&
          response.ok(),
      ),
      organizerGroupPage
        .getByRole("button", { name: "Send email" })
        .nth(1)
        .click(),
    ]);

    // Assert that the content is hidden.
    await expect(notificationModal).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Email sent successfully to all group members.",
    );
  });

  test("viewer sees read-only controls in the members view", async ({
    groupViewerPage,
  }) => {
    // Load the members tab as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=members");

    // Find the dashboard content.
    const dashboardContent = groupViewerPage.locator("#dashboard-content");

    // Verify viewer sees read-only controls in the members view.
    await expect(
      dashboardContent.getByText("Members", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Send email" }),
    ).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Send email" }),
    ).toHaveAttribute("title", "Your role cannot send emails to members.");
  });
});
