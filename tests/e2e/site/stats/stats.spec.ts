import { expect, test } from "@playwright/test";

import { navigateToPath } from "../../utils";

test.describe("site stats page", () => {
  test("renders totals and analytics chart containers", async ({ page }) => {
    await navigateToPath(page, "/stats");

    const mainContent = page.locator("#main-content");
    await expect(mainContent.getByText("Stats", { exact: true })).toBeVisible();
    await expect(
      mainContent.getByText("Global growth trends across all communities.", { exact: true }),
    ).toBeVisible();

    for (const sectionName of ["Groups", "Members", "Events", "Attendees"]) {
      await expect(mainContent.getByText(sectionName, { exact: true }).first()).toBeVisible();
    }

    const groupsSection = mainContent.getByText("Groups", { exact: true }).first().locator("..").locator("..");
    await expect(groupsSection.locator("#groups-running-chart, .chart-empty-state").first()).toBeVisible();
    await expect(groupsSection.locator("#groups-monthly-chart, .chart-empty-state").last()).toBeVisible();

    const membersSection = mainContent
      .getByText("Members", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(membersSection.locator("#members-running-chart, .chart-empty-state").first()).toBeVisible();
    await expect(membersSection.locator("#members-monthly-chart, .chart-empty-state").last()).toBeVisible();

    const eventsSection = mainContent.getByText("Events", { exact: true }).first().locator("..").locator("..");
    await expect(eventsSection.locator("#events-running-chart, .chart-empty-state").first()).toBeVisible();
    await expect(eventsSection.locator("#events-monthly-chart, .chart-empty-state").last()).toBeVisible();

    const attendeesSection = mainContent
      .getByText("Attendees", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(
      attendeesSection.locator("#attendees-running-chart, .chart-empty-state").first(),
    ).toBeVisible();
    await expect(
      attendeesSection.locator("#attendees-monthly-chart, .chart-empty-state").last(),
    ).toBeVisible();
  });
});
