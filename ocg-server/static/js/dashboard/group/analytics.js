import {
  loadEChartsScript,
  getThemePalette,
  createAreaChart,
  createMonthlyBarChart,
  initChart,
} from "/static/js/dashboard/common.js";
import { debounce } from "/static/js/common/common.js";

/**
 * Initialize a chart if its element exists.
 * @param {string} elementId - Target chart element id.
 * @param {Object} option - ECharts option to render.
 * @returns {echarts.ECharts|null} Chart instance or null.
 */
const renderChart = (elementId, option) => {
  const chartElement = document.getElementById(elementId);
  if (!chartElement) {
    return null;
  }

  return initChart(elementId, option);
};

/**
 * Build charts for members metrics.
 * @param {Object} stats - Members stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initMembersCharts = (stats = {}, palette) => {
  const charts = [];

  const runningData = stats.running_total || [];
  charts.push(
    renderChart(
      "members-running-chart",
      createAreaChart("Members over time", "Members", runningData, palette),
    ),
  );

  const monthlyData = stats.per_month || [];
  charts.push(
    renderChart(
      "members-monthly-chart",
      createMonthlyBarChart("New Members per Month", "Members", monthlyData, palette),
    ),
  );

  return charts.filter(Boolean);
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
  charts.push(
    renderChart("events-running-chart", createAreaChart("Events over time", "Events", runningData, palette)),
  );

  const monthlyData = stats.per_month || [];
  charts.push(
    renderChart(
      "events-monthly-chart",
      createMonthlyBarChart("New Events per Month", "Events", monthlyData, palette),
    ),
  );

  return charts.filter(Boolean);
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
  charts.push(
    renderChart(
      "attendees-running-chart",
      createAreaChart("Attendees over time", "Attendees", runningData, palette),
    ),
  );

  const monthlyData = stats.per_month || [];
  charts.push(
    renderChart(
      "attendees-monthly-chart",
      createMonthlyBarChart("New Attendees per Month", "Attendees", monthlyData, palette),
    ),
  );

  return charts.filter(Boolean);
};

/**
 * Initialize all analytics charts for the group dashboard.
 * @param {Object} stats - Group analytics payload from the server.
 */
export const initAnalyticsCharts = async (stats) => {
  if (!stats) {
    return;
  }

  await loadEChartsScript();
  const palette = getThemePalette();

  const charts = [
    ...initMembersCharts(stats.members, palette),
    ...initEventsCharts(stats.events, palette),
    ...initAttendeesCharts(stats.attendees, palette),
  ];

  const hydratedCharts = charts.filter(Boolean);

  const resizeCharts = debounce(() => {
    hydratedCharts.forEach((chart) => chart.resize());
  }, 200);

  window.addEventListener("resize", resizeCharts);
};
