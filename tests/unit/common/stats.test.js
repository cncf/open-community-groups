import { expect } from "@open-wc/testing";

import {
  getCategoryLabelInterval,
  getTimeSplitNumber,
  registerChartResizeHandler,
} from "/static/js/common/stats.js";

const waitForDelay = (delay = 0) => new Promise((resolve) => setTimeout(resolve, delay));

describe("stats utilities", () => {
  it("computes category label intervals", () => {
    expect(getCategoryLabelInterval(0)).to.equal(0);
    expect(getCategoryLabelInterval(6)).to.equal(0);
    expect(getCategoryLabelInterval(24)).to.equal(1);
    expect(getCategoryLabelInterval(25)).to.equal(2);
  });

  it("computes time split numbers within the expected bounds", () => {
    expect(getTimeSplitNumber(0)).to.equal(4);
    expect(getTimeSplitNumber(6)).to.equal(3);
    expect(getTimeSplitNumber(24)).to.equal(4);
    expect(getTimeSplitNumber(60)).to.equal(6);
  });

  it("registers a debounced resize handler for chart instances", async () => {
    const firstChart = { resizeCalls: 0, resize() { this.resizeCalls += 1; } };
    const secondChart = { resizeCalls: 0, resize() { this.resizeCalls += 1; } };

    const resizeHandler = registerChartResizeHandler([firstChart, null, secondChart], 0);
    window.dispatchEvent(new Event("resize"));
    await waitForDelay();

    expect(firstChart.resizeCalls).to.equal(1);
    expect(secondChart.resizeCalls).to.equal(1);

    window.removeEventListener("resize", resizeHandler);
  });
});
