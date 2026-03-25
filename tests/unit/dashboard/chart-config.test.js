import { expect } from "@open-wc/testing";

import {
  buildRecentBarSeries,
  getAxisTooltipConfig,
  getChartGridLineColor,
  getChartTitleConfig,
  getItemTooltipConfig,
  getValueAxisConfig,
  getVerticalBarCategoryAxisConfig,
  getVerticalBarSeriesStyle,
  toCategorySeries,
} from "/static/js/dashboard/common.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard chart config helpers", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("builds monthly bar series without reserving empty periods", () => {
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
    expect(
      toCategorySeries([
        ["Talks", "12"],
        ["Workshops", 4],
      ]),
    ).to.deep.equal([
      { name: "Talks", value: 12 },
      { name: "Workshops", value: 4 },
    ]);

    expect(getVerticalBarSeriesStyle(12)).to.deep.equal({
      barMaxWidth: 35,
      barMinWidth: 12,
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
    const categories = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct"];
    const axisConfig = getVerticalBarCategoryAxisConfig(categories);
    const formatter = axisConfig.axisLabel.formatter;

    expect(formatter("Jan", 0)).to.equal("Jan");
    expect(formatter("Feb", 1)).to.equal("");
    expect(formatter("Mar", 2)).to.equal("Mar");
    expect(formatter("Oct", 9)).to.equal("Oct");
  });

  it("reads shared chart colors and tooltip config from css variables", () => {
    document.documentElement.style.setProperty("--color-stone-100", "#f5f5f4");
    document.documentElement.style.setProperty("--color-stone-200", "#e7e5e4");
    document.documentElement.style.setProperty("--color-stone-700", "#44403c");
    document.documentElement.style.setProperty("--color-white", "#ffffff");

    expect(getChartGridLineColor()).to.equal("#f5f5f4");

    expect(getAxisTooltipConfig()).to.deep.equal({
      trigger: "axis",
      backgroundColor: "#ffffff",
      borderColor: "#e7e5e4",
      borderWidth: 1,
      textStyle: { color: "#44403c" },
    });

    expect(getItemTooltipConfig()).to.deep.equal({
      trigger: "item",
      backgroundColor: "#ffffff",
      borderColor: "#e7e5e4",
      borderWidth: 1,
      textStyle: { color: "#44403c" },
    });
  });

  it("builds title and value axis configs", () => {
    document.documentElement.style.setProperty("--color-stone-100", "#f5f5f4");

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

    expect(getValueAxisConfig()).to.deep.equal({
      type: "value",
      minInterval: 1,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { fontSize: 11 },
      splitLine: { lineStyle: { color: "#f5f5f4", type: "dashed" } },
    });
  });
});
