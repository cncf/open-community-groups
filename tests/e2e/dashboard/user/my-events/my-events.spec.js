import { expect, test } from "../../../fixtures.js";

import { TEST_EVENT_NAMES, navigateToPath } from "../../../utils.js";

test.describe("user dashboard my events view", () => {
  test("my events page lists only upcoming published participation", async ({
    member1Page,
  }) => {
    // Load the user events tab before checking filtered participation.
    await navigateToPath(member1Page, "/dashboard/user?tab=events");

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");

    // Verify my events page lists only upcoming published participation.
    await expect(
      dashboardContent.getByText("My Events", { exact: true }),
    ).toBeVisible();

    // Find the attendee speaker row.
    const attendeeSpeakerRow = dashboardContent.locator("tr", {
      hasText: TEST_EVENT_NAMES.alpha[0],
    });
    await expect(attendeeSpeakerRow).toContainText("Attendee");
    await expect(attendeeSpeakerRow).toContainText("Speaker");

    // Assert how many matching elements are shown.
    await expect(
      dashboardContent.getByText("Past Event For Filtering"),
    ).toHaveCount(0);
    await expect(
      dashboardContent.getByText(TEST_EVENT_NAMES.beta[0]),
    ).toHaveCount(0);
  });
});
