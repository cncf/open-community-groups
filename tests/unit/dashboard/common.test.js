import { expect } from "@open-wc/testing";

import {
  clearChartElement,
  deferUntilHtmxSettled,
  getThemePalette,
  hasChartData,
  hasStackedTimeSeriesData,
  hasTimeSeriesData,
  showChartEmptyState,
  toTimeSeries,
  triggerChangeOnForm,
} from "/static/js/dashboard/common.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";
import { dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";

describe("dashboard common utilities", () => {
  const originalEcharts = globalThis.echarts;

  let htmx;
  let disposedCharts;

  beforeEach(() => {
    disposedCharts = [];
    resetDom();
    htmx = mockHtmx();

    globalThis.echarts = {
      getInstanceByDom: () => ({
        dispose: () => {
          disposedCharts.push(true);
        },
      }),
    };
  });

  afterEach(() => {
    resetDom();
    htmx.restore();
    globalThis.echarts = originalEcharts;
  });

  it("renders and clears chart empty states", () => {
    const element = document.createElement("div");
    element.id = "stats";
    element.className = "chart-empty-state";
    element.textContent = "Old text";
    document.body.append(element);

    const clearedElement = clearChartElement("stats");

    expect(clearedElement).to.equal(element);
    expect(element.classList.contains("chart-empty-state")).to.equal(false);
    expect(element.textContent).to.equal("");
    expect(disposedCharts).to.have.length(1);

    showChartEmptyState("stats", "No chart data yet");
    expect(element.classList.contains("chart-empty-state")).to.equal(true);
    expect(element.textContent).to.equal("No chart data yet");
  });

  it("evaluates chart data helpers", () => {
    expect(hasChartData([])).to.equal(false);
    expect(hasChartData([1])).to.equal(true);

    expect(hasTimeSeriesData([[1, 2]])).to.equal(false);
    expect(hasTimeSeriesData([[1, 2], [3, 4]])).to.equal(true);

    expect(hasStackedTimeSeriesData([])).to.equal(false);
    expect(hasStackedTimeSeriesData([{ data: [1] }])).to.equal(false);
    expect(hasStackedTimeSeriesData([{ data: [1, 2] }])).to.equal(true);
    expect(hasStackedTimeSeriesData([{ data: [1] }, { data: [1, 2, 3] }], 3)).to.equal(true);
  });

  it("triggers htmx change events on forms", () => {
    const form = document.createElement("form");
    form.id = "filters-form";
    document.body.append(form);

    triggerChangeOnForm("filters-form");

    expect(htmx.triggerCalls).to.deep.equal([[form, "change"]]);
  });

  it("reads palette values with fallback and normalizes time series", () => {
    document.documentElement.style.setProperty("--color-primary-500", "#3b82f6");
    document.documentElement.style.setProperty("--color-primary-700", "#1d4ed8");
    document.documentElement.style.setProperty("--color-primary-900", "#1e3a8a");

    const palette = getThemePalette();

    expect(palette[700]).to.equal("#1d4ed8");
    expect(palette[500]).to.equal("#3b82f6");
    expect(palette[50]).to.equal("#1d4ed8");

    expect(
      toTimeSeries([
        ["1735689600", "2"],
        [1735776000, 5],
      ]),
    ).to.deep.equal([
      [1735689600, 2],
      [1735776000, 5],
    ]);
  });

  it("defers work until htmx settles when the body is swapping", async () => {
    window.htmx = {};
    document.body.classList.add("htmx-swapping");

    let executionCount = 0;

    const taskPromise = deferUntilHtmxSettled(() => {
      executionCount += 1;
    });

    expect(executionCount).to.equal(0);

    dispatchHtmxAfterSwap(document.body);
    await taskPromise;

    expect(executionCount).to.equal(1);
  });
});
