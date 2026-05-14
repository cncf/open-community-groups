import {
  getThemePalette,
  toCategorySeries,
  createAreaChart,
  createMonthlyBarChart,
  createDailyBarChart,
  createHorizontalBarChart,
  createPieChart,
  buildStackedMonthlySeries,
  buildStackedTimeSeries,
  createStackedMonthlyChart,
  createStackedAreaChart,
  loadEChartsScript,
  deferUntilHtmxSettled,
  hasChartData,
  hasTimeSeriesData,
  hasStackedTimeSeriesData,
} from "/static/js/dashboard/common.js";
import { registerChartResizeHandler, renderChart } from "/static/js/common/stats.js";

/**
 * Render page view charts.
 * @param {Object} pageViews - Page views stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initPageViewsCharts = async (pageViews = {}, palette) => {
  await loadEChartsScript();

  const charts = [];

  const totalMonthlyData = pageViews.total?.per_month_views || [];
  const totalMonthlyChart = renderChart(
    "total-views-monthly-chart",
    createMonthlyBarChart("Monthly total page views", "Page views", totalMonthlyData, palette, {
      description: "All tracked views grouped by month.",
      useTimeAxis: true,
      reservePeriodStart: true,
    }),
    hasChartData(totalMonthlyData),
  );
  if (totalMonthlyChart) charts.push(totalMonthlyChart);

  const totalDailyData = pageViews.total?.per_day_views || [];
  const totalDailyChart = renderChart(
    "total-views-daily-chart",
    createDailyBarChart("Daily total page views", "Page views", totalDailyData, palette, {
      description: "All tracked views over the last 30 days.",
    }),
    hasChartData(totalDailyData),
  );
  if (totalDailyChart) charts.push(totalDailyChart);

  const communityMonthlyData = pageViews.community?.per_month_views || [];
  const communityMonthlyChart = renderChart(
    "community-views-monthly-chart",
    createMonthlyBarChart("Monthly community page views", "Page views", communityMonthlyData, palette, {
      description: "Community page views grouped by month.",
      useTimeAxis: true,
      reservePeriodStart: true,
    }),
    hasChartData(communityMonthlyData),
  );
  if (communityMonthlyChart) charts.push(communityMonthlyChart);

  const communityDailyData = pageViews.community?.per_day_views || [];
  const communityDailyChart = renderChart(
    "community-views-daily-chart",
    createDailyBarChart(
      "Daily community page views during the last month",
      "Page views",
      communityDailyData,
      palette,
      { description: "Community page views over the last 30 days." },
    ),
    hasChartData(communityDailyData),
  );
  if (communityDailyChart) charts.push(communityDailyChart);

  const groupMonthlyData = pageViews.groups?.per_month_views || [];
  const groupMonthlyChart = renderChart(
    "groups-views-monthly-chart",
    createMonthlyBarChart("Monthly group page views", "Page views", groupMonthlyData, palette, {
      description: "Group page views grouped by month.",
      useTimeAxis: true,
      reservePeriodStart: true,
    }),
    hasChartData(groupMonthlyData),
  );
  if (groupMonthlyChart) charts.push(groupMonthlyChart);

  const groupDailyData = pageViews.groups?.per_day_views || [];
  const groupDailyChart = renderChart(
    "groups-views-daily-chart",
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

  const eventMonthlyData = pageViews.events?.per_month_views || [];
  const eventMonthlyChart = renderChart(
    "events-views-monthly-chart",
    createMonthlyBarChart("Monthly event page views", "Page views", eventMonthlyData, palette, {
      description: "Event page views grouped by month.",
      useTimeAxis: true,
      reservePeriodStart: true,
    }),
    hasChartData(eventMonthlyData),
  );
  if (eventMonthlyChart) charts.push(eventMonthlyChart);

  const eventDailyData = pageViews.events?.per_day_views || [];
  const eventDailyChart = renderChart(
    "events-views-daily-chart",
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
 * Render groups charts.
 * @param {Object} groups - Group stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initGroupsCharts = async (groups = {}, palette) => {
  await loadEChartsScript();

  const charts = [];

  const runningData = groups.running_total || [];
  const runningChart = renderChart(
    "groups-running-chart",
    createAreaChart("Groups over time", "Groups", runningData, palette, {
      description: "Cumulative active groups over time.",
    }),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = renderChart(
    "groups-monthly-chart",
    createMonthlyBarChart("New Groups per Month", "Groups", groups.per_month, palette, {
      description: "Groups created each month.",
      reservePeriodStart: true,
    }),
    hasChartData(groups.per_month || []),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const categoryData = toCategorySeries(groups.total_by_category || []);
  const categoryChart = renderChart(
    "groups-category-chart",
    createHorizontalBarChart("Groups by Category", categoryData, palette, {
      description: "Current groups split by category.",
    }),
    hasChartData(categoryData),
  );
  if (categoryChart) charts.push(categoryChart);

  const regionData = toCategorySeries(groups.total_by_region || []);
  const regionChart = renderChart(
    "groups-region-chart",
    createPieChart("Groups by Region", "Groups", regionData, palette, {
      description: "Current groups split by region.",
    }),
    hasChartData(regionData),
  );
  if (regionChart) charts.push(regionChart);

  const runningCategorySeries = buildStackedTimeSeries(groups.running_total_by_category || {}).series;
  const runningCategoryChart = renderChart(
    "groups-running-category-chart",
    createStackedAreaChart("Groups over time by category", runningCategorySeries, palette, {
      description: "Cumulative groups split by category.",
    }),
    hasStackedTimeSeriesData(runningCategorySeries),
  );
  if (runningCategoryChart) charts.push(runningCategoryChart);

  const runningRegionSeries = buildStackedTimeSeries(groups.running_total_by_region || {}).series;
  const runningRegionChart = renderChart(
    "groups-running-region-chart",
    createStackedAreaChart("Groups over time by region", runningRegionSeries, palette, {
      description: "Cumulative groups split by region.",
    }),
    hasStackedTimeSeriesData(runningRegionSeries),
  );
  if (runningRegionChart) charts.push(runningRegionChart);

  const monthlyByCategory = buildStackedMonthlySeries(groups.per_month_by_category || {}, {
    reservePeriodStart: true,
  });
  const monthlyCategoryChart = renderChart(
    "groups-monthly-category-chart",
    createStackedMonthlyChart(
      "New Groups per Month by category",
      monthlyByCategory.months,
      monthlyByCategory.series,
      palette,
      { description: "Groups created each month by category." },
    ),
    hasChartData(monthlyByCategory.months),
  );
  if (monthlyCategoryChart) charts.push(monthlyCategoryChart);

  const monthlyByRegion = buildStackedMonthlySeries(groups.per_month_by_region || {}, {
    reservePeriodStart: true,
  });
  const monthlyRegionChart = renderChart(
    "groups-monthly-region-chart",
    createStackedMonthlyChart(
      "New Groups per Month by region",
      monthlyByRegion.months,
      monthlyByRegion.series,
      palette,
      { description: "Groups created each month by region." },
    ),
    hasChartData(monthlyByRegion.months),
  );
  if (monthlyRegionChart) charts.push(monthlyRegionChart);

  return charts;
};

/**
 * Render members charts.
 * @param {Object} members - Member stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initMembersCharts = async (members = {}, palette) => {
  await loadEChartsScript();

  const charts = [];

  const runningData = members.running_total || [];
  const monthlyByCategory = buildStackedMonthlySeries(members.per_month_by_category || {}, {
    reservePeriodStart: true,
  });
  const monthlyCategoryChart = renderChart(
    "members-monthly-category-chart",
    createStackedMonthlyChart(
      "New Members per Month by category",
      monthlyByCategory.months,
      monthlyByCategory.series,
      palette,
      { description: "Member joins each month by category." },
    ),
    hasChartData(monthlyByCategory.months),
  );
  if (monthlyCategoryChart) charts.push(monthlyCategoryChart);

  const monthlyByRegion = buildStackedMonthlySeries(members.per_month_by_region || {}, {
    reservePeriodStart: true,
  });
  const monthlyRegionChart = renderChart(
    "members-monthly-region-chart",
    createStackedMonthlyChart(
      "New Members per Month by region",
      monthlyByRegion.months,
      monthlyByRegion.series,
      palette,
      { description: "Member joins each month by region." },
    ),
    hasChartData(monthlyByRegion.months),
  );
  if (monthlyRegionChart) charts.push(monthlyRegionChart);

  const runningChart = renderChart(
    "members-running-chart",
    createAreaChart("Members over time", "Members", runningData, palette, {
      description: "Cumulative member joins over time.",
    }),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = renderChart(
    "members-monthly-chart",
    createMonthlyBarChart("New Members per Month", "Members", members.per_month, palette, {
      description: "Member joins each month.",
      reservePeriodStart: true,
    }),
    hasChartData(members.per_month || []),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const categoryData = toCategorySeries(members.total_by_category || []);
  const categoryChart = renderChart(
    "members-category-chart",
    createHorizontalBarChart("Members by Group Category", categoryData, palette, {
      description: "Current members split by group category.",
    }),
    hasChartData(categoryData),
  );
  if (categoryChart) charts.push(categoryChart);

  const regionData = toCategorySeries(members.total_by_region || []);
  const regionChart = renderChart(
    "members-region-chart",
    createPieChart("Members by Region", "Members", regionData, palette, {
      description: "Current members split by region.",
    }),
    hasChartData(regionData),
  );
  if (regionChart) charts.push(regionChart);

  const runningCategorySeries = buildStackedTimeSeries(members.running_total_by_category || {}).series;
  const runningCategoryChart = renderChart(
    "members-running-category-chart",
    createStackedAreaChart("Members over time by category", runningCategorySeries, palette, {
      description: "Cumulative members split by category.",
    }),
    hasStackedTimeSeriesData(runningCategorySeries),
  );
  if (runningCategoryChart) charts.push(runningCategoryChart);

  const runningRegionSeries = buildStackedTimeSeries(members.running_total_by_region || {}).series;
  const runningRegionChart = renderChart(
    "members-running-region-chart",
    createStackedAreaChart("Members over time by region", runningRegionSeries, palette, {
      description: "Cumulative members split by region.",
    }),
    hasStackedTimeSeriesData(runningRegionSeries),
  );
  if (runningRegionChart) charts.push(runningRegionChart);

  return charts;
};

/**
 * Render events charts.
 * @param {Object} events - Event stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initEventsCharts = async (events = {}, palette) => {
  await loadEChartsScript();

  const charts = [];

  const runningData = events.running_total || [];
  const runningChart = renderChart(
    "events-running-chart",
    createAreaChart("Events over time", "Events", runningData, palette, {
      description: "Cumulative published events over time.",
    }),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = renderChart(
    "events-monthly-chart",
    createMonthlyBarChart("Events per Month", "Events", events.per_month, palette, {
      description: "Published events by scheduled month.",
      reservePeriodStart: true,
    }),
    hasChartData(events.per_month || []),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const groupCategoryData = toCategorySeries(events.total_by_group_category || []);
  const groupCategoryChart = renderChart(
    "events-group-category-chart",
    createHorizontalBarChart("Events by Group Category", groupCategoryData, palette, {
      description: "Published events split by group category.",
    }),
    hasChartData(groupCategoryData),
  );
  if (groupCategoryChart) charts.push(groupCategoryChart);

  const regionData = toCategorySeries(events.total_by_group_region || []);
  const regionChart = renderChart(
    "events-region-chart",
    createPieChart("Events by Region", "Events", regionData, palette, {
      description: "Published events split by region.",
    }),
    hasChartData(regionData),
  );
  if (regionChart) charts.push(regionChart);

  const categoryData = toCategorySeries(events.total_by_event_category || []);
  const categoryChart = renderChart(
    "events-category-chart",
    createHorizontalBarChart("Events by Type", categoryData, palette, {
      description: "Published events split by event type.",
    }),
    hasChartData(categoryData),
  );
  if (categoryChart) charts.push(categoryChart);

  const runningByGroupCategory = buildStackedTimeSeries(events.running_total_by_group_category || {});
  const runningGroupCategoryChart = renderChart(
    "events-running-group-category-chart",
    createStackedAreaChart("Events over time by group category", runningByGroupCategory.series, palette, {
      description: "Cumulative events by group category.",
    }),
    hasStackedTimeSeriesData(runningByGroupCategory.series),
  );
  if (runningGroupCategoryChart) charts.push(runningGroupCategoryChart);

  const runningByGroupRegion = buildStackedTimeSeries(events.running_total_by_group_region || {});
  const runningGroupRegionChart = renderChart(
    "events-running-group-region-chart",
    createStackedAreaChart("Events over time by group region", runningByGroupRegion.series, palette, {
      description: "Cumulative events by group region.",
    }),
    hasStackedTimeSeriesData(runningByGroupRegion.series),
  );
  if (runningGroupRegionChart) charts.push(runningGroupRegionChart);

  const runningByEventCategory = buildStackedTimeSeries(events.running_total_by_event_category || {});
  const runningEventCategoryChart = renderChart(
    "events-running-event-category-chart",
    createStackedAreaChart("Events over time by event category", runningByEventCategory.series, palette, {
      description: "Cumulative events by event type.",
    }),
    hasStackedTimeSeriesData(runningByEventCategory.series),
  );
  if (runningEventCategoryChart) charts.push(runningEventCategoryChart);

  const monthlyByGroupCategory = buildStackedMonthlySeries(events.per_month_by_group_category || {}, {
    reservePeriodStart: true,
  });
  const monthlyGroupCategoryChart = renderChart(
    "events-monthly-group-category-chart",
    createStackedMonthlyChart(
      "Events per Month by group category",
      monthlyByGroupCategory.months,
      monthlyByGroupCategory.series,
      palette,
      { description: "Scheduled events each month by group category." },
    ),
    hasChartData(monthlyByGroupCategory.months),
  );
  if (monthlyGroupCategoryChart) charts.push(monthlyGroupCategoryChart);

  const monthlyByGroupRegion = buildStackedMonthlySeries(events.per_month_by_group_region || {}, {
    reservePeriodStart: true,
  });
  const monthlyGroupRegionChart = renderChart(
    "events-monthly-group-region-chart",
    createStackedMonthlyChart(
      "Events per Month by group region",
      monthlyByGroupRegion.months,
      monthlyByGroupRegion.series,
      palette,
      { description: "Scheduled events each month by group region." },
    ),
    hasChartData(monthlyByGroupRegion.months),
  );
  if (monthlyGroupRegionChart) charts.push(monthlyGroupRegionChart);

  const monthlyByEventCategory = buildStackedMonthlySeries(events.per_month_by_event_category || {}, {
    reservePeriodStart: true,
  });
  const monthlyEventCategoryChart = renderChart(
    "events-monthly-event-category-chart",
    createStackedMonthlyChart(
      "Events per Month by event category",
      monthlyByEventCategory.months,
      monthlyByEventCategory.series,
      palette,
      { description: "Scheduled events each month by event type." },
    ),
    hasChartData(monthlyByEventCategory.months),
  );
  if (monthlyEventCategoryChart) charts.push(monthlyEventCategoryChart);

  return charts;
};

/**
 * Render attendees charts.
 * @param {Object} attendees - Attendee stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initAttendeesCharts = async (attendees = {}, palette) => {
  await loadEChartsScript();

  const charts = [];

  const runningData = attendees.running_total || [];
  const runningChart = renderChart(
    "attendees-running-chart",
    createAreaChart("Attendees over time", "Attendees", runningData, palette, {
      description: "Cumulative event RSVPs over time.",
    }),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = renderChart(
    "attendees-monthly-chart",
    createMonthlyBarChart("Attendees per Month", "Attendees", attendees.per_month, palette, {
      description: "Event RSVPs created each month.",
      reservePeriodStart: true,
    }),
    hasChartData(attendees.per_month || []),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const categoryData = toCategorySeries(attendees.total_by_event_category || []);
  const categoryChart = renderChart(
    "attendees-category-chart",
    createHorizontalBarChart("Attendees by Event Type", categoryData, palette, {
      description: "Total RSVPs split by event type.",
    }),
    hasChartData(categoryData),
  );
  if (categoryChart) charts.push(categoryChart);

  const regionData = toCategorySeries(attendees.total_by_group_region || []);
  const regionChart = renderChart(
    "attendees-region-chart",
    createPieChart("Attendees by Region", "Attendees", regionData, palette, {
      description: "Total RSVPs split by group region.",
    }),
    hasChartData(regionData),
  );
  if (regionChart) charts.push(regionChart);

  const runningByGroupCategory = buildStackedTimeSeries(attendees.running_total_by_group_category || {});
  const runningGroupCategoryChart = renderChart(
    "attendees-running-group-category-chart",
    createStackedAreaChart("Attendees over time by group category", runningByGroupCategory.series, palette, {
      description: "Cumulative RSVPs by group category.",
    }),
    hasStackedTimeSeriesData(runningByGroupCategory.series),
  );
  if (runningGroupCategoryChart) charts.push(runningGroupCategoryChart);

  const runningByGroupRegion = buildStackedTimeSeries(attendees.running_total_by_group_region || {});
  const runningGroupRegionChart = renderChart(
    "attendees-running-group-region-chart",
    createStackedAreaChart("Attendees over time by group region", runningByGroupRegion.series, palette, {
      description: "Cumulative RSVPs by group region.",
    }),
    hasStackedTimeSeriesData(runningByGroupRegion.series),
  );
  if (runningGroupRegionChart) charts.push(runningGroupRegionChart);

  const runningByEventCategory = buildStackedTimeSeries(attendees.running_total_by_event_category || {});
  const runningEventCategoryChart = renderChart(
    "attendees-running-event-category-chart",
    createStackedAreaChart("Attendees over time by event category", runningByEventCategory.series, palette, {
      description: "Cumulative RSVPs by event type.",
    }),
    hasStackedTimeSeriesData(runningByEventCategory.series),
  );
  if (runningEventCategoryChart) charts.push(runningEventCategoryChart);

  const monthlyByGroupCategory = buildStackedMonthlySeries(attendees.per_month_by_group_category || {}, {
    reservePeriodStart: true,
  });
  const monthlyGroupCategoryChart = renderChart(
    "attendees-monthly-group-category-chart",
    createStackedMonthlyChart(
      "Attendees per Month by group category",
      monthlyByGroupCategory.months,
      monthlyByGroupCategory.series,
      palette,
      { description: "RSVPs created each month by group category." },
    ),
    hasChartData(monthlyByGroupCategory.months),
  );
  if (monthlyGroupCategoryChart) charts.push(monthlyGroupCategoryChart);

  const monthlyByGroupRegion = buildStackedMonthlySeries(attendees.per_month_by_group_region || {}, {
    reservePeriodStart: true,
  });
  const monthlyGroupRegionChart = renderChart(
    "attendees-monthly-group-region-chart",
    createStackedMonthlyChart(
      "Attendees per Month by group region",
      monthlyByGroupRegion.months,
      monthlyByGroupRegion.series,
      palette,
      { description: "RSVPs created each month by group region." },
    ),
    hasChartData(monthlyByGroupRegion.months),
  );
  if (monthlyGroupRegionChart) charts.push(monthlyGroupRegionChart);

  const monthlyByEventCategory = buildStackedMonthlySeries(attendees.per_month_by_event_category || {}, {
    reservePeriodStart: true,
  });
  const monthlyEventCategoryChart = renderChart(
    "attendees-monthly-event-category-chart",
    createStackedMonthlyChart(
      "Attendees per Month by event category",
      monthlyByEventCategory.months,
      monthlyByEventCategory.series,
      palette,
      { description: "RSVPs created each month by event type." },
    ),
    hasChartData(monthlyByEventCategory.months),
  );
  if (monthlyEventCategoryChart) charts.push(monthlyEventCategoryChart);

  return charts;
};

/**
 * Wire tab switching and lazy chart initialization for analytics sections.
 * @param {Object} stats - Community analytics payload.
 * @param {Object} palette - Theme palette.
 */
const setupAnalyticsTabs = (stats, palette) => {
  const tabButtons = document.querySelectorAll("[data-analytics-tab]");
  const tabContents = document.querySelectorAll("[data-analytics-content]");
  if (!tabButtons.length || !tabContents.length) {
    return;
  }

  const initializedTabs = new Set();
  const chartsByTab = new Map();
  const allCharts = new Set();

  const initTabCharts = async (tab) => {
    if (initializedTabs.has(tab)) {
      return false;
    }

    let charts = [];
    if (tab === "groups") {
      charts = await initGroupsCharts(stats.groups, palette);
    } else if (tab === "members") {
      charts = await initMembersCharts(stats.members, palette);
    } else if (tab === "events") {
      charts = await initEventsCharts(stats.events, palette);
    } else if (tab === "attendees") {
      charts = await initAttendeesCharts(stats.attendees, palette);
    } else if (tab === "page-views") {
      charts = await initPageViewsCharts(stats.page_views, palette);
    }

    const hydratedCharts = charts.filter(Boolean);
    hydratedCharts.forEach((chart) => allCharts.add(chart));
    chartsByTab.set(tab, hydratedCharts);
    initializedTabs.add(tab);
    return true;
  };

  const showTab = (tab) => {
    tabButtons.forEach((btn) => {
      btn.dataset.active = btn.dataset.analyticsTab === tab ? "true" : "false";
    });

    tabContents.forEach((content) => {
      const visible = content.dataset.analyticsContent === tab;
      content.classList.toggle("hidden", !visible);
    });

    initTabCharts(tab)
      .then(() => {
        (chartsByTab.get(tab) || []).forEach((chart) => chart.resize());
      })
      .catch((error) => console.error("Failed to initialize analytics charts", error));
  };

  showTab("groups");

  tabButtons.forEach((button) => {
    button.addEventListener("click", () => {
      const tab = button.dataset.analyticsTab;
      showTab(tab);
    });
  });

  registerChartResizeHandler(() => Array.from(allCharts));
};

/**
 * Render analytics charts with lazy tab initialization.
 * @param {Object} stats - Community statistics payload from the server.
 */
export const initAnalyticsCharts = async (stats) => {
  if (!stats) {
    return;
  }

  return deferUntilHtmxSettled(async () => {
    await loadEChartsScript();
    const palette = getThemePalette();
    setupAnalyticsTabs(stats, palette);
  });
};
