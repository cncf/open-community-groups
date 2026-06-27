import { expect, test } from "@playwright/test";

import { navigateToPath } from "../../utils.js";

const expectChartSettled = async (page, selector) => {
  const chart = page.locator(selector);

  if ((await chart.count()) === 0) {
    return;
  }

  await expect(chart).toBeVisible();
  await expect(chart.locator("svg-spinner")).toHaveCount(0);
};

test.describe("site stats page", () => {
  test("renders totals and analytics chart containers", async ({ page }) => {
    // Load the public stats page before checking analytics sections.
    await navigateToPath(page, "/stats");

    // Find the main content.
    const mainContent = page.locator("#main-content");

    // Verify renders totals and analytics chart containers.
    await expect(
      mainContent.getByRole("heading", {
        level: 1,
        name: "GOUP momentum at a glance",
      }),
    ).toBeVisible();
    await expect(
      mainContent.getByText(
        "A live-feeling view of community growth, alliance groups, event activity, and ecosystem signals as they come online.",
        { exact: true },
      ),
    ).toBeVisible();

    // Assert each expected case.
    for (const sectionName of ["Groups", "Members", "Events", "Attendees"]) {
      await expect(
        mainContent.getByText(sectionName, { exact: true }).first(),
      ).toBeVisible();
    }

    // Verify representative charts finish rendering or show an empty state.
    await expectChartSettled(page, "#groups-running-chart");
    await expectChartSettled(page, "#groups-monthly-chart");
    await expectChartSettled(page, "#members-running-chart");
    await expectChartSettled(page, "#members-monthly-chart");
    await expectChartSettled(page, "#events-running-chart");
    await expectChartSettled(page, "#events-monthly-chart");
    await expectChartSettled(page, "#attendees-running-chart");
    await expectChartSettled(page, "#attendees-monthly-chart");
  });
});
