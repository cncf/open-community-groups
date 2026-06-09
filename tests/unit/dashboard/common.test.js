import { expect } from "@open-wc/testing";

import {
  clearChartElement,
  getThemePalette,
  hasChartData,
  hasStackedTimeSeriesData,
  hasTimeSeriesData,
  showChartEmptyState,
  toTimeSeries,
} from "/static/js/common/charts/charts.js";
import {
  deferUntilHtmxSettled,
} from "/static/js/dashboard/common.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";

describe("dashboard common utilities", () => {
  const originalEcharts = globalThis.echarts;

  let disposedCharts;

  beforeEach(() => {
    disposedCharts = [];
    resetDom();

    // Run the behavior under test.
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
    globalThis.echarts = originalEcharts;
  });

  it("renders and clears chart empty states", () => {
    // Prepare element for rendering and clears chart empty states.
    const element = document.createElement("div");
    element.id = "stats";
    element.className = "chart-empty-state";
    element.textContent = "Old text";
    document.body.append(element);

    // Prepare cleared element for rendering and clears chart empty states.
    const clearedElement = clearChartElement("stats");

    // Assert the cleared element.
    expect(clearedElement).to.equal(element);
    expect(element.classList.contains("chart-empty-state")).to.equal(false);
    expect(element.textContent).to.equal("");
    expect(disposedCharts).to.have.length(1);

    // Call show chart empty state.
    showChartEmptyState("stats", "No chart data yet");
    expect(element.classList.contains("chart-empty-state")).to.equal(true);
    expect(element.textContent).to.equal("No chart data yet");
  });

  it("evaluates chart data helpers", () => {
    // Assert the has chart data.
    expect(hasChartData([])).to.equal(false);
    expect(hasChartData([1])).to.equal(true);

    // Assert the updated has time series data.
    expect(hasTimeSeriesData([[1, 2]])).to.equal(false);
    expect(
      hasTimeSeriesData([
        [1, 2],
        [3, 4],
      ]),
    ).to.equal(true);

    // Verify evaluates chart data helpers.
    expect(hasStackedTimeSeriesData([])).to.equal(false);
    expect(hasStackedTimeSeriesData([{ data: [1] }])).to.equal(false);
    expect(hasStackedTimeSeriesData([{ data: [1, 2] }])).to.equal(true);
    expect(
      hasStackedTimeSeriesData([{ data: [1] }, { data: [1, 2, 3] }], 3),
    ).to.equal(true);
  });

  it("reads palette values with fallback and normalizes time series", () => {
    // Verify reads palette values with fallback and normalizes.
    document.documentElement.style.setProperty(
      "--color-primary-500",
      "#3b82f6",
    );
    document.documentElement.style.setProperty(
      "--color-primary-700",
      "#1d4ed8",
    );
    document.documentElement.style.setProperty(
      "--color-primary-900",
      "#1e3a8a",
    );

    // Prepare palette for reading palette values with fallback and normalizes time.
    const palette = getThemePalette();

    // Assert the palette.
    expect(palette[700]).to.equal("#1d4ed8");
    expect(palette[500]).to.equal("#3b82f6");
    expect(palette[50]).to.equal("#1d4ed8");

    // Assert the updated value.
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
    // Assert that work waits while the body is swapping.
    window.htmx = {};
    document.body.classList.add("htmx-swapping");

    // Track how often the deferred task runs.
    let executionCount = 0;

    // Start the deferred task while HTMX is still settling.
    const taskPromise = deferUntilHtmxSettled(() => {
      executionCount += 1;
    });

    // Assert the execution count.
    expect(executionCount).to.equal(0);

    // Dispatch the HTMX after-swap event.
    dispatchHtmxAfterSwap(document.body);
    await taskPromise;

    // Assert the updated execution count.
    expect(executionCount).to.equal(1);
  });
});
