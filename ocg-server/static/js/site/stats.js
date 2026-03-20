import {
  createAreaChart,
  createMonthlyBarChart,
  dashboardFontFamily,
  getThemePalette,
  getChartUiColors,
  hasChartData,
  hasTimeSeriesData,
  loadEChartsScript,
} from "/static/js/dashboard/common.js";
import {
  getCategoryLabelInterval,
  getTimeSplitNumber,
  registerChartResizeHandler,
  renderChart,
} from "/static/js/common/stats.js";

/**
 * Apply stats-page specific legend styling without affecting dashboard charts.
 * @param {Object} option - ECharts option object.
 * @param {Object} legendOverrides - Legend overrides.
 * @returns {Object} Styled ECharts option.
 */
const styleStatsPageLegend = (option, legendOverrides = {}) => {
  const uiColors = getChartUiColors();
  const legend = {
    bottom: 10,
    left: "center",
    itemGap: 12,
    textStyle: {
      fontFamily: dashboardFontFamily,
      fontSize: 12,
      color: uiColors.muted,
    },
    ...legendOverrides,
  };

  if (option?.baseOption) {
    option.baseOption.legend = Object.assign({}, option.baseOption.legend, legend);
    option.baseOption.grid = Object.assign({}, option.baseOption.grid, { bottom: 100 });
    return option;
  }

  option.legend = Object.assign({}, option.legend, legend);
  return option;
};

/**
 * Returns the target number of visible monthly x-axis labels for the viewport.
 * @returns {number} Visible label target.
 */
const getMonthlyLabelTarget = () => {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return 7;
  }

  return window.matchMedia("(max-width: 640px)").matches ? 3 : 7;
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
  const runningOption = styleStatsPageLegend(
    createAreaChart(`${label} over time`, label, runningData, palette),
  );
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
  const monthlyOption = styleStatsPageLegend(
    createMonthlyBarChart(`New ${label} per Month`, label, monthlyData, palette),
  );
  const monthlyCategoryCount = monthlyOption.xAxis?.data?.length || monthlyData.length;
  monthlyOption.xAxis = Object.assign({}, monthlyOption.xAxis, {
    axisLabel: Object.assign({}, monthlyOption.xAxis?.axisLabel, {
      hideOverlap: false,
      rotate: 0,
      interval: getCategoryLabelInterval(monthlyCategoryCount, getMonthlyLabelTarget()),
      formatter: (value) => value,
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

  registerChartResizeHandler(charts);
};
