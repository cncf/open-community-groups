import { expect, test } from "../fixtures";

import { navigateToPath } from "../utils";

const NOTIFICATION_TITLE = "E2E member notification";
const NOTIFICATION_BODY = "Reminder for all members from the e2e suite.";

test.describe("group members dashboard", () => {
  test("organizer can send a notification to group members", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=members");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Members", { exact: true })).toBeVisible();

    const openModalButton = organizerGroupPage.getByRole("button", { name: "Send email" });
    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();

    const notificationModal = organizerGroupPage.locator("#notification-modal");
    await expect(notificationModal).toBeVisible();

    await organizerGroupPage.getByLabel("Title").fill(NOTIFICATION_TITLE);
    await organizerGroupPage.getByLabel("Body").fill(NOTIFICATION_BODY);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/notifications") &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Send email" }).nth(1).click(),
    ]);

    await expect(notificationModal).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Email sent successfully to all group members.",
    );
  });
});
