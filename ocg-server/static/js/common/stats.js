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
