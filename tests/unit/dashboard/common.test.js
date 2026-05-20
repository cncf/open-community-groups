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

    // Exercise the flow to check it covers the current behavior.
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
    // Prepare element to check it renders and clears chart empty states.
    const element = document.createElement("div");
    element.id = "stats";
    element.className = "chart-empty-state";
    element.textContent = "Old text";
    document.body.append(element);

    // Prepare cleared element to check it renders and clears chart empty states.
    const clearedElement = clearChartElement("stats");

    // Confirm it renders and clears chart empty states.
    expect(clearedElement).to.equal(element);
    expect(element.classList.contains("chart-empty-state")).to.equal(false);
    expect(element.textContent).to.equal("");
    expect(disposedCharts).to.have.length(1);

    // Exercise the flow to check it renders and clears chart empty states.
    showChartEmptyState("stats", "No chart data yet");
    expect(element.classList.contains("chart-empty-state")).to.equal(true);
    expect(element.textContent).to.equal("No chart data yet");
  });

  it("evaluates chart data helpers", () => {
    // Confirm it evaluates chart data helpers.
    expect(hasChartData([])).to.equal(false);
    expect(hasChartData([1])).to.equal(true);

    // Confirm it evaluates chart data helpers.
    expect(hasTimeSeriesData([[1, 2]])).to.equal(false);
    expect(
      hasTimeSeriesData([
        [1, 2],
        [3, 4],
      ]),
    ).to.equal(true);

    // Confirm it evaluates chart data helpers.
    expect(hasStackedTimeSeriesData([])).to.equal(false);
    expect(hasStackedTimeSeriesData([{ data: [1] }])).to.equal(false);
    expect(hasStackedTimeSeriesData([{ data: [1, 2] }])).to.equal(true);
    expect(
      hasStackedTimeSeriesData([{ data: [1] }, { data: [1, 2, 3] }], 3),
    ).to.equal(true);
  });

  it("triggers htmx change events on forms", () => {
    // Prepare form to check it triggers HTMX change events on forms.
    const form = document.createElement("form");
    form.id = "filters-form";
    document.body.append(form);

    // Exercise the flow to check it triggers HTMX change events on forms.
    triggerChangeOnForm("filters-form");

    // Confirm it triggers HTMX change events on forms.
    expect(htmx.triggerCalls).to.deep.equal([[form, "change"]]);
  });

  it("reads palette values with fallback and normalizes time series", () => {
    // Exercise the flow to check it reads palette values with fallback and normalizes.
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

    // Prepare palette to check it reads palette values with fallback and normalizes time.
    const palette = getThemePalette();

    // Confirm it reads palette values with fallback and normalizes time series.
    expect(palette[700]).to.equal("#1d4ed8");
    expect(palette[500]).to.equal("#3b82f6");
    expect(palette[50]).to.equal("#1d4ed8");

    // Confirm it reads palette values with fallback and normalizes time series.
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
    // Exercise the flow to check it defers work until HTMX settles when the body.
    window.htmx = {};
    document.body.classList.add("htmx-swapping");

    // Prepare execution count to check it defers work until HTMX settles when the body.
    let executionCount = 0;

    // Prepare task promise to check it defers work until HTMX settles when the body.
    const taskPromise = deferUntilHtmxSettled(() => {
      executionCount += 1;
    });

    // Confirm it defers work until HTMX settles when the body is swapping.
    expect(executionCount).to.equal(0);

    // Dispatch the HTMX after swap event to check it defers work until HTMX settles.
    dispatchHtmxAfterSwap(document.body);
    await taskPromise;

    // Confirm it defers work until HTMX settles when the body is swapping.
    expect(executionCount).to.equal(1);
  });
});
