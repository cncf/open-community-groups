import {
  loadEChartsScript,
  getThemePalette,
  createAreaChart,
  createMonthlyBarChart,
  deferUntilHtmxSettled,
  hasChartData,
  hasTimeSeriesData,
} from "/static/js/dashboard/common.js";
import { registerChartResizeHandler, renderChart } from "/static/js/common/stats.js";

/**
 * Build charts for members metrics.
 * @param {Object} stats - Members stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initMembersCharts = (stats = {}, palette) => {
  const charts = [];

  const runningData = stats.running_total || [];
  const runningChart = renderChart(
    "members-running-chart",
    createAreaChart("Members over time", "Members", runningData, palette),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyData = stats.per_month || [];
  const monthlyChart = renderChart(
    "members-monthly-chart",
    createMonthlyBarChart("New Members per Month", "Members", monthlyData, palette),
    hasChartData(monthlyData),
  );
  if (monthlyChart) charts.push(monthlyChart);

  return charts;
};

/**
 * Build charts for events metrics.
 * @param {Object} stats - Events stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initEventsCharts = (stats = {}, palette) => {
  const charts = [];

  const runningData = stats.running_total || [];
  const runningChart = renderChart(
    "events-running-chart",
    createAreaChart("Events over time", "Events", runningData, palette),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyData = stats.per_month || [];
  const monthlyChart = renderChart(
    "events-monthly-chart",
    createMonthlyBarChart("New Events per Month", "Events", monthlyData, palette),
    hasChartData(monthlyData),
  );
  if (monthlyChart) charts.push(monthlyChart);

  return charts;
};

/**
 * Build charts for attendees metrics.
 * @param {Object} stats - Attendees stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initAttendeesCharts = (stats = {}, palette) => {
  const charts = [];

  const runningData = stats.running_total || [];
  const runningChart = renderChart(
    "attendees-running-chart",
    createAreaChart("Attendees over time", "Attendees", runningData, palette),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyData = stats.per_month || [];
  const monthlyChart = renderChart(
    "attendees-monthly-chart",
    createMonthlyBarChart("New Attendees per Month", "Attendees", monthlyData, palette),
    hasChartData(monthlyData),
  );
  if (monthlyChart) charts.push(monthlyChart);

  return charts;
};

/**
 * Initialize all analytics charts for the group dashboard.
 * @param {Object} stats - Group analytics payload from the server.
 */
export const initAnalyticsCharts = async (stats) => {
  if (!stats) {
    return;
  }

  return deferUntilHtmxSettled(async () => {
    await loadEChartsScript();
    const palette = getThemePalette();

    const charts = [
      ...initMembersCharts(stats.members, palette),
      ...initEventsCharts(stats.events, palette),
      ...initAttendeesCharts(stats.attendees, palette),
    ];

    const hydratedCharts = charts.filter(Boolean);

    registerChartResizeHandler(hydratedCharts);
  });
};
