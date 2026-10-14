import "/static/js/common/svg-spinner.js";
import {
  clearChartElement,
  initChart,
  loadEChartsScript,
  showChartEmptyState,
} from "/static/js/common/charts/charts.js";
import { getElementById, isDatasetReady, markDatasetReady } from "/static/js/common/dom.js";
import { parseJsonText } from "/static/js/common/utils.js";

/** Delay applied before resizing a chart after its container changes size. */
const CHART_RESIZE_DELAY = 200;

/** Rendered charts keyed by their container element. */
const chartRegistry = new Map();

/** JSON markers whose charts are being initialized. */
const markersInFlight = new WeakSet();

/** Shared observer resizing registered charts when their containers change size. */
let chartResizeObserver = null;

/**
 * Render a chart or show an empty state based on data availability.
 * @param {string} elementId - Target chart element id.
 * @param {Object} option - ECharts option object.
 * @param {boolean} hasData - Whether the chart has data to render.
 * @param {Object} options - Render options.
 * @param {number} options.minTimeSeriesPoints - Minimum points for time-series charts.
 * @returns {echarts.ECharts|null} Chart instance or null.
 */
export const renderChart = (elementId, option, hasData, options = {}) => {
  const { minTimeSeriesPoints = 2 } = options;
  const seriesData = option?.series?.[0]?.data || [];
  const needsTrendLine = option?.xAxis?.type === "time" && option?.series?.[0]?.type === "line";
  const canRender = hasData && (!needsTrendLine || seriesData.length >= minTimeSeriesPoints);

  if (!canRender) {
    unregisterChart(getElementById(document, elementId));
    showChartEmptyState(elementId);
    return null;
  }

  const element = clearChartElement(elementId);
  if (!element) {
    return null;
  }

  const chart = initChart(elementId, option);
  if (chart) {
    registerChart(element, chart);
  }

  return chart;
};

/**
 * Adds a rendered chart to the collection when the container has chart data.
 * @param {Array<echarts.ECharts>} charts - Chart collection.
 * @param {string} elementId - Chart container ID.
 * @param {Object} chartOptions - ECharts options.
 * @param {boolean} hasData - Whether chart data is available.
 * @returns {void}
 */
export const addRenderedChart = (charts, elementId, chartOptions, hasData) => {
  const chart = renderChart(elementId, chartOptions, hasData);
  if (chart) {
    charts.push(chart);
  }
};

/**
 * Disposes the registered charts rendered inside an element.
 * @param {Element} root - Element being removed or cleaned up.
 * @returns {void}
 */
export const disposeChartsWithin = (root) => {
  if (!(root instanceof Element) || chartRegistry.size === 0) {
    return;
  }

  Array.from(chartRegistry.keys())
    .filter((element) => root === element || root.contains(element))
    .forEach((element) => unregisterChart(element));
};

/**
 * Compute a reasonable label interval for category axes.
 * @param {number} count - Total number of labels.
 * @param {number} target - Target labels to show.
 * @returns {number} ECharts interval value.
 */
export const getCategoryLabelInterval = (count, target = 12) => {
  if (!count) {
    return 0;
  }

  const step = Math.ceil(count / target);
  return Math.max(step - 1, 0);
};

/**
 * Finds a stats JSON marker in a root or matching root element.
 * @param {Document|Element} root - Root element to search from.
 * @param {string} selector - JSON marker selector.
 * @returns {Element|null} Matching marker.
 */
export const getStatsMarker = (root, selector) => {
  if (root instanceof Element && root.matches(selector)) {
    return root;
  }

  return root.querySelector?.(selector) || null;
};

/**
 * Compute a reasonable split count for time axes.
 * @param {number} count - Total number of points.
 * @returns {number} ECharts splitNumber value.
 */
export const getTimeSplitNumber = (count) => {
  if (!count) {
    return 4;
  }

  return Math.min(6, Math.max(3, Math.round(count / 6)));
};

/**
 * Initializes charts from an inert JSON marker once.
 *
 * The marker is marked ready only after the initializer succeeds, so a failed
 * initialization can be retried on a later load. Concurrent calls for the same
 * marker are ignored, and initialization stops when the marker is removed
 * while ECharts loads.
 * @param {Object} config - Initialization configuration.
 * @param {Document|Element} config.root - Root element to search from.
 * @param {string} config.selector - JSON marker selector.
 * @param {string} config.readyKey - Dataset key used to guard initialization.
 * @param {Function} config.initialize - Chart initializer.
 * @param {string} config.parseErrorMessage - Payload parse error message.
 * @param {string} config.initErrorMessage - Chart initialization error message.
 * @param {boolean} config.force - Whether to ignore an existing ready marker.
 * @returns {Promise<void>} Promise resolved when initialization finishes.
 */
export const initializeChartsFromJsonMarker = async ({
  root = document,
  selector,
  readyKey,
  initialize,
  parseErrorMessage,
  initErrorMessage,
  force = false,
}) => {
  const marker = getStatsMarker(root, selector);
  if (!marker || markersInFlight.has(marker) || (!force && isDatasetReady(marker, readyKey))) {
    return;
  }

  const stats = parseJsonText(marker.textContent || "{}", null, (error) => {
    console.error(parseErrorMessage, error);
  });
  if (!stats) {
    return;
  }

  markersInFlight.add(marker);
  try {
    await loadEChartsScript();
    if (!marker.isConnected) {
      return;
    }

    await initialize(stats, { marker });
    markDatasetReady(marker, readyKey);
  } catch (error) {
    console.error(initErrorMessage, error);
  } finally {
    markersInFlight.delete(marker);
  }
};

/**
 * Returns the shared resize observer, creating it on first use.
 * @returns {ResizeObserver|null} Observer, or null when unsupported.
 */
const getChartResizeObserver = () => {
  if (!chartResizeObserver && typeof ResizeObserver !== "undefined") {
    chartResizeObserver = new ResizeObserver((entries) => {
      entries.forEach((entry) => chartRegistry.get(entry.target)?.scheduleResize());
    });
  }

  return chartResizeObserver;
};

/**
 * Registers a rendered chart so it follows its container size, replacing any
 * chart previously registered for the same container.
 * @param {Element} element - Chart container.
 * @param {echarts.ECharts} chart - Chart instance.
 * @returns {void}
 */
const registerChart = (element, chart) => {
  unregisterChart(element, { keepChart: chart });

  let timeoutId = null;
  chartRegistry.set(element, {
    cancelResize: () => clearTimeout(timeoutId),
    chart,
    scheduleResize: () => {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(() => chart.resize(), CHART_RESIZE_DELAY);
    },
  });
  getChartResizeObserver()?.observe(element);
};

/**
 * Stops tracking a chart container, cancelling pending resizes and disposing
 * its chart.
 * @param {Element|null} element - Chart container.
 * @param {Object} options - Unregister options.
 * @param {echarts.ECharts} options.keepChart - Chart instance that must stay alive.
 * @returns {void}
 */
const unregisterChart = (element, { keepChart = null } = {}) => {
  const entry = element ? chartRegistry.get(element) : null;
  if (!entry) {
    return;
  }

  entry.cancelResize();
  chartRegistry.delete(element);
  chartResizeObserver?.unobserve(element);
  if (entry.chart !== keepChart && !entry.chart.isDisposed?.()) {
    entry.chart.dispose?.();
  }
};

// Dispose charts inside content HTMX removes or replaces.
document.addEventListener("htmx:beforeCleanupElement", (event) => {
  disposeChartsWithin(event.target);
});
