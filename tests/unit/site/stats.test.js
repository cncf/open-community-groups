import { expect } from "@open-wc/testing";

import { initSiteStatsCharts } from "/static/js/site/stats.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("site stats", () => {
  const originalEcharts = globalThis.echarts;
  const originalMatchMedia = window.matchMedia;
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
    document.documentElement.style.setProperty("--color-stone-400", "#78716c");
    window.matchMedia = () => ({
      matches: false,
      addEventListener() {},
      removeEventListener() {},
    });

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
    window.matchMedia = originalMatchMedia;
    if (originalEcharts) {
      globalThis.echarts = originalEcharts;
    } else {
      delete globalThis.echarts;
    }
  });

  it("renders charts for each stats section and registers resize handling", async () => {
    await initSiteStatsCharts({
      groups: {
        running_total: [[1, 2], [2, 3]],
        per_month: [
          ["2025-01", 1],
          ["2025-02", 2],
          ["2025-03", 3],
          ["2025-04", 4],
          ["2025-05", 5],
          ["2025-06", 6],
          ["2025-07", 7],
          ["2025-08", 8],
          ["2025-09", 9],
          ["2025-10", 10],
          ["2025-11", 11],
          ["2025-12", 12],
        ],
      },
      members: { running_total: [[1, 2], [2, 4]], per_month: [["2025-01", 3]] },
      events: { running_total: [[1, 1], [2, 2]], per_month: [["2025-01", 1]] },
      attendees: { running_total: [[1, 1], [2, 5]], per_month: [["2025-01", 4]] },
    });

    expect(initCalls).to.have.length(8);

    const groupsRunningOption = initCalls.find(({ element }) => element.id === "groups-running-chart")?.option;
    const groupsMonthlyOption = initCalls.find(({ element }) => element.id === "groups-monthly-chart")?.option;

    expect(groupsRunningOption.baseOption.legend).to.include({
      bottom: 10,
      left: "center",
      itemGap: 12,
    });
    expect(groupsRunningOption.baseOption.legend.textStyle.fontFamily).to.include("Inter");
    expect(groupsRunningOption.baseOption.legend.textStyle.color).to.not.equal("");
    expect(groupsRunningOption.xAxis.splitNumber).to.equal(3);
    expect(groupsRunningOption.xAxis.axisLabel.formatter).to.equal("{yyyy}-{MM}");
    expect(groupsMonthlyOption.xAxis.axisLabel.interval).to.equal(1);
    expect(groupsMonthlyOption.xAxis.axisLabel.formatter("Jan'25")).to.equal("Jan'25");
    expect(groupsMonthlyOption.legend.bottom).to.equal(10);

    window.dispatchEvent(new Event("resize"));
    await new Promise((resolve) => setTimeout(resolve, 250));

    expect(resizeCalls).to.include("groups-running-chart");
    expect(resizeCalls).to.include("attendees-monthly-chart");
  });
});
