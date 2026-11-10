import { expect } from "@open-wc/testing";

import {
  disposeChartsWithin,
  getCategoryLabelInterval,
  getStatsMarker,
  getTimeSplitNumber,
  initializeChartsFromJsonMarker,
  renderChart,
} from "/static/js/common/charts/stats.js";
import { THEME_CHANGE_EVENT, THEME_STORAGE_KEY } from "/static/js/common/theme.js";
import { waitForFrameThenTask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

// Set up the test fixture.
const waitForDelay = (delay = 0) => new Promise((resolve) => setTimeout(resolve, delay));

/**
 * Stores a color theme and announces the change, as `theme.js` does.
 * @param {"light"|"dark"} theme - Color theme to apply.
 */
const changeTheme = (theme) => {
  localStorage.setItem(THEME_STORAGE_KEY, theme);
  document.dispatchEvent(new CustomEvent(THEME_CHANGE_EVENT, { detail: { theme } }));
};

/**
 * Builds a stats marker configuration recording every initializer run.
 * @param {string} selector - JSON marker selector.
 * @param {Array<Object>} runs - Initializer runs, with the marker and the context.
 * @param {Function} [wait] - Awaited inside each run before it records it.
 * @returns {Object} Initialization configuration.
 */
const buildRecordingConfig = (selector, runs, wait = async () => {}) => ({
  selector,
  readyKey: "statsReady",
  initialize: async (stats, context) => {
    await wait();
    runs.push({ marker: context.marker, retheme: context.retheme, stats });
  },
  parseErrorMessage: "Failed to parse stats:",
  initErrorMessage: "Failed to initialize stats:",
});

/** Resize observer stub recording observed elements and triggering callbacks on demand. */
class ResizeObserverStub {
  static instances = [];

  constructor(callback) {
    this.callback = callback;
    this.observed = new Set();
    ResizeObserverStub.instances.push(this);
  }

  observe(element) {
    this.observed.add(element);
  }

  unobserve(element) {
    this.observed.delete(element);
  }

  trigger(elements) {
    this.callback(elements.map((target) => ({ target })));
  }
}

/** Creates an ECharts stub recording created charts. */
const createEchartsStub = (charts) => ({
  getInstanceByDom() {
    return null;
  },
  init(element) {
    const chart = {
      disposeCalls: 0,
      element,
      resizeCalls: 0,
      dispose() {
        this.disposeCalls += 1;
      },
      isDisposed() {
        return this.disposeCalls > 0;
      },
      resize() {
        this.resizeCalls += 1;
      },
      setOption() {},
    };
    charts.push(chart);
    return chart;
  },
});

describe("stats utilities", () => {
  const originalEcharts = globalThis.echarts;
  const originalResizeObserver = globalThis.ResizeObserver;
  let charts;

  before(() => {
    globalThis.ResizeObserver = ResizeObserverStub;
  });

  after(() => {
    globalThis.ResizeObserver = originalResizeObserver;
  });

  beforeEach(() => {
    resetDom();
    charts = [];
    globalThis.echarts = createEchartsStub(charts);
  });

  afterEach(async () => {
    disposeChartsWithin(document.body);
    resetDom();
    localStorage.removeItem(THEME_STORAGE_KEY);
    await waitForFrameThenTask();
    if (originalEcharts) {
      globalThis.echarts = originalEcharts;
    } else {
      delete globalThis.echarts;
    }
  });

  it("computes category label intervals", () => {
    // Computed category label intervals.
    expect(getCategoryLabelInterval(0)).to.equal(0);
    expect(getCategoryLabelInterval(6)).to.equal(0);

    // Larger category counts increase the interval.
    expect(getCategoryLabelInterval(24)).to.equal(1);
    expect(getCategoryLabelInterval(25)).to.equal(2);
  });

  it("computes time split numbers within the expected bounds", () => {
    // Computed time split numbers within the expected bounds.
    expect(getTimeSplitNumber(0)).to.equal(4);
    expect(getTimeSplitNumber(6)).to.equal(3);

    // Larger month ranges keep the split count bounded.
    expect(getTimeSplitNumber(24)).to.equal(4);
    expect(getTimeSplitNumber(60)).to.equal(6);
  });

  it("resizes rendered charts when their containers change size, including later charts", async () => {
    // Render an empty chart first so no chart is registered yet.
    document.body.innerHTML = `<div id="first-chart"></div><div id="later-chart"></div>`;
    renderChart("first-chart", { series: [{ data: [] }] }, false);
    expect(charts).to.have.length(0);

    // Render a chart lazily after the initial empty set.
    const chart = renderChart("later-chart", { series: [{ data: [1] }] }, true);
    const observer = ResizeObserverStub.instances.at(-1);
    const element = document.getElementById("later-chart");
    expect(observer.observed.has(element)).to.equal(true);

    // Trigger container resizes and wait for the debounced resize.
    observer.trigger([element]);
    observer.trigger([element]);
    await waitForDelay(250);

    // Assert the chart resized once after the debounce.
    expect(chart.resizeCalls).to.equal(1);
  });

  it("disposes charts inside elements cleaned up by htmx and cancels pending resizes", async () => {
    // Render a chart inside a container that HTMX will clean up.
    document.body.innerHTML = `<section id="panel"><div id="panel-chart"></div></section>`;
    const chart = renderChart("panel-chart", { series: [{ data: [1] }] }, true);
    const observer = ResizeObserverStub.instances.at(-1);
    const element = document.getElementById("panel-chart");

    // Schedule a resize and clean up the container before it runs.
    observer.trigger([element]);
    document.getElementById("panel").dispatchEvent(new CustomEvent("htmx:beforeCleanupElement", { bubbles: true }));
    await waitForDelay(250);

    // Assert the chart was disposed, unobserved and never resized.
    expect(chart.disposeCalls).to.equal(1);
    expect(chart.resizeCalls).to.equal(0);
    expect(observer.observed.has(element)).to.equal(false);
  });

  it("unregisters the previous chart when an element is rendered again", () => {
    // Render the same chart container twice.
    document.body.innerHTML = `<div id="rerendered-chart"></div>`;
    const firstChart = renderChart("rerendered-chart", { series: [{ data: [1] }] }, true);
    const secondChart = renderChart("rerendered-chart", { series: [{ data: [2] }] }, true);

    // Assert the previous chart was disposed and the new one kept.
    expect(firstChart.disposeCalls).to.equal(1);
    expect(secondChart.disposeCalls).to.equal(0);

    // Assert switching to the empty state disposes the current chart.
    renderChart("rerendered-chart", { series: [{ data: [] }] }, false);
    expect(secondChart.disposeCalls).to.equal(1);
  });

  it("disposes charts whose containers were removed without an htmx cleanup", () => {
    // Render a chart and remove its container directly.
    document.body.innerHTML = `<div id="detached-chart"></div><div id="next-chart"></div>`;
    const detachedChart = renderChart("detached-chart", { series: [{ data: [1] }] }, true);
    const detachedElement = document.getElementById("detached-chart");
    detachedElement.remove();

    // Render another chart.
    const nextChart = renderChart("next-chart", { series: [{ data: [1] }] }, true);
    const observer = ResizeObserverStub.instances.at(-1);

    // Assert the detached chart was disposed and unobserved, keeping the new one.
    expect(detachedChart.disposeCalls).to.equal(1);
    expect(observer.observed.has(detachedElement)).to.equal(false);
    expect(nextChart.disposeCalls).to.equal(0);
    expect(observer.observed.has(document.getElementById("next-chart"))).to.equal(true);
  });

  it("finds stats markers from matching roots and descendants", () => {
    // Build the marker fixture.
    document.body.innerHTML = `
      <section>
        <script type="application/json" data-stats>{"total": 1}</script>
      </section>
    `;
    const marker = document.querySelector("[data-stats]");

    // Assert markers resolve from the document, descendants, and the marker itself.
    expect(getStatsMarker(document, "[data-stats]")).to.equal(marker);
    expect(getStatsMarker(document.querySelector("section"), "[data-stats]")).to.equal(marker);
    expect(getStatsMarker(marker, "[data-stats]")).to.equal(marker);
  });

  it("initializes charts from a JSON marker once", async () => {
    // Build the marker fixture.
    document.body.innerHTML = `
      <script type="application/json" data-stats>{"total": 1}</script>
    `;
    const initializedStats = [];
    const config = {
      selector: "[data-stats]",
      readyKey: "statsReady",
      initialize: async (stats) => initializedStats.push(stats),
      parseErrorMessage: "Failed to parse stats:",
      initErrorMessage: "Failed to initialize stats:",
    };

    // Initialize charts twice, the first time concurrently, to verify the guards.
    await Promise.all([initializeChartsFromJsonMarker(config), initializeChartsFromJsonMarker(config)]);
    await initializeChartsFromJsonMarker(config);

    // Assert the marker payload initializes charts once.
    expect(initializedStats).to.deep.equal([{ total: 1 }]);
    expect(document.querySelector("[data-stats]").dataset.statsReady).to.equal("true");
  });

  it("marks markers ready only after a successful initialization", async () => {
    // Build the marker fixture and an initializer failing once.
    document.body.innerHTML = `
      <script type="application/json" data-stats>{"total": 3}</script>
    `;
    const marker = document.querySelector("[data-stats]");
    let attempts = 0;
    const originalConsoleError = console.error;
    console.error = () => {};
    const config = {
      selector: "[data-stats]",
      readyKey: "statsReady",
      initialize: async () => {
        attempts += 1;
        if (attempts === 1) {
          throw new Error("boom");
        }
      },
      parseErrorMessage: "Failed to parse stats:",
      initErrorMessage: "Failed to initialize stats:",
    };

    try {
      // Fail the first initialization.
      await initializeChartsFromJsonMarker(config);
      expect(marker.dataset.statsReady).to.equal(undefined);

      // Retry and succeed.
      await initializeChartsFromJsonMarker(config);
    } finally {
      console.error = originalConsoleError;
    }

    // Assert the retry ran and marked the marker ready.
    expect(attempts).to.equal(2);
    expect(marker.dataset.statsReady).to.equal("true");
  });

  it("skips initialization when the marker is removed while charts load", async () => {
    // Build the marker fixture.
    document.body.innerHTML = `
      <section id="stats-root">
        <script type="application/json" data-stats>{"total": 4}</script>
      </section>
    `;
    const initializedStats = [];

    // Start initialization and remove the root before it resumes.
    const pending = initializeChartsFromJsonMarker({
      root: document.getElementById("stats-root"),
      selector: "[data-stats]",
      readyKey: "statsReady",
      initialize: async (stats) => initializedStats.push(stats),
      parseErrorMessage: "Failed to parse stats:",
      initErrorMessage: "Failed to initialize stats:",
    });
    document.getElementById("stats-root").remove();
    await pending;

    // Assert detached markers are not initialized.
    expect(initializedStats).to.deep.equal([]);
  });

  it("reinitializes charts from a restored JSON marker when forced", async () => {
    // Build the restored marker fixture with the previous ready flag.
    document.body.innerHTML = `
      <script type="application/json" data-stats data-stats-ready="true">{"total": 2}</script>
    `;
    const initializedStats = [];

    // Force initialization for markers restored from cached history snapshots.
    await initializeChartsFromJsonMarker({
      selector: "[data-stats]",
      readyKey: "statsReady",
      initialize: async (stats) => initializedStats.push(stats),
      parseErrorMessage: "Failed to parse stats:",
      initErrorMessage: "Failed to initialize stats:",
      force: true,
    });

    // Assert restored markers can hydrate charts again.
    expect(initializedStats).to.deep.equal([{ total: 2 }]);
    expect(document.querySelector("[data-stats]").dataset.statsReady).to.equal("true");
  });

  it("re-renders only connected markers rendered under the other color theme", async () => {
    // Render one marker under the light theme and another under the dark theme.
    document.body.innerHTML = `
      <section id="light-stats"><script type="application/json" data-light-stats>{"total": 1}</script></section>
      <section id="dark-stats"><script type="application/json" data-dark-stats>{"total": 2}</script></section>
    `;
    const runs = [];
    localStorage.setItem(THEME_STORAGE_KEY, "light");
    await initializeChartsFromJsonMarker(buildRecordingConfig("[data-light-stats]", runs));
    localStorage.setItem(THEME_STORAGE_KEY, "dark");
    await initializeChartsFromJsonMarker(buildRecordingConfig("[data-dark-stats]", runs));
    expect(runs.map(({ retheme }) => retheme)).to.deep.equal([false, false]);

    // Announce the dark theme.
    changeTheme("dark");
    await waitForFrameThenTask();

    // Assert only the light marker re-rendered, past its ready flag and as a re-theme.
    const lightMarker = document.querySelector("[data-light-stats]");
    expect(runs).to.have.length(3);
    expect(runs[2]).to.deep.equal({ marker: lightMarker, retheme: true, stats: { total: 1 } });

    // Assert a later change back to light re-renders both markers once.
    changeTheme("light");
    await waitForFrameThenTask();
    expect(runs.slice(3).map(({ marker }) => marker)).to.have.members([
      lightMarker,
      document.querySelector("[data-dark-stats]"),
    ]);
  });

  it("coalesces color theme changes in one frame into one re-render", async () => {
    // Render a marker under the light theme.
    document.body.innerHTML = `<script type="application/json" data-stats>{"total": 1}</script>`;
    const runs = [];
    localStorage.setItem(THEME_STORAGE_KEY, "light");
    await initializeChartsFromJsonMarker(buildRecordingConfig("[data-stats]", runs));

    // Announce two changes before the next frame, counting the frames requested.
    const originalRequestAnimationFrame = window.requestAnimationFrame;
    let frameRequests = 0;
    window.requestAnimationFrame = (callback) => {
      frameRequests += 1;
      return originalRequestAnimationFrame.call(window, callback);
    };
    try {
      changeTheme("dark");
      changeTheme("dark");
    } finally {
      window.requestAnimationFrame = originalRequestAnimationFrame;
    }
    await waitForFrameThenTask();
    await waitForFrameThenTask();

    // Assert one frame re-rendered the marker once.
    expect(frameRequests).to.equal(1);
    expect(runs.map(({ retheme }) => retheme)).to.deep.equal([false, true]);
  });

  it("applies a color theme change that lands during a run once the run ends", async () => {
    // Start a run under the light theme that waits for the test to finish it.
    document.body.innerHTML = `<script type="application/json" data-stats>{"total": 1}</script>`;
    const runs = [];
    let finishRun = () => {};
    let holdRuns = true;
    const wait = () => (holdRuns ? new Promise((resolve) => (finishRun = resolve)) : Promise.resolve());
    localStorage.setItem(THEME_STORAGE_KEY, "light");
    const pending = initializeChartsFromJsonMarker(buildRecordingConfig("[data-stats]", runs, wait));
    await waitForDelay();

    // Announce the dark theme while the run is in flight.
    changeTheme("dark");
    await waitForFrameThenTask();
    expect(runs).to.have.length(0);

    // Finish the run and let the next frame re-render it.
    holdRuns = false;
    finishRun();
    await pending;
    await waitForFrameThenTask();
    await waitForFrameThenTask();

    // Assert the change was applied once after the run ended.
    expect(runs.map(({ retheme }) => retheme)).to.deep.equal([false, true]);
  });

  it("drops markers cleaned up by htmx or detached from the document", async () => {
    // Render two markers under the light theme.
    document.body.innerHTML = `
      <section id="cleaned-stats"><script type="application/json" data-cleaned-stats>{"total": 1}</script></section>
      <section id="detached-stats"><script type="application/json" data-detached-stats>{"total": 2}</script></section>
    `;
    const runs = [];
    localStorage.setItem(THEME_STORAGE_KEY, "light");
    await initializeChartsFromJsonMarker(buildRecordingConfig("[data-cleaned-stats]", runs));
    await initializeChartsFromJsonMarker(buildRecordingConfig("[data-detached-stats]", runs));

    // Clean up the first section through htmx and detach the second one.
    const cleanedSection = document.getElementById("cleaned-stats");
    cleanedSection.dispatchEvent(new CustomEvent("htmx:beforeCleanupElement", { bubbles: true }));
    const detachedSection = document.getElementById("detached-stats");
    detachedSection.remove();
    changeTheme("dark");
    await waitForFrameThenTask();

    // Reattach the detached section and announce another change.
    document.body.append(detachedSection);
    changeTheme("dark");
    await waitForFrameThenTask();

    // Assert neither marker re-rendered.
    expect(runs.map(({ retheme }) => retheme)).to.deep.equal([false, false]);
  });
});
