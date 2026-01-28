import {
  createAreaChart,
  createMonthlyBarChart,
  getThemePalette,
  hasChartData,
  hasTimeSeriesData,
  loadEChartsScript,
} from "/static/js/dashboard/common.js";
import { debounce } from "/static/js/common/common.js";
import { getCategoryLabelInterval, getTimeSplitNumber, renderChart } from "/static/js/common/stats.js";

/**
 * Initialize charts for a stats section.
 * @param {string} key - Section key.
 * @param {string} label - Label for chart titles.
 * @param {Object} stats - Stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Chart instances.
 */
const initSectionCharts = async (key, label, stats = {}, palette) => {
  const section = stats[key] || {};
  const charts = [];

  const runningData = section.running_total || [];
  const runningOption = createAreaChart(`${label} over time`, label, runningData, palette);
  runningOption.xAxis = Object.assign({}, runningOption.xAxis, {
    axisLabel: Object.assign({}, runningOption.xAxis?.axisLabel, {
      formatter: "{yyyy}-{MM}",
      hideOverlap: true,
    }),
    splitNumber: getTimeSplitNumber(runningData.length),
  });
  const runningChart = renderChart(`${key}-running-chart`, runningOption, hasTimeSeriesData(runningData));
  if (runningChart) charts.push(runningChart);

  const monthlyData = section.per_month || [];
  const monthlyOption = createMonthlyBarChart(`New ${label} per Month`, label, monthlyData, palette);
  monthlyOption.xAxis = Object.assign({}, monthlyOption.xAxis, {
    axisLabel: Object.assign({}, monthlyOption.xAxis?.axisLabel, {
      hideOverlap: true,
      interval: getCategoryLabelInterval(monthlyData.length),
    }),
  });
  const monthlyChart = renderChart(`${key}-monthly-chart`, monthlyOption, hasChartData(monthlyData));
  if (monthlyChart) charts.push(monthlyChart);

  return charts;
};

/**
 * Render site stats charts.
 * @param {Object} stats - Site statistics payload from the server.
 * @returns {Promise<void>} Promise resolved when charts are initialized.
 */
export const initSiteStatsCharts = async (stats) => {
  if (!stats) {
    return;
  }

  await loadEChartsScript();
  const palette = getThemePalette();

  const charts = [];
  const sections = [
    { key: "groups", label: "Groups" },
    { key: "members", label: "Members" },
    { key: "events", label: "Events" },
    { key: "attendees", label: "Attendees" },
  ];

  for (const section of sections) {
    const sectionCharts = await initSectionCharts(section.key, section.label, stats, palette);
    charts.push(...sectionCharts);
  }

  const resizeCharts = debounce(() => {
    charts.forEach((chart) => chart.resize());
  }, 200);

  window.addEventListener("resize", resizeCharts);
};
