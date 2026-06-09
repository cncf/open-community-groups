import { expect } from "@open-wc/testing";

import {
  initializeGroupAnalyticsFromPage,
  initAnalyticsCharts,
} from "/static/js/dashboard/group/analytics.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard group analytics", () => {
  const originalEcharts = globalThis.echarts;
  let setOptionCalls;

  const getGroupAnalyticsPayload = () => ({
    page_views: {
      total: {
        per_month_views: [["2025-01", 4]],
        per_day_views: [["2025-01-01", 2]],
      },
      group: {
        per_month_views: [["2025-01", 2]],
        per_day_views: [["2025-01-01", 1]],
      },
      events: {
        per_month_views: [["2025-01", 2]],
        per_day_views: [["2025-01-01", 1]],
      },
    },
    members: {
      running_total: [
        [1, 1],
        [2, 2],
      ],
      per_month: [["2025-01", 1]],
    },
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

    // Run the behavior under test.
    [
      "total-views-monthly-chart",
      "total-views-daily-chart",
      "group-views-monthly-chart",
      "group-views-daily-chart",
      "event-views-monthly-chart",
      "event-views-daily-chart",
      "members-running-chart",
      "members-monthly-chart",
      "events-running-chart",
      "events-monthly-chart",
      "attendees-running-chart",
      "attendees-monthly-chart",
    ].forEach((id) => {
      const div = document.createElement("div");
      div.id = id;
      document.body.append(div);
    });
  });

  afterEach(() => {
    resetDom();
    if (originalEcharts) {
      globalThis.echarts = originalEcharts;
    } else {
      delete globalThis.echarts;
    }
  });

  it("initializes the expected group analytics charts", async () => {
    // Verify initializes the expected group analytics charts.
    await initAnalyticsCharts(getGroupAnalyticsPayload());

    // Verify initializes the expected group analytics charts.
    expect(setOptionCalls).to.have.length(12);
    expect(setOptionCalls.map((call) => call.id)).to.include(
      "members-running-chart",
    );
    expect(setOptionCalls.map((call) => call.id)).to.include(
      "total-views-monthly-chart",
    );
    expect(setOptionCalls.map((call) => call.id)).to.include(
      "event-views-daily-chart",
    );
    expect(
      setOptionCalls.find((call) => call.id === "events-monthly-chart").option
        .title.text,
    ).to.equal("Events per Month");
    expect(
      setOptionCalls.find((call) => call.id === "attendees-monthly-chart")
        .option.title.text,
    ).to.equal("Attendees per Month");
    expect(
      setOptionCalls.find((call) => call.id === "total-views-monthly-chart")
        .option.title.subtext,
    ).to.equal("Group and event views grouped by month");
  });

  it("initializes charts from the page payload only once", async () => {
    // Prepare the declarative analytics payload used by the page template.
    const marker = document.createElement("script");
    marker.type = "application/json";
    marker.dataset.groupAnalytics = "";
    marker.textContent = JSON.stringify(getGroupAnalyticsPayload());
    document.body.append(marker);

    // Run the page initializer twice to verify duplicate renders are guarded.
    await initializeGroupAnalyticsFromPage();
    await initializeGroupAnalyticsFromPage();

    // Verify the page payload renders the expected charts once.
    expect(setOptionCalls).to.have.length(12);
    expect(setOptionCalls.map((call) => call.id)).to.include(
      "members-running-chart",
    );
  });

  it("initializes charts when analytics content is swapped by htmx", async () => {
    // Prepare swapped analytics content with a fresh declarative marker.
    const swappedRoot = document.createElement("section");
    const marker = document.createElement("script");
    marker.type = "application/json";
    marker.dataset.groupAnalytics = "";
    marker.textContent = JSON.stringify(getGroupAnalyticsPayload());
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
    expect(setOptionCalls).to.have.length(12);
    expect(marker.dataset.groupAnalyticsReady).to.equal("true");
  });
});
