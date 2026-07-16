import { createDailyBarChart, createMonthlyBarChart, hasChartData } from "/static/js/common/charts/charts.js";
import { renderChart } from "/static/js/common/charts/stats.js";

/**
 * Build a page-view chart from a local chart spec.
 * @param {Object} config - Page-view chart configuration.
 * @param {Object} config.pageViews - Page views stats payload.
 * @param {Object} config.palette - Theme palette.
 * @param {string} config.elementId - Chart container ID.
 * @param {string} config.title - Chart title.
 * @param {string} config.description - Chart description.
 * @param {Array<string>} config.path - Payload path for chart data.
 * @param {"monthly"|"daily"} config.kind - Chart kind.
 * @returns {echarts.ECharts|null} Initialized chart.
 */
const buildPageViewChart = ({ pageViews, palette, elementId, title, description, path, kind }) => {
  const data = path.reduce((value, key) => value?.[key], pageViews) || [];
  const createOptions =
    kind === "monthly"
      ? () =>
          createMonthlyBarChart(title, "Page views", data, palette, {
            description,
            useTimeAxis: true,
            reservePeriodStart: true,
          })
      : () => createDailyBarChart(title, "Page views", data, palette, { description });

  return renderChart(elementId, createOptions(), hasChartData(data));
};

/**
 * Build page-view charts from chart specs.
 * @param {Object} pageViews - Page views stats payload.
 * @param {Object} palette - Theme palette.
 * @param {Array<Object>} chartSpecs - Page-view chart specs.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
export const initializePageViewCharts = (pageViews = {}, palette, chartSpecs = []) =>
  chartSpecs.map((config) => buildPageViewChart({ ...config, pageViews, palette })).filter(Boolean);
