import { expect, test } from "../../fixtures";

import { navigateToPath } from "../../utils";

test.describe("group dashboard analytics view", () => {
  test("organizer can view analytics summary cards and chart sections", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=analytics");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Analytics", { exact: true })).toBeVisible();

    for (const label of ["Members", "Events", "Attendees", "Page views"]) {
      await expect(dashboardContent.getByText(label, { exact: true }).first()).toBeVisible();
    }

    const membersSection = dashboardContent
      .getByText("Members", { exact: true })
      .last()
      .locator("..")
      .locator("..");
    await expect(membersSection.getByText("Running total", { exact: true })).toBeVisible();
    await expect(membersSection.locator("#members-running-chart, .chart-empty-state").first()).toBeVisible();

    const eventsSection = dashboardContent
      .getByText("Events", { exact: true })
      .last()
      .locator("..")
      .locator("..");
    await expect(eventsSection.getByText("Running total", { exact: true })).toBeVisible();
    await expect(eventsSection.locator("#events-running-chart, .chart-empty-state").first()).toBeVisible();

    const attendeesSection = dashboardContent
      .getByText("Attendees", { exact: true })
      .last()
      .locator("..")
      .locator("..");
    await expect(attendeesSection.getByText("Running total", { exact: true })).toBeVisible();
    await expect(
      attendeesSection.locator("#attendees-running-chart, .chart-empty-state").first(),
    ).toBeVisible();

    const pageViewsSection = dashboardContent
      .getByText("Page Views", { exact: true })
      .last()
      .locator("..")
      .locator("..");
    await expect(pageViewsSection).toBeVisible();
    await expect(pageViewsSection.getByText("Group page", { exact: true })).toBeVisible();
    await expect(pageViewsSection.getByText("Event pages", { exact: true })).toBeVisible();
    await expect(pageViewsSection.locator(".chart-empty-state, #group-views-monthly-chart").first()).toBeVisible();
  });
});
