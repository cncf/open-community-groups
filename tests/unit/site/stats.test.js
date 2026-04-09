import { expect } from "@open-wc/testing";

import { initSiteStatsCharts } from "/static/js/site/stats.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("site stats", () => {
  const originalEcharts = globalThis.echarts;
  let initCalls;
  let resizeCalls;

  beforeEach(() => {
    resetDom();
    initCalls = [];
    resizeCalls = [];

    globalThis.echarts = {
      getInstanceByDom() {
        return null;
      },
      init(element) {
        const chart = {
          setOption(option) {
            initCalls.push({ element, option });
          },
          resize() {
            resizeCalls.push(element.id);
          },
        };
        return chart;
      },
    };

    document.documentElement.style.setProperty("--color-primary-500", "#0f766e");
    document.documentElement.style.setProperty("--color-primary-700", "#115e59");

    [
      "groups-running-chart",
      "groups-monthly-chart",
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

  it("renders charts for each stats section and registers resize handling", async () => {
    await initSiteStatsCharts({
      groups: { running_total: [[1, 2], [2, 3]], per_month: [["2025-01", 2]] },
      members: { running_total: [[1, 2], [2, 4]], per_month: [["2025-01", 3]] },
      events: { running_total: [[1, 1], [2, 2]], per_month: [["2025-01", 1]] },
      attendees: { running_total: [[1, 1], [2, 5]], per_month: [["2025-01", 4]] },
    });

    expect(initCalls).to.have.length(8);

    window.dispatchEvent(new Event("resize"));
    await new Promise((resolve) => setTimeout(resolve, 250));

    expect(resizeCalls).to.include("groups-running-chart");
    expect(resizeCalls).to.include("attendees-monthly-chart");
  });
});
