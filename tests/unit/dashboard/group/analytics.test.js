import { expect } from "@open-wc/testing";

import { initAnalyticsCharts } from "/static/js/dashboard/group/analytics.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard group analytics", () => {
  const originalEcharts = globalThis.echarts;
  let setOptionCalls;

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
    document.documentElement.style.setProperty("--color-primary-500", "#0f766e");
    document.documentElement.style.setProperty("--color-primary-700", "#115e59");

    [
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
    await initAnalyticsCharts({
      page_views: {
        group: { per_month_views: [["2025-01", 2]], per_day_views: [["2025-01-01", 1]] },
        events: { per_month_views: [["2025-01", 2]], per_day_views: [["2025-01-01", 1]] },
      },
      members: { running_total: [[1, 1], [2, 2]], per_month: [["2025-01", 1]] },
      events: { running_total: [[1, 1], [2, 2]], per_month: [["2025-01", 1]] },
      attendees: { running_total: [[1, 1], [2, 2]], per_month: [["2025-01", 1]] },
    });

    expect(setOptionCalls).to.have.length(10);
    expect(setOptionCalls.map((call) => call.id)).to.include("members-running-chart");
    expect(setOptionCalls.map((call) => call.id)).to.include("event-views-daily-chart");
  });
});
