import {
  clearChartElement,
  createAreaChart,
  createMonthlyBarChart,
  deferUntilHtmxSettled,
  getThemePalette,
  hasChartData,
  hasTimeSeriesData,
  initChart,
  loadEChartsScript,
  showChartEmptyState,
} from "/static/js/dashboard/common.js";
import { debounce } from "/static/js/common/common.js";

/**
 * Render a chart or show an empty state based on data availability.
 * @param {string} elementId - Target chart element id.
 * @param {Object} option - ECharts option object.
 * @param {boolean} hasData - Whether the chart has data to render.
 * @returns {echarts.ECharts|null} Chart instance or null.
 */
const renderChart = (elementId, option, hasData) => {
  if (!hasData) {
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
const getCategoryLabelInterval = (count, target = 12) => {
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
const getTimeSplitNumber = (count) => {
  if (!count) {
    return 4;
  }

  return Math.min(6, Math.max(3, Math.round(count / 6)));
};

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

  return deferUntilHtmxSettled(async () => {
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
  });
};
