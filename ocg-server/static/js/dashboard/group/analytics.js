import {
  loadEChartsScript,
  getThemePalette,
  createAreaChart,
  createDailyBarChart,
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
    createAreaChart("Members over time", "Members", runningData, palette, {
      description: "Cumulative group members over time.",
    }),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyData = stats.per_month || [];
  const monthlyChart = renderChart(
    "members-monthly-chart",
    createMonthlyBarChart("New Members per Month", "Members", monthlyData, palette, {
      description: "Member joins each month.",
      reservePeriodStart: true,
    }),
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
    createAreaChart("Events over time", "Events", runningData, palette, {
      description: "Cumulative group events over time.",
    }),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyData = stats.per_month || [];
  const monthlyChart = renderChart(
    "events-monthly-chart",
    createMonthlyBarChart("Events per Month", "Events", monthlyData, palette, {
      description: "Published events by scheduled month.",
      reservePeriodStart: true,
    }),
    hasChartData(monthlyData),
  );
  if (monthlyChart) charts.push(monthlyChart);

  return charts;
};

/**
 * Build charts for page views.
 * @param {Object} stats - Page views stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initPageViewsCharts = async (stats = {}, palette) => {
  await loadEChartsScript();

  const charts = [];

  const totalMonthlyData = stats.total?.per_month_views || [];
  const totalMonthlyChart = renderChart(
    "total-views-monthly-chart",
    createMonthlyBarChart("Monthly total page views", "Page views", totalMonthlyData, palette, {
      description: "Group and event views grouped by month.",
      useTimeAxis: true,
      reservePeriodStart: true,
    }),
    hasChartData(totalMonthlyData),
  );
  if (totalMonthlyChart) charts.push(totalMonthlyChart);

  const totalDailyData = stats.total?.per_day_views || [];
  const totalDailyChart = renderChart(
    "total-views-daily-chart",
    createDailyBarChart("Daily total page views", "Page views", totalDailyData, palette, {
      description: "Group and event views over the last 30 days.",
    }),
    hasChartData(totalDailyData),
  );
  if (totalDailyChart) charts.push(totalDailyChart);

  const groupMonthlyData = stats.group?.per_month_views || [];
  const groupMonthlyChart = renderChart(
    "group-views-monthly-chart",
    createMonthlyBarChart("Monthly group page views", "Page views", groupMonthlyData, palette, {
      description: "Group page views grouped by month.",
      useTimeAxis: true,
      reservePeriodStart: true,
    }),
    hasChartData(groupMonthlyData),
  );
  if (groupMonthlyChart) charts.push(groupMonthlyChart);

  const groupDailyData = stats.group?.per_day_views || [];
  const groupDailyChart = renderChart(
    "group-views-daily-chart",
    createDailyBarChart(
      "Daily group page views during the last month",
      "Page views",
      groupDailyData,
      palette,
      { description: "Group page views over the last 30 days." },
    ),
    hasChartData(groupDailyData),
  );
  if (groupDailyChart) charts.push(groupDailyChart);

  const eventMonthlyData = stats.events?.per_month_views || [];
  const eventMonthlyChart = renderChart(
    "event-views-monthly-chart",
    createMonthlyBarChart("Monthly event page views", "Page views", eventMonthlyData, palette, {
      description: "Event page views grouped by month.",
      useTimeAxis: true,
      reservePeriodStart: true,
    }),
    hasChartData(eventMonthlyData),
  );
  if (eventMonthlyChart) charts.push(eventMonthlyChart);

  const eventDailyData = stats.events?.per_day_views || [];
  const eventDailyChart = renderChart(
    "event-views-daily-chart",
    createDailyBarChart(
      "Daily event page views during the last month",
      "Page views",
      eventDailyData,
      palette,
      { description: "Event page views over the last 30 days." },
    ),
    hasChartData(eventDailyData),
  );
  if (eventDailyChart) charts.push(eventDailyChart);

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
    createAreaChart("Attendees over time", "Attendees", runningData, palette, {
      description: "Cumulative event RSVPs over time.",
    }),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyData = stats.per_month || [];
  const monthlyChart = renderChart(
    "attendees-monthly-chart",
    createMonthlyBarChart("Attendees per Month", "Attendees", monthlyData, palette, {
      description: "Event RSVPs created each month.",
      reservePeriodStart: true,
    }),
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
      ...(await initPageViewsCharts(stats.page_views, palette)),
      ...initMembersCharts(stats.members, palette),
      ...initEventsCharts(stats.events, palette),
      ...initAttendeesCharts(stats.attendees, palette),
    ];

    const hydratedCharts = charts.filter(Boolean);

    registerChartResizeHandler(hydratedCharts);
  });
};
