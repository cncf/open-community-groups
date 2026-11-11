import { expect, test } from "../../fixtures.js";
import { navigateToPath } from "../../utils.js";

const PUBLIC_STATS_CHART_IDS = [
  "groups-running-chart",
  "groups-monthly-chart",
  "members-running-chart",
  "members-monthly-chart",
  "events-running-chart",
  "events-monthly-chart",
  "attendees-running-chart",
  "attendees-monthly-chart",
];

/** Public stats sections in display order, with the nouns their chart summaries use. */
const PUBLIC_STATS_SECTIONS = [
  { key: "groups", noun: "group", title: "Groups" },
  { key: "members", noun: "member", title: "Members" },
  { key: "events", noun: "event", title: "Events" },
  { key: "attendees", noun: "attendee", title: "Attendees" },
];

test.describe("site stats page", () => {
  test("renders totals and analytics chart containers", async ({ page }) => {
    // Load the public stats page before checking analytics sections.
    await navigateToPath(page, "/stats");

    // Find the main content.
    const mainContent = page.locator("#main-content");

    // Verify the page heading and description.
    await expect(mainContent.getByRole("heading", { level: 1, name: "Stats" })).toBeVisible();
    await expect(
      mainContent.getByText("Global growth trends across all communities.", {
        exact: true,
      }),
    ).toBeVisible();

    // Verify each section, found by its heading, holds its running and monthly slots.
    for (const { key, title } of PUBLIC_STATS_SECTIONS) {
      const section = statsSection(page, mainContent, title);
      await expect(section).toHaveCount(1);
      await expect(section.locator(`#${key}-running-chart, .chart-empty-state`).first()).toBeVisible();
      await expect(section.locator(`#${key}-monthly-chart, .chart-empty-state`).last()).toBeVisible();
    }

    // Verify representative charts finish rendering or show the empty state.
    await expectChartSettled(page, "#groups-running-chart");
    await expectChartSettled(page, "#members-running-chart");
    await expectChartSettled(page, "#events-running-chart");
    await expectChartSettled(page, "#attendees-running-chart");

    // Count rendered and empty chart slots to cover the complete page contract.
    const renderedCharts = mainContent.locator(
      PUBLIC_STATS_CHART_IDS.map((chartId) => `#${chartId}`).join(", "),
    );
    const emptyCharts = mainContent.locator(".chart-empty-state");
    await expect
      .poll(async () => (await renderedCharts.count()) + (await emptyCharts.count()))
      .toBe(PUBLIC_STATS_CHART_IDS.length);

    // Verify each rendered chart is visible and settled.
    for (const chartId of PUBLIC_STATS_CHART_IDS) {
      const chart = mainContent.locator(`#${chartId}`);
      if ((await chart.count()) > 0) {
        await expect(chart).toBeVisible();
        await expect(chart.locator("svg-spinner")).toHaveCount(0);
      }
    }

    // Verify the embedded payload contains every public statistics area.
    // The stats payload script is rendered outside #main-content.
    const statsPayload = await page.locator("script[data-site-stats]").textContent();
    const parsedStats = JSON.parse(statsPayload);
    expect(Object.keys(parsedStats)).toEqual(
      expect.arrayContaining(["groups", "members", "events", "attendees"]),
    );
  });

  test("describes each rendered chart in text", async ({ page }) => {
    // Load the public stats page before reading the chart summaries.
    await navigateToPath(page, "/stats");
    const mainContent = page.locator("#main-content");

    // Verify each rendered chart card carries its summary and empty slots carry none.
    const month = String.raw`\w+ \d{4}`;
    const count = (word) => String.raw`[\d,]+ ${word}s?`;
    let renderedCharts = 0;
    for (const { key, noun, title } of PUBLIC_STATS_SECTIONS) {
      const section = statsSection(page, mainContent, title);
      const charts = [
        {
          id: `${key}-running-chart`,
          summary: new RegExp(
            String.raw`^${title} over time: went from ${count(noun)} in ${month} to ${count(noun)} in ${month}\.$`,
          ),
        },
        {
          id: `${key}-monthly-chart`,
          summary: new RegExp(
            String.raw`^New ${noun}s per month: ${count(`new ${noun}`)} (in ${month}|from ${month} to ${month}\. The busiest month was ${month} with [\d,]+)\.$`,
          ),
        },
      ];
      for (const { id, summary } of charts) {
        const chart = section.locator(`#${id}`);
        if ((await chart.count()) > 0) {
          renderedCharts += 1;
          await expect(chart.locator("..").getByText(summary)).toHaveCount(1);
        } else {
          await expect(section.getByText(summary)).toHaveCount(0);
        }
      }
    }

    // Verify the seeded data renders at least one described chart.
    expect(renderedCharts).toBeGreaterThan(0);
  });

  test("keeps every statistics card and chart available on mobile @mobile", async ({ page }) => {
    // Load public statistics using the mobile project viewport.
    await navigateToPath(page, "/stats");

    // Verify every summary card and chart slot remains available.
    const mainContent = page.locator("#main-content");
    await expect(mainContent.getByRole("heading", { level: 1, name: "Stats" })).toBeVisible();
    // Each total card mixes the label with its value, so match by substring.
    await expect(mainContent.getByText("Total")).toHaveCount(4);
    await expect(mainContent.locator("section")).toHaveCount(4);
    await expect(mainContent.locator(".chart-empty-state, [id$='-chart']")).toHaveCount(
      PUBLIC_STATS_CHART_IDS.length,
    );
  });

  test("shortens charts and pins sentence case headings on phones @mobile", async ({ page }) => {
    // Load public statistics using the mobile project viewport.
    await navigateToPath(page, "/stats");

    // Verify each running and monthly slot takes its phone height.
    const mainContent = page.locator("#main-content");
    const heights = await mainContent
      .locator(".chart-empty-state, [id$='-chart']")
      .evaluateAll((elements) => elements.map((element) => element.offsetHeight));
    expect(heights).toEqual([224, 208, 224, 208, 224, 208, 224, 208]);

    // Verify the heading pins in desktop's sentence case on the canvas.
    const heading = mainContent.locator(".section-strip").first();
    const style = await heading.evaluate((element) => {
      const { position, textTransform } = getComputedStyle(element);
      return { position, textTransform };
    });
    expect(style).toEqual({ position: "sticky", textTransform: "none" });

    // Verify the Total box stays beside the title, inside the 12px gutter.
    const headingBox = await heading.boundingBox();
    const totalBox = await heading.getByText("Total").boundingBox();
    expect(headingBox.x).toBe(0);
    expect(totalBox.y + totalBox.height).toBeLessThanOrEqual(headingBox.y + headingBox.height);
    expect(totalBox.x + totalBox.width).toBeCloseTo(headingBox.width - 12, 0);
  });
});

/** Returns the stats section named by its level-2 heading. */
const statsSection = (page, mainContent, title) =>
  mainContent.locator("section").filter({
    has: page.getByRole("heading", { level: 2, name: title, exact: true }),
  });

/** Waits for a stats chart or its empty state to settle. */
const expectChartSettled = async (page, selector) => {
  const chart = page.locator(selector);

  if ((await chart.count()) === 0) {
    await expect(page.locator(".chart-empty-state").first()).toBeVisible();
    return;
  }

  await expect(chart).toBeVisible();
  await expect(chart.locator("svg-spinner")).toHaveCount(0);
};
