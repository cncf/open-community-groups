import {
  loadEChartsScript,
  getThemePalette,
  createAreaChart,
  createDailyBarChart,
  createMonthlyBarChart,
  hasChartData,
  hasTimeSeriesData,
} from "/static/js/common/charts/charts.js";
import { deferUntilHtmxSettled } from "/static/js/dashboard/common.js";
import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";
import {
  addRenderedChart,
  initializeChartsFromJsonMarker,
  registerChartResizeHandler,
  renderChart,
} from "/static/js/common/charts/stats.js";

const GROUP_ANALYTICS_DATA_SELECTOR = "[data-group-analytics]";
const GROUP_ANALYTICS_READY_KEY = "groupAnalyticsReady";

/**
 * Builds a running total area chart and monthly bar chart for one metric.
 * @param {Object} config - Trend chart configuration.
 * @param {Object} config.stats - Metric stats payload.
 * @param {Object} config.palette - Theme palette.
 * @param {string} config.runningChartId - Running total chart ID.
 * @param {string} config.monthlyChartId - Monthly chart ID.
 * @param {string} config.runningTitle - Running total chart title.
 * @param {string} config.monthlyTitle - Monthly chart title.
 * @param {string} config.label - Metric label.
 * @param {string} config.runningDescription - Running chart description.
 * @param {string} config.monthlyDescription - Monthly chart description.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const buildTrendCharts = ({
  stats = {},
  palette,
  runningChartId,
  monthlyChartId,
  runningTitle,
  monthlyTitle,
  label,
  runningDescription,
  monthlyDescription,
}) => {
  const charts = [];
  const runningData = stats.running_total || [];
  const monthlyData = stats.per_month || [];

  addRenderedChart(
    charts,
    runningChartId,
    createAreaChart(runningTitle, label, runningData, palette, {
      description: runningDescription,
    }),
    hasTimeSeriesData(runningData),
  );
  addRenderedChart(
    charts,
    monthlyChartId,
    createMonthlyBarChart(monthlyTitle, label, monthlyData, palette, {
      description: monthlyDescription,
      reservePeriodStart: true,
    }),
    hasChartData(monthlyData),
  );

  return charts;
};

/**
 * Build charts for members metrics.
 * @param {Object} stats - Members stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initMembersCharts = (stats = {}, palette) =>
  buildTrendCharts({
    stats,
    palette,
    runningChartId: "members-running-chart",
    monthlyChartId: "members-monthly-chart",
    runningTitle: "Members over time",
    monthlyTitle: "New Members per Month",
    label: "Members",
    runningDescription: "Cumulative group members over time",
    monthlyDescription: "Member joins each month",
  });

/**
 * Build charts for events metrics.
 * @param {Object} stats - Events stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initEventsCharts = (stats = {}, palette) =>
  buildTrendCharts({
    stats,
    palette,
    runningChartId: "events-running-chart",
    monthlyChartId: "events-monthly-chart",
    runningTitle: "Events over time",
    monthlyTitle: "Events per Month",
    label: "Events",
    runningDescription: "Cumulative group events over time",
    monthlyDescription: "Published events by scheduled month",
  });

/**
 * Build a page-view chart from a small local chart spec.
 * @param {Object} config - Page-view chart configuration.
 * @param {Object} config.stats - Page views stats payload.
 * @param {Object} config.palette - Theme palette.
 * @param {string} config.elementId - Chart container ID.
 * @param {string} config.title - Chart title.
 * @param {string} config.description - Chart description.
 * @param {Array<string>} config.path - Payload path for chart data.
 * @param {"monthly"|"daily"} config.kind - Chart kind.
 * @returns {echarts.ECharts|null} Initialized chart.
 */
const buildPageViewChart = ({ stats, palette, elementId, title, description, path, kind }) => {
  const data = path.reduce((value, key) => value?.[key], stats) || [];
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
 * Build charts for page views.
 * @param {Object} stats - Page views stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initPageViewsCharts = (stats = {}, palette) =>
  [
    {
      elementId: "total-views-monthly-chart",
      title: "Monthly total page views",
      description: "Group and event views grouped by month",
      path: ["total", "per_month_views"],
      kind: "monthly",
    },
    {
      elementId: "total-views-daily-chart",
      title: "Daily total page views",
      description: "Group and event views over the last 30 days",
      path: ["total", "per_day_views"],
      kind: "daily",
    },
    {
      elementId: "group-views-monthly-chart",
      title: "Monthly group page views",
      description: "Group page views grouped by month",
      path: ["group", "per_month_views"],
      kind: "monthly",
    },
    {
      elementId: "group-views-daily-chart",
      title: "Daily group page views during the last month",
      description: "Group page views over the last 30 days",
      path: ["group", "per_day_views"],
      kind: "daily",
    },
    {
      elementId: "event-views-monthly-chart",
      title: "Monthly event page views",
      description: "Event page views grouped by month",
      path: ["events", "per_month_views"],
      kind: "monthly",
    },
    {
      elementId: "event-views-daily-chart",
      title: "Daily event page views during the last month",
      description: "Event page views over the last 30 days",
      path: ["events", "per_day_views"],
      kind: "daily",
    },
  ]
    .map((config) => buildPageViewChart({ ...config, stats, palette }))
    .filter(Boolean);

/**
 * Build charts for attendees metrics.
 * @param {Object} stats - Attendees stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initAttendeesCharts = (stats = {}, palette) =>
  buildTrendCharts({
    stats,
    palette,
    runningChartId: "attendees-running-chart",
    monthlyChartId: "attendees-monthly-chart",
    runningTitle: "Attendees over time",
    monthlyTitle: "Attendees per Month",
    label: "Attendees",
    runningDescription: "Cumulative event RSVPs over time",
    monthlyDescription: "Event RSVPs created each month",
  });

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
      ...initPageViewsCharts(stats.page_views, palette),
      ...initMembersCharts(stats.members, palette),
      ...initEventsCharts(stats.events, palette),
      ...initAttendeesCharts(stats.attendees, palette),
    ];

    const hydratedCharts = charts.filter(Boolean);

    registerChartResizeHandler(hydratedCharts);
  });
};

/**
 * Initialize group analytics charts from the page JSON marker.
 * @param {Document|Element} root - Root element to search from.
 * @returns {Promise<void>} Promise resolved when initialization finishes.
 */
export const initializeGroupAnalyticsFromPage = async (root = document) => {
  return initializeChartsFromJsonMarker({
    root,
    selector: GROUP_ANALYTICS_DATA_SELECTOR,
    readyKey: GROUP_ANALYTICS_READY_KEY,
    initialize: initAnalyticsCharts,
    parseErrorMessage: "Failed to parse group analytics payload:",
    initErrorMessage: "Failed to initialize analytics charts:",
  });
};

initializeOnReadyAndHtmxLoad(initializeGroupAnalyticsFromPage);
