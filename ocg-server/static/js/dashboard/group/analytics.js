import {
  loadEChartsScript,
  getThemePalette,
  createAreaChart,
  createMonthlyBarChart,
  initChart,
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
 * Check whether a dataset contains points for rendering.
 * @param {Array} data - Chart data points.
 * @returns {boolean} True when the chart has data.
 */
const hasData = (data) => {
  return Array.isArray(data) && data.length > 0;
};

/**
 * Render a friendly empty state when no data is available.
 * @param {string} elementId - Target chart element id.
 */
const showEmptyState = (elementId) => {
  const chartElement = document.getElementById(elementId);
  if (!chartElement) {
    return;
  }

  const container = chartElement.closest("[data-analytics-chart]");
  if (container) {
    removeSpinner(container);
  }

  if (typeof echarts !== "undefined") {
    const existingChart = echarts.getInstanceByDom(chartElement);
    if (existingChart) {
      existingChart.dispose();
    }
  }

  chartElement.classList.add(
    "flex",
    "items-center",
    "justify-center",
    "bg-gray-100",
    "rounded-lg",
    "text-stone-400",
    "text-md",
    "p-4",
    "bg-stone-50/80",
  );
  chartElement.textContent = "No data available yet";
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

  if (!hasChartData) {
    showEmptyState(elementId);
    return null;
  }

  if (!chartElement) {
    return null;
  }

  if (container) {
    removeSpinner(container);
  }

  if (typeof echarts !== "undefined") {
    const existingChart = echarts.getInstanceByDom(chartElement);
    if (existingChart) {
      existingChart.dispose();
    }
  }

  chartElement.textContent = "";
  chartElement.style.display = "";
  chartElement.style.alignItems = "";
  chartElement.style.justifyContent = "";
  chartElement.style.color = "";
  chartElement.style.fontSize = "";

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
      hasData(runningData),
    ),
  );

  const monthlyData = stats.per_month || [];
  charts.push(
    renderChart(
      "members-monthly-chart",
      createMonthlyBarChart("New Members per Month", "Members", monthlyData, palette),
      hasData(monthlyData),
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
      hasData(runningData),
    ),
  );

  const monthlyData = stats.per_month || [];
  charts.push(
    renderChart(
      "events-monthly-chart",
      createMonthlyBarChart("New Events per Month", "Events", monthlyData, palette),
      hasData(monthlyData),
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
      hasData(runningData),
    ),
  );

  const monthlyData = stats.per_month || [];
  charts.push(
    renderChart(
      "attendees-monthly-chart",
      createMonthlyBarChart("New Attendees per Month", "Attendees", monthlyData, palette),
      hasData(monthlyData),
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
