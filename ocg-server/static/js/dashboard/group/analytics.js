import {
  loadEChartsScript,
  getThemePalette,
  createAreaChart,
  createMonthlyBarChart,
  initChart,
} from "/static/js/dashboard/common.js";
import "/static/js/common/svg-spinner.js";
import { debounce } from "/static/js/common/common.js";

function addSpinner(container) {
  if (!container || container.querySelector(".chart-spinner")) {
    return;
  }

  container.classList.add("relative");

  const spinner = document.createElement("div");
  spinner.innerHTML =
    '<svg-spinner size="size-10" class="chart-spinner absolute inset-0 flex items-center justify-center text-gray-500 bg-white/80 backdrop-blur-[1px] z-10"></svg-spinner>';
  container.appendChild(spinner);
}

function removeSpinner(container) {
  container?.querySelector(".chart-spinner")?.remove();
}

function hasData(data) {
  return Array.isArray(data) && data.length > 0;
}

function showEmptyState(elementId) {
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
}

function renderChart(elementId, option, hasChartData) {
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
}

function initMembersCharts(stats = {}, palette) {
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
}

function initEventsCharts(stats = {}, palette) {
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
}

function initAttendeesCharts(stats = {}, palette) {
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
}

export function showAnalyticsSpinners() {
  document.querySelectorAll("[data-analytics-chart]").forEach((container) => {
    addSpinner(container);
  });
}

export async function initAnalyticsCharts(stats) {
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
}
