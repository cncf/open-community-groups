import {
  loadEChartsScript,
  getThemePalette,
  createAreaChart,
  createMonthlyBarChart,
  initChart,
  hasChartData,
  hasTimeSeriesData,
  showChartEmptyState,
  clearChartElement,
} from "/static/js/dashboard/common.js";
import "/static/js/common/svg-spinner.js";
import { debounce } from "/static/js/common/common.js";

/**
 * Add a loading spinner overlay to a chart container.
 * @param {HTMLElement} container - Chart wrapper element.
 */
const addSpinner = (container) => {
  if (!container || container.querySelector(".chart-spinner")) {
    return;
  }

  container.classList.add("relative");

  const spinner = document.createElement("div");
  spinner.innerHTML =
    '<svg-spinner size="size-10" class="chart-spinner absolute inset-0 flex items-center justify-center text-gray-500 bg-white/80 backdrop-blur-[1px] z-10"></svg-spinner>';
  container.appendChild(spinner);
};

/**
 * Remove any spinner overlay from a chart container.
 * @param {HTMLElement} container - Chart wrapper element.
 */
const removeSpinner = (container) => {
  container?.querySelector(".chart-spinner")?.remove();
};

/**
 * Create or dispose a chart depending on data availability.
 * @param {string} elementId - Target chart element id.
 * @param {Object} option - ECharts option to render.
 * @param {boolean} hasChartData - Whether the chart has data.
 * @returns {echarts.ECharts|null} Chart instance or null.
 */
const renderChart = (elementId, option, hasChartData) => {
  const chartElement = document.getElementById(elementId);
  const container = chartElement?.closest("[data-analytics-chart]");

  const seriesData = option?.series?.[0]?.data || [];
  const needsTrendLine = option?.xAxis?.type === "time" && option?.series?.[0]?.type === "line";
  const canRender = hasChartData && (!needsTrendLine || seriesData.length >= 2);

  if (!canRender) {
    if (container) {
      removeSpinner(container);
    }
    showChartEmptyState(elementId);
    return null;
  }

  const element = clearChartElement(elementId);
  if (!element) {
    return null;
  }

  if (container) {
    removeSpinner(container);
  }

  const chart = initChart(elementId, option);
  return chart;
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
      hasTimeSeriesData(runningData),
    ),
  );

  const monthlyData = stats.per_month || [];
  charts.push(
    renderChart(
      "members-monthly-chart",
      createMonthlyBarChart("New Members per Month", "Members", monthlyData, palette),
      hasChartData(monthlyData),
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
    renderChart(
      "events-running-chart",
      createAreaChart("Events over time", "Events", runningData, palette),
      hasTimeSeriesData(runningData),
    ),
  );

  const monthlyData = stats.per_month || [];
  charts.push(
    renderChart(
      "events-monthly-chart",
      createMonthlyBarChart("New Events per Month", "Events", monthlyData, palette),
      hasChartData(monthlyData),
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
      hasTimeSeriesData(runningData),
    ),
  );

  const monthlyData = stats.per_month || [];
  charts.push(
    renderChart(
      "attendees-monthly-chart",
      createMonthlyBarChart("New Attendees per Month", "Attendees", monthlyData, palette),
      hasChartData(monthlyData),
    ),
  );

  return charts.filter(Boolean);
};

/**
 * Show spinners on all analytics chart containers.
 */
export const showAnalyticsSpinners = () => {
  document.querySelectorAll("[data-analytics-chart]").forEach((container) => {
    addSpinner(container);
  });
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
