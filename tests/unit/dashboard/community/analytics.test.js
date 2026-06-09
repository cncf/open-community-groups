import { expect } from "@open-wc/testing";

import {
  initializeCommunityAnalyticsFromPage,
  initAnalyticsCharts,
} from "/static/js/dashboard/community/analytics.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard community analytics", () => {
  const originalEcharts = globalThis.echarts;
  let setOptionCalls;

  const getCommunityAnalyticsPayload = () => ({
    groups: {
      running_total: [
        [1, 1],
        [2, 2],
      ],
      per_month: [["2025-01", 1]],
      total_by_category: [["Cloud", 3]],
      total_by_region: [["EU", 2]],
      running_total_by_category: {
        Cloud: [
          [1, 1],
          [2, 2],
        ],
      },
      running_total_by_region: {
        EU: [
          [1, 1],
          [2, 2],
        ],
      },
      per_month_by_category: { Cloud: [["2025-01", 1]] },
      per_month_by_region: { EU: [["2025-01", 1]] },
    },
  });

  beforeEach(() => {
    resetDom();
    setOptionCalls = [];
    globalThis.echarts = {
      getInstanceByDom() {
        return null;
      },
      init(element) {
        return {
          setOption(option) {
            setOptionCalls.push({ id: element.id, option });
          },
          resize() {},
        };
      },
    };
    document.documentElement.style.setProperty(
      "--color-primary-500",
      "#0f766e",
    );
    document.documentElement.style.setProperty(
      "--color-primary-700",
      "#115e59",
    );

    // Build the DOM fixture.
    document.body.innerHTML = `
      <button data-analytics-tab="groups"></button>
      <button data-analytics-tab="events"></button>
      <button data-analytics-tab="attendees"></button>
      <button data-analytics-tab="page-views"></button>
      <div data-analytics-content="groups"></div>
      <div data-analytics-content="events"></div>
      <div data-analytics-content="attendees"></div>
      <div data-analytics-content="page-views"></div>
      <div id="groups-running-chart"></div>
      <div id="groups-monthly-chart"></div>
      <div id="groups-category-chart"></div>
      <div id="groups-region-chart"></div>
      <div id="groups-running-category-chart"></div>
      <div id="groups-running-region-chart"></div>
      <div id="groups-monthly-category-chart"></div>
      <div id="groups-monthly-region-chart"></div>
      <div id="events-running-chart"></div>
      <div id="events-monthly-chart"></div>
      <div id="attendees-running-chart"></div>
      <div id="attendees-monthly-chart"></div>
      <div id="total-views-monthly-chart"></div>
      <div id="total-views-daily-chart"></div>
    `;
  });

  afterEach(() => {
    resetDom();
    if (originalEcharts) {
      globalThis.echarts = originalEcharts;
    } else {
      delete globalThis.echarts;
    }
  });

  it("initializes the default groups analytics tab", async () => {
    // Verify initializes the default groups analytics tab.
    await initAnalyticsCharts(getCommunityAnalyticsPayload());

    // Verify initializes the default groups analytics tab.
    expect(setOptionCalls).to.have.length(8);
    expect(setOptionCalls.map((call) => call.id)).to.include(
      "groups-region-chart",
    );
    expect(
      setOptionCalls.find((call) => call.id === "groups-running-chart").option
        .baseOption.title.subtext,
    ).to.equal("Cumulative active groups over time");
    expect(
      document.querySelector('[data-analytics-tab="groups"]').dataset.active,
    ).to.equal("true");
  });

  it("initializes charts from the page payload only once", async () => {
    // Prepare the declarative analytics payload used by the page template.
    const marker = document.createElement("script");
    marker.type = "application/json";
    marker.dataset.communityAnalytics = "";
    marker.textContent = JSON.stringify(getCommunityAnalyticsPayload());
    document.body.append(marker);

    // Run the page initializer twice to verify duplicate renders are guarded.
    await initializeCommunityAnalyticsFromPage();
    await initializeCommunityAnalyticsFromPage();

    // Verify the page payload renders the default groups charts once.
    expect(setOptionCalls).to.have.length(8);
    expect(
      document.querySelector('[data-analytics-tab="groups"]').dataset.active,
    ).to.equal("true");
  });

  it("initializes charts when analytics content is swapped by htmx", async () => {
    // Prepare swapped analytics content with a fresh declarative marker.
    const swappedRoot = document.createElement("section");
    const marker = document.createElement("script");
    marker.type = "application/json";
    marker.dataset.communityAnalytics = "";
    marker.textContent = JSON.stringify(getCommunityAnalyticsPayload());
    swappedRoot.append(marker);
    document.body.append(swappedRoot);

    // Dispatch the HTMX load event that follows swapped dashboard content.
    swappedRoot.dispatchEvent(
      new CustomEvent("htmx:load", {
        bubbles: true,
      }),
    );
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Verify the swapped marker initializes the analytics charts.
    expect(setOptionCalls).to.have.length(8);
    expect(marker.dataset.communityAnalyticsReady).to.equal("true");
  });

  it("uses clearer event, attendee, and total page-view chart titles", async () => {
    // Verify uses clearer event, attendee, and total page-view.
    await initAnalyticsCharts({
      groups: {},
      events: {
        running_total: [
          [1, 1],
          [2, 2],
        ],
        per_month: [["2025-01", 1]],
      },
      attendees: {
        running_total: [
          [1, 1],
          [2, 2],
        ],
        per_month: [["2025-01", 1]],
      },
      page_views: {
        total: {
          per_month_views: [["2025-01", 4]],
          per_day_views: [["2025-01-01", 4]],
        },
      },
    });

    // Verify uses clearer event, attendee, and total page-view.
    setOptionCalls = [];
    document.querySelector('[data-analytics-tab="events"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Verify uses clearer event, attendee, and total page-view chart titles.
    expect(
      setOptionCalls.find((call) => call.id === "events-monthly-chart").option
        .title.text,
    ).to.equal("Events per Month");
    expect(
      setOptionCalls.find((call) => call.id === "events-monthly-chart").option
        .title.subtext,
    ).to.equal("Published events by scheduled month");

    // Verify uses clearer event, attendee, and total page-view.
    setOptionCalls = [];
    document.querySelector('[data-analytics-tab="attendees"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Verify uses clearer event, attendee, and total page-view chart titles.
    expect(
      setOptionCalls.find((call) => call.id === "attendees-monthly-chart")
        .option.title.text,
    ).to.equal("Attendees per Month");
    expect(
      setOptionCalls.find((call) => call.id === "attendees-monthly-chart")
        .option.title.subtext,
    ).to.equal("Event RSVPs created each month");

    // Verify uses clearer event, attendee, and total page-view.
    setOptionCalls = [];
    document.querySelector('[data-analytics-tab="page-views"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Verify uses clearer event, attendee, and total page-view chart titles.
    expect(
      setOptionCalls.find((call) => call.id === "total-views-monthly-chart")
        .option.title.text,
    ).to.equal("Monthly total page views");
    expect(
      setOptionCalls.find((call) => call.id === "total-views-monthly-chart")
        .option.title.subtext,
    ).to.equal("All tracked views grouped by month");
  });
});
