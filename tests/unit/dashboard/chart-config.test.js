import { expect } from "@open-wc/testing";

import {
  buildRecentBarSeries,
  buildStackedMonthlySeries,
  createAreaChart,
  createHorizontalBarChart,
  createPieChart,
  createStackedAreaChart,
  createStackedDailyBarChart,
  createStackedMonthlyChart,
  formatDayAxisLabel,
  getAxisTooltipConfig,
  getDailyLineSymbolConfig,
  getDayMarkersConfig,
  getChartGridLineColor,
  getChartTheme,
  getChartTitleConfig,
  getChartUiColors,
  getItemTooltipConfig,
  getValueAxisConfig,
  getVerticalBarCategoryAxisConfig,
  getVerticalBarSeriesStyle,
  hasActivity,
  initChart,
  toCategorySeries,
  toChartColor,
  withAlpha,
} from "/static/js/common/charts/charts.js";
import { THEME_STORAGE_KEY } from "/static/js/common/theme.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const palette = {
  50: "#f0fdfa",
  100: "#ccfbf1",
  200: "#99f6e4",
  300: "#5eead4",
  400: "#2dd4bf",
  500: "#14b8a6",
  600: "#0d9488",
  700: "#0f766e",
  800: "#115e59",
  900: "#134e4a",
  950: "#042f2e",
};

/**
 * Sets the chart token colors on the root element.
 * @param {Object<string, string>} colors - Colors keyed by CSS custom property name.
 */
const setChartTokens = (colors) => {
  Object.entries(colors).forEach(([name, value]) => document.documentElement.style.setProperty(name, value));
};

/** Dark token values of the chart readers. */
const DARK_CHART_TOKENS = {
  "--color-stone-100": "#292524",
  "--color-stone-200": "#44403c",
  "--color-stone-300": "#57534e",
  "--color-stone-400": "#a8a29e",
  "--color-stone-700": "#e7e5e4",
  "--color-surface": "#181514",
};

/**
 * Creates an ECharts stub recording theme registrations and chart inits.
 * @returns {{echarts: Object, initCalls: Array<Array>, registerThemeCalls: Array<Array>}} Stub and calls.
 */
const createEchartsThemeStub = () => {
  const initCalls = [];
  const registerThemeCalls = [];

  return {
    echarts: {
      init(...args) {
        initCalls.push(args);
        return { setOption() {} };
      },
      registerTheme(...args) {
        registerThemeCalls.push(args);
      },
    },
    initCalls,
    registerThemeCalls,
  };
};

describe("dashboard chart config helpers", () => {
  const originalEcharts = globalThis.echarts;

  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
    localStorage.removeItem(THEME_STORAGE_KEY);
    if (originalEcharts) {
      globalThis.echarts = originalEcharts;
    } else {
      delete globalThis.echarts;
    }
  });

  it("builds monthly bar series without reserving empty periods", () => {
    // Verify builds monthly bar series without reserving empty periods.
    expect(
      buildRecentBarSeries(
        [
          ["2025-01", "2"],
          ["2025-02", 5],
        ],
        "month",
        24,
        { reservePeriodStart: false },
      ),
    ).to.deep.equal({
      categories: ["Jan'25", "Feb'25"],
      values: [2, 5],
    });
  });

  it("normalizes category tuples and bar sizing options", () => {
    // Verify normalizes category tuples and bar sizing options.
    expect(
      toCategorySeries([
        ["Talks", "12"],
        ["Workshops", 4],
      ]),
    ).to.deep.equal([
      { name: "Talks", value: 12 },
      { name: "Workshops", value: 4 },
    ]);

    // Verify normalizes category tuples and bar sizing options.
    expect(getVerticalBarSeriesStyle(12)).to.deep.equal({
      barMaxWidth: 35,
      barMinWidth: 12,
      barCategoryGap: "30%",
    });
    expect(getVerticalBarSeriesStyle(30)).to.deep.equal({
      barMaxWidth: 35,
      barCategoryGap: "30%",
    });
    expect(getVerticalBarSeriesStyle(48)).to.deep.equal({
      barMaxWidth: 11,
      barCategoryGap: "45%",
    });
    expect(getVerticalBarSeriesStyle(80)).to.deep.equal({
      barMaxWidth: 8,
      barCategoryGap: "35%",
    });
  });

  it("formats sparse category axis labels", () => {
    // Prepare categories for formatting sparse category axis labels.
    const categories = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct"];
    const axisConfig = getVerticalBarCategoryAxisConfig(categories);
    const formatter = axisConfig.axisLabel.formatter;

    // Verify formats sparse category axis labels.
    expect(formatter("Jan", 0)).to.equal("Jan");
    expect(formatter("Feb", 1)).to.equal("");
    expect(formatter("Mar", 2)).to.equal("Mar");
    expect(formatter("Oct", 9)).to.equal("Oct");
  });

  it("reads shared chart colors and tooltip config from css variables", () => {
    // Verify reads shared chart colors and tooltip config.
    document.documentElement.style.setProperty("--color-stone-100", "#f5f5f4");
    document.documentElement.style.setProperty("--color-stone-200", "#e7e5e4");
    document.documentElement.style.setProperty("--color-stone-700", "#44403c");
    document.documentElement.style.setProperty("--color-surface", "#ffffff");
    // A leftover white read would fail the expectations below.
    document.documentElement.style.setProperty("--color-white", "#000000");

    // Assert the chart grid line color.
    expect(getChartGridLineColor()).to.equal("#f5f5f4");

    // Assert the axis tooltip config.
    expect(getAxisTooltipConfig()).to.deep.equal({
      trigger: "axis",
      backgroundColor: "#ffffff",
      borderColor: "#e7e5e4",
      borderWidth: 1,
      textStyle: { color: "#44403c" },
    });

    // Verify reads shared chart colors and tooltip config from css variables.
    expect(getItemTooltipConfig()).to.deep.equal({
      trigger: "item",
      backgroundColor: "#ffffff",
      borderColor: "#e7e5e4",
      borderWidth: 1,
      textStyle: { color: "#44403c" },
    });

    // Assert the chart surface color.
    expect(getChartUiColors().surface).to.equal("#ffffff");
  });

  it("converts css colors that echarts cannot parse into rgb", () => {
    // Assert formats echarts parses are kept as they are.
    expect(toChartColor("#d6d3d1")).to.equal("#d6d3d1");
    expect(toChartColor("rgb(214, 211, 209)")).to.equal("rgb(214, 211, 209)");
    expect(toChartColor("")).to.equal("");

    // Assert oklch theme colors read from css variables become rgb.
    document.documentElement.style.setProperty("--color-stone-100", "oklch(97% 0.001 106.424)");
    expect(getChartGridLineColor()).to.match(/^rgb\(\d+, \d+, \d+\)$/);
    expect(toChartColor("oklch(0% 0 0)")).to.equal("rgb(0, 0, 0)");
    expect(toChartColor("oklch(100% 0 0 / 50%)")).to.match(/^rgba\(\d+, \d+, \d+, 0\.5\d*\)$/);
  });

  it("sets the opacity of hex and rgb chart colors", () => {
    // Assert short and long hex colors become rgba with the opacity.
    expect(withAlpha("#fff", 0)).to.equal("rgba(255, 255, 255, 0)");
    expect(withAlpha("#0094ff", 0.5)).to.equal("rgba(0, 148, 255, 0.5)");

    // Assert canvas read-back colors keep their channels and take the new opacity.
    expect(withAlpha("rgb(24, 21, 20)", 0)).to.equal("rgba(24, 21, 20, 0)");
    expect(withAlpha("rgba(1, 2, 3, 0.5)", 0.25)).to.equal("rgba(1, 2, 3, 0.25)");

    // Assert unset and unsupported colors are returned as they are.
    expect(withAlpha("", 0)).to.equal("");
    expect(withAlpha("hsl(0 0% 100%)", 0)).to.equal("hsl(0 0% 100%)");
  });

  it("fades the area chart into the transparent surface", () => {
    // Build an area chart over the light surface.
    const data = [
      [1, 1],
      [2, 2],
    ];
    const getEndStop = () =>
      createAreaChart("Members over time", "Members", data, palette).baseOption.series[0].areaStyle.color
        .colorStops[1];
    document.documentElement.style.setProperty("--color-surface", "#fff");

    // Assert the light end stop keeps the exact white transparent string.
    expect(getEndStop()).to.deep.equal({ offset: 1, color: "rgba(255, 255, 255, 0)" });

    // Assert a dark surface ends the fade in its own transparent color.
    document.documentElement.style.setProperty("--color-surface", "#181514");
    expect(getEndStop()).to.deep.equal({ offset: 1, color: "rgba(24, 21, 20, 0)" });
  });

  it("builds the dark chart theme from the chart token readers", () => {
    // Set the dark token values the readers return.
    setChartTokens(DARK_CHART_TOKENS);
    const axisTheme = {
      axisLabel: { color: "#a8a29e" },
      axisLine: { lineStyle: { color: "#57534e" } },
      axisTick: { lineStyle: { color: "#57534e" } },
      splitLine: { lineStyle: { color: "#292524" } },
    };

    // Assert every field maps to its token reader.
    expect(getChartTheme()).to.deep.equal({
      backgroundColor: "transparent",
      categoryAxis: axisTheme,
      darkMode: true,
      legend: { inactiveColor: "#57534e", textStyle: { color: "#e7e5e4" } },
      logAxis: axisTheme,
      textStyle: { color: "#e7e5e4" },
      timeAxis: axisTheme,
      tooltip: {
        backgroundColor: "#181514",
        borderColor: "#44403c",
        textStyle: { color: "#e7e5e4" },
      },
      valueAxis: axisTheme,
    });
  });

  it("initializes light charts with the ECharts defaults", () => {
    // Render a chart under the light color theme.
    localStorage.setItem(THEME_STORAGE_KEY, "light");
    document.body.innerHTML = `<div id="light-chart"></div>`;
    const stub = createEchartsThemeStub();
    globalThis.echarts = stub.echarts;
    initChart("light-chart", {});

    // Assert the chart uses one init argument and no registered theme.
    expect(stub.initCalls).to.have.length(1);
    expect(stub.initCalls[0]).to.deep.equal([document.getElementById("light-chart")]);
    expect(stub.registerThemeCalls).to.deep.equal([]);
  });

  it("initializes dark charts with the registered dark theme", () => {
    // Render a chart under the dark color theme.
    localStorage.setItem(THEME_STORAGE_KEY, "dark");
    setChartTokens(DARK_CHART_TOKENS);
    document.body.innerHTML = `<div id="dark-chart"></div>`;
    const stub = createEchartsThemeStub();
    globalThis.echarts = stub.echarts;
    initChart("dark-chart", {});

    // Assert the dark theme is registered from the tokens and used by the chart.
    expect(stub.registerThemeCalls).to.deep.equal([["ocg-dark", getChartTheme()]]);
    expect(stub.initCalls).to.deep.equal([[document.getElementById("dark-chart"), "ocg-dark"]]);
  });

  it("builds title and value axis configs", () => {
    // Verify builds title and value axis configs.
    document.documentElement.style.setProperty("--color-stone-100", "#f5f5f4");

    // Assert the computed value.
    expect(getChartTitleConfig("Members over time", { 950: "#0c0a09" })).to.deep.equal({
      text: "Members over time",
      left: "center",
      top: 12,
      textStyle: {
        fontFamily:
          '"Inter", "ui-sans-serif", "system-ui", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "sans-serif"',
        fontSize: 14,
        fontWeight: 500,
        color: "#0c0a09",
      },
    });

    // Verify builds title and value axis configs.
    expect(getValueAxisConfig()).to.deep.equal({
      type: "value",
      minInterval: 1,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { fontSize: 11 },
      splitLine: { lineStyle: { color: "#f5f5f4", type: "dashed" } },
    });
  });

  it("builds recent daily buckets in UTC from an injected time at midnight", () => {
    // Build three daily buckets ending at a UTC midnight reference time.
    const series = buildRecentBarSeries(
      [
        ["2024-12-31", 3],
        ["2025-01-01", 4],
      ],
      "day",
      3,
      { now: new Date(Date.UTC(2025, 0, 1, 0, 0, 0)) },
    );

    // Assert keys and labels use UTC regardless of the browser timezone.
    expect(series).to.deep.equal({
      categories: ["30 Dec", "31 Dec", "01 Jan"],
      values: [0, 3, 4],
    });
  });

  it("builds recent daily buckets across a daylight saving change", () => {
    // Build buckets ending on the European and Pacific daylight saving dates.
    const european = buildRecentBarSeries([["2025-03-30", 2]], "day", 3, {
      now: new Date(Date.UTC(2025, 2, 30, 1, 30, 0)),
    });
    const pacific = buildRecentBarSeries([["2025-04-06", 5]], "day", 2, {
      now: new Date(Date.UTC(2025, 3, 6, 13, 30, 0)),
    });

    // Assert every day appears once in UTC.
    expect(european).to.deep.equal({ categories: ["28 Mar", "29 Mar", "30 Mar"], values: [0, 0, 2] });
    expect(pacific).to.deep.equal({ categories: ["05 Apr", "06 Apr"], values: [0, 5] });
  });

  it("builds recent monthly buckets across a month rollover in UTC", () => {
    // Use a reference time that is already the next month in eastern timezones.
    const now = new Date(Date.UTC(2025, 2, 31, 23, 30, 0));

    // Assert monthly bar series and stacked series use UTC months.
    expect(buildRecentBarSeries([["2025-03", 7]], "month", 3, { now })).to.deep.equal({
      categories: ["Jan'25", "Feb'25", "Mar'25"],
      values: [0, 0, 7],
    });
    expect(
      buildStackedMonthlySeries(
        { Talks: [["2025-02", 1]] },
        { now, recentWindowMonths: 2, reservePeriodStart: true },
      ),
    ).to.deep.equal({
      months: ["2025-02", "2025-03"],
      series: [{ name: "Talks", data: [1, 0] }],
    });
  });

  it("formats day axis labels from day keys without timezone shifts", () => {
    // Verify day keys become short labels and other values pass through.
    expect(formatDayAxisLabel("2025-01-01")).to.equal("01 Jan");
    expect(formatDayAxisLabel("2025-12-31")).to.equal("31 Dec");
    expect(formatDayAxisLabel("2025-13-01")).to.equal("2025-13-01");
    expect(formatDayAxisLabel("Jan")).to.equal("Jan");
  });

  it("detects activity in counts and key/count pairs", () => {
    // Verify zero, empty and non-zero inputs.
    expect(hasActivity([])).to.equal(false);
    expect(hasActivity([0, 0])).to.equal(false);
    expect(hasActivity([["2025-01-01", 0]])).to.equal(false);
    expect(
      hasActivity([
        ["2025-01-01", 0],
        ["2025-01-02", "2"],
      ]),
    ).to.equal(true);
    expect(hasActivity([-1])).to.equal(true);
  });

  it("builds horizontal bar charts with a percentage base, count labels and inverse order", () => {
    // Build bars whose percentages use an explicit base.
    const data = [
      { name: "newsletter", value: 5 },
      { name: "social", value: 15 },
    ];
    const percentOption = createHorizontalBarChart("Views by source", data, palette, {
      description: "Share of all views",
      inverse: true,
      leftMargin: 90,
      percentBase: 100,
    });

    // Assert the shared title, inverse axis, margin and percentage labels.
    expect(percentOption.title.text).to.equal("Views by source");
    expect(percentOption.title.subtext).to.equal("Share of all views");
    expect(percentOption.yAxis.inverse).to.equal(true);
    expect(percentOption.yAxis.data).to.deep.equal(["newsletter", "social"]);
    expect(percentOption.grid.left).to.equal(90);
    expect(percentOption.series[0].label.formatter({ value: 5 })).to.equal("5.0%");
    expect(percentOption.tooltip.trigger).to.equal("item");
    expect(percentOption.tooltip.formatter({ name: "social", value: 15 })).to.equal("social: 15 (15.0%)");

    // Assert count labels and the data total default.
    const countOption = createHorizontalBarChart("Funnel", data, palette, { valueLabel: "count" });
    expect(countOption.series[0].label.formatter({ value: 15 })).to.equal("15");
    expect(countOption.yAxis.inverse).to.equal(false);
    expect(countOption.grid.left).to.equal(140);
    expect(countOption.tooltip.formatter({ name: "social", value: 15 })).to.equal("social: 15");
    expect(countOption.xAxis.axisLabel.show).to.equal(true);

    // Assert long category names are truncated next to the default margin.
    expect(countOption.yAxis.axisLabel).to.include({ fontSize: 12, overflow: "truncate", width: 120 });

    // Assert the value axis labels can be hidden when bars are labeled.
    const unlabeledAxisOption = createHorizontalBarChart("Views", data, palette, {
      showValueAxisLabels: false,
    });
    expect(unlabeledAxisOption.xAxis.axisLabel.show).to.equal(false);
  });

  it("escapes category names in horizontal bar tooltips", () => {
    // Build bars named with organizer-provided markup.
    const option = createHorizontalBarChart("Selections per option", [{ name: "x", value: 1 }], palette);

    // Assert the tooltip renders the name as text.
    expect(option.tooltip.formatter({ name: `<img src=x onerror="alert('x')">`, value: 1 })).to.equal(
      "&lt;img src=x onerror=&quot;alert(&#39;x&#39;)&quot;&gt;: 1 (100.0%)",
    );
  });

  it("builds pie charts with shared colors, explicit colors and an optional tail", () => {
    // Build a dense pie with the default grouped tail.
    const data = Array.from({ length: 8 }, (_, index) => ({ name: `value-${index}`, value: 8 - index }));
    const grouped = createPieChart("Views", "Views", data, palette);

    // Assert the tail is grouped and the shared palette applies.
    expect(grouped.series[0].data).to.have.length(7);
    expect(grouped.series[0].data.at(-1)).to.deep.equal({ name: "Other", value: 3 });
    expect(grouped.color[0]).to.equal(palette[950]);
    expect(grouped.tooltip.formatter).to.equal("{b}: {c} ({d}%)");

    // Assert explicit colors keep every slice.
    const colors = data.map((_, index) => `#00000${index}`);
    const explicit = createPieChart("Views", "Views", data, palette, { colors, groupTail: false });
    expect(explicit.series[0].data).to.have.length(8);
    expect(explicit.color).to.deep.equal(colors);
    expect(explicit.legend).to.include({ left: "55%", orient: "vertical", top: "30%" });
    expect(explicit.series[0].label.show).to.equal(true);

    // Assert a bottom legend centers the pie and slice labels can be hidden.
    const compact = createPieChart("Views", "Views", data, palette, {
      legendPosition: "bottom",
      showLabels: false,
    });
    expect(compact.legend).to.include({
      bottom: 0,
      itemGap: 8,
      left: "center",
      orient: "horizontal",
      type: "scroll",
    });
    expect(compact.legend.textStyle.fontSize).to.equal(11);
    expect(compact.legend.formatter("Platform engineering")).to.equal("Platform engin...");
    expect(compact.legend.formatter("Unattributed")).to.equal("Unattributed");
    expect(compact.series[0].center).to.deep.equal(["50%", "54%"]);
    expect(compact.series[0].label.show).to.equal(false);
    expect(compact.series[0].labelLine.show).to.equal(false);

    // Assert compact pies hide overlapping labels and show full legend names on hover.
    expect(compact.series[0].labelLayout).to.deep.equal({ hideOverlap: true });
    expect(compact.legend.tooltip.show).to.equal(true);
    expect(explicit.series[0].labelLayout).to.equal(undefined);
  });

  it("keeps stacked chart legends on one scrolling row", () => {
    // Build stacked monthly and area charts with only two series.
    const monthlyOption = createStackedMonthlyChart(
      "Groups per month",
      ["2025-01", "2025-02"],
      [
        { name: "Cloud", data: [1, 2] },
        { name: "Data", data: [3, 4] },
      ],
      palette,
    );
    const areaOption = createStackedAreaChart(
      "Groups over time",
      [
        {
          name: "Cloud",
          data: [
            [1, 1],
            [2, 2],
          ],
        },
        {
          name: "Data",
          data: [
            [1, 3],
            [2, 4],
          ],
        },
      ],
      palette,
    );

    // Assert both legends scroll instead of wrapping onto extra rows.
    expect(monthlyOption.legend.type).to.equal("scroll");
    expect(areaOption.baseOption.legend.type).to.equal("scroll");
  });

  it("places day markers on their UTC day with event timezone tooltips", () => {
    // Build markers on visible and hidden days.
    const markLine = getDayMarkersConfig(
      [
        { kind: "published", ts: Date.UTC(2025, 2, 1, 23, 30) / 1000 },
        { kind: "announcement", ts: Date.UTC(2025, 2, 1, 8, 0) / 1000 },
        { kind: "event-start", ts: Date.UTC(2025, 2, 9, 12, 0) / 1000 },
      ],
      {
        color: "#999999",
        days: ["2025-03-01", "2025-03-02"],
        labelForKind: (kind) => ({ announcement: "Announcement", published: "Published" })[kind] || kind,
        timeZone: "Asia/Tokyo",
      },
    );

    // Assert markers on the same UTC day are combined and hidden days skipped.
    expect(markLine.data).to.have.length(1);
    expect(markLine.data[0].xAxis).to.equal("2025-03-01");
    expect(markLine.data[0].details[0]).to.equal("Published: Mar 2, 2025, 8:30 AM GMT+9");
    expect(markLine.data[0].details[1]).to.equal("Announcement: Mar 1, 2025, 5:00 PM GMT+9");
    expect(markLine.tooltip.formatter({ data: markLine.data[0] })).to.include("<br/>");
    expect(markLine.lineStyle).to.deep.equal({ color: "#999999", type: "dashed", width: 1 });

    // Assert markers outside the days produce no config.
    expect(getDayMarkersConfig([{ kind: "published", ts: 0 }], { days: ["2025-03-01"] })).to.equal(null);
  });

  it("builds stacked daily bar charts with explicit colors and markers", () => {
    // Build stacked daily charts with one explicit color and a marker.
    const days = ["2025-03-01", "2025-03-02"];
    const seriesData = [
      { name: "newsletter", data: [1, 2], color: "#123456" },
      { name: "Untagged", data: [3, 4] },
    ];
    const markLine = { data: [{ xAxis: "2025-03-01" }] };
    const barOption = createStackedDailyBarChart("Views per day", days, seriesData, palette, { markLine });

    // Assert stacked bars keep explicit colors and attach markers once.
    expect(barOption.xAxis.type).to.equal("category");
    expect(barOption.xAxis.data).to.deep.equal(days);
    expect(barOption.xAxis.axisLabel.formatter("2025-03-01", 0)).to.equal("01 Mar");
    expect(barOption.series.map((series) => series.stack)).to.deep.equal(["total", "total"]);
    expect(barOption.series[0].itemStyle.color).to.equal("#123456");
    expect(barOption.series[1].itemStyle.color).to.equal(palette[400]);
    expect(barOption.series[0].markLine).to.equal(markLine);
    expect(barOption.series[1].markLine).to.equal(undefined);

    // Assert three series spread across the palette for contrast.
    const threeSeries = ["a", "b", "c"].map((name) => ({ name, data: [1, 2] }));
    const threeOption = createStackedDailyBarChart("Views per day", days, threeSeries, palette);
    expect(threeOption.series.map((series) => series.itemStyle.color)).to.deep.equal([
      palette[950],
      palette[600],
      palette[300],
    ]);
  });

  it("keeps single-day line points visible", () => {
    // Assert only single-day lines show their symbol.
    expect(getDailyLineSymbolConfig(1)).to.deep.equal({ showSymbol: true, symbol: "circle" });
    expect(getDailyLineSymbolConfig(2)).to.deep.equal({ showSymbol: false, symbol: "none" });
  });
});
