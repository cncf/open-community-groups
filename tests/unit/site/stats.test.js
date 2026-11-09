import { expect } from "@open-wc/testing";

import {
  createAreaChart,
  createMonthlyBarChart,
  dashboardFontFamily,
  getChartUiColors,
  getThemePalette,
} from "/static/js/common/charts/charts.js";
import { getCategoryLabelInterval, getTimeSplitNumber } from "/static/js/common/charts/stats.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { initializeSiteStatsFromPage, initSiteStatsCharts } from "/static/js/site/stats.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

/** Stats payload with two years of months in every section. */
const buildStatsPayload = () => {
  const section = {
    running_total: [
      [1735689600000, 2],
      [1738368000000, 3],
      [1740787200000, 12500],
    ],
    per_month: Array.from({ length: 24 }, (_, index) => {
      const year = 2025 + Math.floor(index / 12);
      const month = String((index % 12) + 1).padStart(2, "0");
      return [`${year}-${month}`, index + 1];
    }),
  };

  return { groups: section, members: section, events: section, attendees: section };
};

/**
 * Builds the options the stats page rendered before phones had their own, for one section.
 * @param {string} label Section label.
 * @param {Object} section Section payload.
 * @param {number} labelTarget Monthly label target of the viewport.
 * @returns {{monthly: Object, running: Object}} Chart options.
 */
const buildDesktopOptions = (label, section, labelTarget) => {
  const palette = getThemePalette();
  const legend = {
    bottom: 10,
    left: "center",
    itemGap: 12,
    textStyle: {
      fontFamily: dashboardFontFamily,
      fontSize: 12,
      color: getChartUiColors().muted,
    },
  };

  const running = createAreaChart(`${label} over time`, label, section.running_total, palette);
  running.baseOption.legend = Object.assign({}, running.baseOption.legend, legend);
  running.baseOption.grid = Object.assign({}, running.baseOption.grid, { bottom: 100 });
  running.xAxis = {
    axisLabel: { formatter: "{yyyy}-{MM}", hideOverlap: true },
    splitNumber: getTimeSplitNumber(section.running_total.length),
  };

  const monthly = createMonthlyBarChart(`New ${label} per Month`, label, section.per_month, palette);
  monthly.legend = Object.assign({}, monthly.legend, legend);
  monthly.xAxis = Object.assign({}, monthly.xAxis, {
    axisLabel: Object.assign({}, monthly.xAxis.axisLabel, {
      hideOverlap: false,
      rotate: 0,
      interval: getCategoryLabelInterval(monthly.xAxis.data.length, labelTarget),
      formatter: (value) => value,
    }),
  });

  return { monthly, running };
};

/**
 * Makes an option comparable by deep equality, with functions compared by source.
 * @param {Object} option ECharts option.
 * @returns {Object} Plain option.
 */
const toComparableOption = (option) =>
  JSON.parse(JSON.stringify(option, (_, value) => (typeof value === "function" ? String(value) : value)));

describe("site stats", () => {
  const originalEcharts = globalThis.echarts;
  let initCalls;
  let media;
  let resizeCalls;

  /**
   * Finds the option rendered into a chart.
   * @param {string} id Chart element id.
   * @returns {Object} ECharts option.
   */
  const getChartOption = (id) => initCalls.find(({ element }) => element.id === id)?.option;

  beforeEach(() => {
    resetDom();
    initCalls = [];
    resizeCalls = [];

    // Run the behavior under test.
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

    // Run the behavior under test.
    document.documentElement.style.setProperty("--color-primary-500", "#0f766e");
    document.documentElement.style.setProperty("--color-primary-700", "#115e59");
    document.documentElement.style.setProperty("--color-stone-400", "#78716c");
    media = stubMatchMedia();

    // Run the behavior under test.
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
    media.restore();
    if (originalEcharts) {
      globalThis.echarts = originalEcharts;
    } else {
      delete globalThis.echarts;
    }
  });

  it("renders charts for each stats section and registers resize handling", async () => {
    // Verify renders charts for each stats section and registers.
    await initSiteStatsCharts({
      groups: {
        running_total: [
          [1, 2],
          [2, 3],
        ],
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
      members: {
        running_total: [
          [1, 2],
          [2, 4],
        ],
        per_month: [["2025-01", 3]],
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
          [2, 5],
        ],
        per_month: [["2025-01", 4]],
      },
    });

    // Verify renders charts for each stats section and registers resize handling.
    expect(initCalls).to.have.length(8);

    // Prepare groups running option for rendering charts for each stats section.
    const groupsRunningOption = initCalls.find(
      ({ element }) => element.id === "groups-running-chart",
    )?.option;
    const groupsMonthlyOption = initCalls.find(
      ({ element }) => element.id === "groups-monthly-chart",
    )?.option;

    // Verify renders charts for each stats section and registers resize handling.
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

    // Dispatch the resize event.
    window.dispatchEvent(new Event("resize"));
    await new Promise((resolve) => setTimeout(resolve, 250));

    // Verify renders charts for each stats section and registers resize handling.
    expect(resizeCalls).to.include("groups-running-chart");
    expect(resizeCalls).to.include("attendees-monthly-chart");
  });

  for (const { name, queries, labelTarget } of [
    { name: "width 600", queries: ["(max-width: 640px)"], labelTarget: 4 },
    { name: "width 1280", queries: [], labelTarget: 8 },
  ]) {
    it(`keeps today's options when the phone query is false at ${name}`, async () => {
      // Match the viewport without matching the phone query.
      queries.forEach((query) => media.setMatches(query, true));
      const stats = buildStatsPayload();

      // Render every section.
      await initSiteStatsCharts(stats);

      // Verify each chart option deep-equals the pre-phone build.
      expect(initCalls).to.have.length(8);
      for (const [key, label] of [
        ["groups", "Groups"],
        ["members", "Members"],
        ["events", "Events"],
        ["attendees", "Attendees"],
      ]) {
        const expected = buildDesktopOptions(label, stats[key], labelTarget);
        expect(toComparableOption(getChartOption(`${key}-running-chart`))).to.deep.equal(
          toComparableOption(expected.running),
        );
        expect(toComparableOption(getChartOption(`${key}-monthly-chart`))).to.deep.equal(
          toComparableOption(expected.monthly),
        );
      }
    });
  }

  it("renders plain charts with short labels on phones", async () => {
    // Match the phone query above the old 640px label breakpoint.
    media.setMatches(PHONE_MEDIA_QUERY, true);

    // Render every section.
    await initSiteStatsCharts(buildStatsPayload());

    // Verify the area chart drops baseOption, media and the legend.
    const running = getChartOption("groups-running-chart");
    expect(running).to.not.have.any.keys("baseOption", "media");
    expect(running.legend).to.deep.equal({ show: false });
    expect(running.grid).to.deep.equal({ left: 8, right: 24, top: 56, bottom: 8, containLabel: true });
    expect(running.title.left).to.equal("center");
    expect(running.series[0].type).to.equal("line");

    // Verify the area chart's axes.
    expect(running.xAxis.type).to.equal("time");
    expect(running.xAxis.splitNumber).to.equal(4);
    expect(running.xAxis.axisLabel).to.include({ fontSize: 10, hideOverlap: true, rotate: 0 });
    expect(running.yAxis.axisLabel.fontSize).to.equal(10);
    expect(running.yAxis.axisLabel.formatter(12500)).to.equal("13K");
    expect(running.yAxis.axisLabel.formatter(7)).to.equal("7");

    // Verify the monthly chart gets the same treatment and four labels.
    const monthly = getChartOption("groups-monthly-chart");
    expect(monthly.legend).to.deep.equal({ show: false });
    expect(monthly.grid).to.deep.equal(running.grid);
    expect(monthly.xAxis.type).to.equal("category");
    expect(monthly.xAxis.axisLabel).to.include({ fontSize: 10, hideOverlap: true, interval: 5, rotate: 0 });
    expect(monthly.yAxis.axisLabel.formatter(1500)).to.equal("1.5K");

    // Verify every chart rendered and a single rotation listener was registered.
    expect(initCalls).to.have.length(8);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(1);
    expect(media.listeners("(max-width: 640px)").size).to.equal(0);
  });

  it("re-renders the charts when the viewport crosses the phone boundary", async () => {
    // The page always carries the stats marker, which the re-render guards on.
    const marker = document.createElement("script");
    marker.type = "application/json";
    marker.dataset.siteStats = "";
    document.body.append(marker);

    const latestOption = (id) => initCalls.filter(({ element }) => element.id === id).pop().option;

    // Render in the desktop layout first: the area chart keeps its media base option and legend.
    await initSiteStatsCharts(buildStatsPayload());
    expect(latestOption("groups-running-chart")).to.have.property("baseOption");
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(1);

    // Rotate into the phone layout and fire the media change.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(1);

    // The charts now use the phone layout without a second rotation listener being added.
    const phoneRunning = latestOption("groups-running-chart");
    expect(phoneRunning).to.not.have.any.keys("baseOption", "media");
    expect(phoneRunning.legend).to.deep.equal({ show: false });
    expect(phoneRunning.grid).to.deep.equal({ left: 8, right: 24, top: 56, bottom: 8, containLabel: true });
    expect(latestOption("attendees-monthly-chart").legend).to.deep.equal({ show: false });
  });

  it("initializes charts from the page payload only once", async () => {
    // Prepare the declarative stats payload used by the page template.
    const marker = document.createElement("script");
    marker.type = "application/json";
    marker.dataset.siteStats = "";
    marker.textContent = JSON.stringify({
      groups: {
        running_total: [
          [1, 1],
          [2, 2],
        ],
        per_month: [["2025-01", 1]],
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
    document.body.append(marker);

    // Run the page initializer twice to verify duplicate renders are guarded.
    await initializeSiteStatsFromPage(marker);
    await initializeSiteStatsFromPage();

    // Verify the page payload renders the same chart set once.
    expect(initCalls).to.have.length(8);
  });

  it("reinitializes restored page payloads on history restore", async () => {
    // Prepare a stats payload restored from a cached history snapshot.
    const marker = document.createElement("script");
    marker.type = "application/json";
    marker.dataset.siteStats = "";
    marker.dataset.siteStatsReady = "true";
    marker.textContent = JSON.stringify({
      groups: {
        running_total: [
          [1, 1],
          [2, 2],
        ],
        per_month: [["2025-01", 1]],
      },
      members: {
        running_total: [],
        per_month: [],
      },
      events: {
        running_total: [],
        per_month: [],
      },
      attendees: {
        running_total: [],
        per_month: [],
      },
    });
    document.body.append(marker);

    // Force rehydration for cached history restores.
    await initializeSiteStatsFromPage(document, { historyRestore: true });

    // The restored ready marker still renders its available chart data.
    expect(initCalls.map(({ element }) => element.id)).to.include("groups-running-chart");
  });
});
