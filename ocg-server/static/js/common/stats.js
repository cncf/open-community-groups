import { debounce } from "/static/js/common/common.js";
import { clearChartElement, initChart, showChartEmptyState } from "/static/js/dashboard/common.js";

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
    showChartEmptyState(elementId);
    return null;
  }

  const element = clearChartElement(elementId);
  if (!element) {
    return null;
  }

  return initChart(elementId, option);
};

/**
 * Register a debounced resize handler for chart instances.
 * @param {Iterable<echarts.ECharts>|Function} chartsSource - Chart list or getter.
 * @param {number} delay - Debounce delay in milliseconds.
 * @returns {Function} Debounced resize handler.
 */
export const registerChartResizeHandler = (chartsSource, delay = 200) => {
  const getCharts = typeof chartsSource === "function" ? chartsSource : () => Array.from(chartsSource || []);
  const resizeCharts = debounce(() => {
    const charts = (getCharts() || []).filter(Boolean);
    charts.forEach((chart) => chart.resize());
  }, delay);

  window.addEventListener("resize", resizeCharts);
  return resizeCharts;
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
