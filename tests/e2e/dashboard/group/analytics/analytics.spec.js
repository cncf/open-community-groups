import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const expectChartSettled = async (page, selector) => {
  const chart = page.locator(selector);

  if ((await chart.count()) === 0) {
    await expect(page.locator(".chart-empty-state").first()).toBeVisible();
    return;
  }

  await expect(chart).toBeVisible();
  await expect(chart.locator("svg-spinner")).toHaveCount(0);
};

test.describe("group dashboard analytics view", () => {
  test("empty group analytics settles every chart slot", async ({
    organizerEmptyGroupPage,
  }) => {
    // Load analytics for the dedicated group without activity records.
    await navigateToPath(
      organizerEmptyGroupPage,
      "/dashboard/group?tab=analytics",
    );
    const dashboardContent = organizerEmptyGroupPage.locator(
      "#dashboard-content",
    );

    // Verify each chart resolves to an explicit empty visualization state.
    await expect(dashboardContent.locator(".chart-empty-state")).toHaveCount(12);
    await expect(dashboardContent.locator("[id$='-chart']")).toHaveCount(0);
  });

  test("organizer can view analytics summary cards and chart sections", async ({ organizerGroupPage }) => {
    // Load the group analytics dashboard before checking chart sections.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=analytics");

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can view analytics summary cards and chart sections.
    await expect(dashboardContent.getByText("Analytics", { exact: true })).toBeVisible();

    // Assert each expected case.
    for (const label of ["Members", "Events", "Attendees", "Page views"]) {
      await expect(dashboardContent.getByText(label, { exact: true }).first()).toBeVisible();
    }

    // Set up members section.
    const membersSection = dashboardContent
      .getByText("Members", { exact: true })
      .last()
      .locator("..")
      .locator("..");
    await expect(membersSection.getByText("Running total", { exact: true })).toBeVisible();
    await expect(membersSection.locator("#members-running-chart, .chart-empty-state").first()).toBeVisible();

    // Set up events section.
    const eventsSection = dashboardContent
      .getByText("Events", { exact: true })
      .last()
      .locator("..")
      .locator("..");
    await expect(eventsSection.getByText("Running total", { exact: true })).toBeVisible();
    await expect(eventsSection.locator("#events-running-chart, .chart-empty-state").first()).toBeVisible();

    // Set up attendees section.
    const attendeesSection = dashboardContent
      .getByText("Attendees", { exact: true })
      .last()
      .locator("..")
      .locator("..");
    await expect(attendeesSection.getByText("Running total", { exact: true })).toBeVisible();
    await expect(
      attendeesSection.locator("#attendees-running-chart, .chart-empty-state").first(),
    ).toBeVisible();

    // Set up page views section.
    const pageViewsSection = dashboardContent
      .getByText("Page views", { exact: true })
      .last()
      .locator("..")
      .locator("..");
    await expect(pageViewsSection).toBeVisible();
    await expect(pageViewsSection.getByText("Group page", { exact: true })).toBeVisible();
    await expect(pageViewsSection.getByText("Event pages", { exact: true })).toBeVisible();
    await expect(
      pageViewsSection.locator(".chart-empty-state, #group-views-monthly-chart").first(),
    ).toBeVisible();

    // Verify representative charts finish rendering or show the empty state.
    await expectChartSettled(organizerGroupPage, "#members-running-chart");
    await expectChartSettled(organizerGroupPage, "#events-running-chart");
    await expectChartSettled(organizerGroupPage, "#attendees-running-chart");

    // Verify all chart slots and summary card descriptions are rendered.
    await expect(dashboardContent.locator(".chart-empty-state, [id$='-chart']")).toHaveCount(12);
    for (const summaryCopy of [
      "People in this group",
      "Published and past events",
      "Total RSVPs",
      "Group and event page views",
    ]) {
      await expect(dashboardContent.getByText(summaryCopy, { exact: true })).toBeVisible();
    }
  });

  test("organizer can include subgroup analytics", async ({ organizerGroupPage }) => {
    // Load group analytics before including subgroup data.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=analytics");

    // Find the subgroup toggle and verify its initial state.
    const includeSubgroups = organizerGroupPage.getByRole("checkbox", {
      name: "Include subgroups",
    });
    await expect(includeSubgroups).toBeVisible();
    await expect(includeSubgroups).not.toBeChecked();

    // Enable subgroup analytics and wait for the section to refresh. The real
    // checkbox is visually hidden, so toggle it through its label text.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/group/analytics") &&
          response.url().includes("include_subgroups=true") &&
          response.ok(),
      ),
      organizerGroupPage.getByText("Include subgroups", { exact: true }).click(),
    ]);
    // Verify the refreshed toggle and hierarchy-counting guidance.
    await expect(
      organizerGroupPage.getByRole("checkbox", {
        name: "Include subgroups",
      }),
    ).toBeChecked();
    await expect(
      organizerGroupPage.getByText(
        "When enabled, every statistic on this page includes active subgroups. Members are counted as unique people across the hierarchy.",
        { exact: true },
      ),
    ).toBeVisible();
  });
});
