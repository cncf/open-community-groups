import { expect, test } from "../../../fixtures";

import { TEST_EVENT_NAMES, navigateToPath } from "../../../utils";

test.describe("user dashboard my events view", () => {
  test("my events page lists only upcoming published participation", async ({
    member1Page,
  }) => {
    await navigateToPath(member1Page, "/dashboard/user?tab=events");

    const dashboardContent = member1Page.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("My Events", { exact: true }),
    ).toBeVisible();

    const attendeeSpeakerRow = dashboardContent.locator("tr", {
      hasText: TEST_EVENT_NAMES.alpha[0],
    });
    await expect(attendeeSpeakerRow).toContainText("Attendee");
    await expect(attendeeSpeakerRow).toContainText("Speaker");

    await expect(dashboardContent.getByText("Past Event For Filtering")).toHaveCount(0);
    await expect(dashboardContent.getByText(TEST_EVENT_NAMES.beta[0])).toHaveCount(0);
  });
});
