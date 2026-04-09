import { expect } from "@open-wc/testing";

import { initAnalyticsCharts } from "/static/js/dashboard/community/analytics.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard community analytics", () => {
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

    document.body.innerHTML = `
      <button data-analytics-tab="groups"></button>
      <div data-analytics-content="groups"></div>
      <div id="groups-running-chart"></div>
      <div id="groups-monthly-chart"></div>
      <div id="groups-category-chart"></div>
      <div id="groups-region-chart"></div>
      <div id="groups-running-category-chart"></div>
      <div id="groups-running-region-chart"></div>
      <div id="groups-monthly-category-chart"></div>
      <div id="groups-monthly-region-chart"></div>
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
    await initAnalyticsCharts({
      groups: {
        running_total: [[1, 1], [2, 2]],
        per_month: [["2025-01", 1]],
        total_by_category: [["Cloud", 3]],
        total_by_region: [["EU", 2]],
        running_total_by_category: { Cloud: [[1, 1], [2, 2]] },
        running_total_by_region: { EU: [[1, 1], [2, 2]] },
        per_month_by_category: { Cloud: [["2025-01", 1]] },
        per_month_by_region: { EU: [["2025-01", 1]] },
      },
    });

    expect(setOptionCalls).to.have.length(8);
    expect(setOptionCalls.map((call) => call.id)).to.include("groups-region-chart");
    expect(document.querySelector('[data-analytics-tab="groups"]').dataset.active).to.equal("true");
  });
});
