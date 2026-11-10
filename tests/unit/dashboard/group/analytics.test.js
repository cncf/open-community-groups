import { expect } from "@open-wc/testing";

import {
  initializeGroupAnalyticsFromPage,
  initAnalyticsCharts,
} from "/static/js/dashboard/group/analytics.js";
import {
  THEME_CHANGE_EVENT,
  THEME_STORAGE_KEY,
} from "/static/js/common/theme.js";
import { waitForFrameThenTask } from "/tests/unit/test-utils/async.js";
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
    cohosted_events: {
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
      "cohosted-events-running-chart",
      "cohosted-events-monthly-chart",
      "attendees-running-chart",
      "attendees-monthly-chart",
    ].forEach((id) => {
      const div = document.createElement("div");
      div.id = id;
      document.body.append(div);
    });
  });

  afterEach(async () => {
    resetDom();
    localStorage.removeItem(THEME_STORAGE_KEY);
    await waitForFrameThenTask();
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
    expect(setOptionCalls).to.have.length(14);
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
      setOptionCalls.find((call) => call.id === "cohosted-events-monthly-chart")
        .option.title.text,
    ).to.equal("Co-hosted events per Month");
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
    expect(setOptionCalls).to.have.length(14);
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
    expect(setOptionCalls).to.have.length(14);
    expect(marker.dataset.groupAnalyticsReady).to.equal("true");
  });

  it("replaces every chart with the new palette on a color theme change", async () => {
    // Record every chart instance with the theme and option it rendered.
    const charts = [];
    globalThis.echarts = {
      getInstanceByDom() {
        return null;
      },
      init(element, theme) {
        const chart = {
          disposed: false,
          element,
          option: null,
          theme,
          dispose() {
            this.disposed = true;
          },
          isDisposed() {
            return this.disposed;
          },
          resize() {},
          setOption(option) {
            this.option = option;
          },
        };
        charts.push(chart);
        return chart;
      },
      registerTheme() {},
    };

    // Render the page payload under the light theme.
    localStorage.setItem(THEME_STORAGE_KEY, "light");
    const marker = document.createElement("script");
    marker.type = "application/json";
    marker.dataset.groupAnalytics = "";
    marker.textContent = JSON.stringify(getGroupAnalyticsPayload());
    document.body.append(marker);
    await initializeGroupAnalyticsFromPage();
    expect(charts).to.have.length(14);

    // Switch to a dark palette and announce the dark theme.
    document.documentElement.style.setProperty(
      "--color-primary-500",
      "#a855f7",
    );
    document.documentElement.style.setProperty(
      "--color-primary-700",
      "#7e22ce",
    );
    localStorage.setItem(THEME_STORAGE_KEY, "dark");
    document.dispatchEvent(new CustomEvent(THEME_CHANGE_EVENT));
    await waitForFrameThenTask();

    // Assert every light chart was disposed and replaced once.
    const liveCharts = charts.filter((chart) => !chart.disposed);
    expect(charts).to.have.length(28);
    expect(charts.slice(0, 14).every((chart) => chart.disposed)).to.equal(true);
    expect(liveCharts).to.have.length(14);
    expect(new Set(liveCharts.map((chart) => chart.element.id)).size).to.equal(
      14,
    );

    // Assert the new charts use the dark theme and only the new palette.
    liveCharts.forEach((chart) => {
      const option = JSON.stringify(chart.option);
      expect(chart.theme).to.equal("ocg-dark");
      expect(option).to.match(/#a855f7|#7e22ce/);
      expect(option).to.not.match(/#0f766e|#115e59/);
    });
  });
});
