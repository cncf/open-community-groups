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
} from "/static/js/common/charts.js";
import { deferUntilHtmxSettled } from "/static/js/dashboard/common.js";
import { initializeOnReady } from "/static/js/common/dom.js";
import { registerChartResizeHandler, renderChart } from "/static/js/common/stats.js";

const COMMUNITY_ANALYTICS_DATA_SELECTOR = "[data-community-analytics]";
const COMMUNITY_ANALYTICS_READY_KEY = "communityAnalyticsReady";

/**
 * Adds a rendered chart to the collection when the container has chart data.
 * @param {Array<echarts.ECharts>} charts - Chart collection.
 * @param {string} elementId - Chart container ID.
 * @param {Object} chartOptions - ECharts options.
 * @param {boolean} hasData - Whether chart data is available.
 * @returns {void}
 */
const addRenderedChart = (charts, elementId, chartOptions, hasData) => {
  const chart = renderChart(elementId, chartOptions, hasData);
  if (chart) {
    charts.push(chart);
  }
};

/**
 * Builds a page-view chart from a small local chart spec.
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
 * Render page view charts.
 * @param {Object} pageViews - Page views stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
const initPageViewsCharts = async (pageViews = {}, palette) => {
  await loadEChartsScript();

  return [
    {
      elementId: "total-views-monthly-chart",
      title: "Monthly total page views",
      description: "All tracked views grouped by month",
      path: ["total", "per_month_views"],
      kind: "monthly",
    },
    {
      elementId: "total-views-daily-chart",
      title: "Daily total page views",
      description: "All tracked views over the last 30 days",
      path: ["total", "per_day_views"],
      kind: "daily",
    },
    {
      elementId: "community-views-monthly-chart",
      title: "Monthly community page views",
      description: "Community page views grouped by month",
      path: ["community", "per_month_views"],
      kind: "monthly",
    },
    {
      elementId: "community-views-daily-chart",
      title: "Daily community page views during the last month",
      description: "Community page views over the last 30 days",
      path: ["community", "per_day_views"],
      kind: "daily",
    },
    {
      elementId: "groups-views-monthly-chart",
      title: "Monthly group page views",
      description: "Group page views grouped by month",
      path: ["groups", "per_month_views"],
      kind: "monthly",
    },
    {
      elementId: "groups-views-daily-chart",
      title: "Daily group page views during the last month",
      description: "Group page views over the last 30 days",
      path: ["groups", "per_day_views"],
      kind: "daily",
    },
    {
      elementId: "events-views-monthly-chart",
      title: "Monthly event page views",
      description: "Event page views grouped by month",
      path: ["events", "per_month_views"],
      kind: "monthly",
    },
    {
      elementId: "events-views-daily-chart",
      title: "Daily event page views during the last month",
      description: "Event page views over the last 30 days",
      path: ["events", "per_day_views"],
      kind: "daily",
    },
  ]
    .map((config) => buildPageViewChart({ ...config, stats: pageViews, palette }))
    .filter(Boolean);
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
  addRenderedChart(
    charts,
    "groups-running-chart",
    createAreaChart("Groups over time", "Groups", runningData, palette, {
      description: "Cumulative active groups over time",
    }),
    hasTimeSeriesData(runningData),
  );

  addRenderedChart(
    charts,
    "groups-monthly-chart",
    createMonthlyBarChart("New Groups per Month", "Groups", groups.per_month, palette, {
      description: "Groups created each month",
      reservePeriodStart: true,
    }),
    hasChartData(groups.per_month || []),
  );

  const categoryData = toCategorySeries(groups.total_by_category || []);
  addRenderedChart(
    charts,
    "groups-category-chart",
    createHorizontalBarChart("Groups by Category", categoryData, palette, {
      description: "Current groups split by category",
    }),
    hasChartData(categoryData),
  );

  const regionData = toCategorySeries(groups.total_by_region || []);
  addRenderedChart(
    charts,
    "groups-region-chart",
    createPieChart("Groups by Region", "Groups", regionData, palette, {
      description: "Current groups split by region",
    }),
    hasChartData(regionData),
  );

  const runningCategorySeries = buildStackedTimeSeries(groups.running_total_by_category || {}).series;
  addRenderedChart(
    charts,
    "groups-running-category-chart",
    createStackedAreaChart("Groups over time by category", runningCategorySeries, palette, {
      description: "Cumulative groups split by category",
    }),
    hasStackedTimeSeriesData(runningCategorySeries),
  );

  const runningRegionSeries = buildStackedTimeSeries(groups.running_total_by_region || {}).series;
  addRenderedChart(
    charts,
    "groups-running-region-chart",
    createStackedAreaChart("Groups over time by region", runningRegionSeries, palette, {
      description: "Cumulative groups split by region",
    }),
    hasStackedTimeSeriesData(runningRegionSeries),
  );

  const monthlyByCategory = buildStackedMonthlySeries(groups.per_month_by_category || {}, {
    reservePeriodStart: true,
  });
  addRenderedChart(
    charts,
    "groups-monthly-category-chart",
    createStackedMonthlyChart(
      "New Groups per Month by category",
      monthlyByCategory.months,
      monthlyByCategory.series,
      palette,
      { description: "Groups created each month by category" },
    ),
    hasChartData(monthlyByCategory.months),
  );

  const monthlyByRegion = buildStackedMonthlySeries(groups.per_month_by_region || {}, {
    reservePeriodStart: true,
  });
  addRenderedChart(
    charts,
    "groups-monthly-region-chart",
    createStackedMonthlyChart(
      "New Groups per Month by region",
      monthlyByRegion.months,
      monthlyByRegion.series,
      palette,
      { description: "Groups created each month by region" },
    ),
    hasChartData(monthlyByRegion.months),
  );

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
  addRenderedChart(
    charts,
    "members-monthly-category-chart",
    createStackedMonthlyChart(
      "New Members per Month by category",
      monthlyByCategory.months,
      monthlyByCategory.series,
      palette,
      { description: "Member joins each month by category" },
    ),
    hasChartData(monthlyByCategory.months),
  );

  const monthlyByRegion = buildStackedMonthlySeries(members.per_month_by_region || {}, {
    reservePeriodStart: true,
  });
  addRenderedChart(
    charts,
    "members-monthly-region-chart",
    createStackedMonthlyChart(
      "New Members per Month by region",
      monthlyByRegion.months,
      monthlyByRegion.series,
      palette,
      { description: "Member joins each month by region" },
    ),
    hasChartData(monthlyByRegion.months),
  );

  addRenderedChart(
    charts,
    "members-running-chart",
    createAreaChart("Members over time", "Members", runningData, palette, {
      description: "Cumulative member joins over time",
    }),
    hasTimeSeriesData(runningData),
  );

  addRenderedChart(
    charts,
    "members-monthly-chart",
    createMonthlyBarChart("New Members per Month", "Members", members.per_month, palette, {
      description: "Member joins each month",
      reservePeriodStart: true,
    }),
    hasChartData(members.per_month || []),
  );

  const categoryData = toCategorySeries(members.total_by_category || []);
  addRenderedChart(
    charts,
    "members-category-chart",
    createHorizontalBarChart("Members by Group Category", categoryData, palette, {
      description: "Current members split by group category",
    }),
    hasChartData(categoryData),
  );

  const regionData = toCategorySeries(members.total_by_region || []);
  addRenderedChart(
    charts,
    "members-region-chart",
    createPieChart("Members by Region", "Members", regionData, palette, {
      description: "Current members split by region",
    }),
    hasChartData(regionData),
  );

  const runningCategorySeries = buildStackedTimeSeries(members.running_total_by_category || {}).series;
  addRenderedChart(
    charts,
    "members-running-category-chart",
    createStackedAreaChart("Members over time by category", runningCategorySeries, palette, {
      description: "Cumulative members split by category",
    }),
    hasStackedTimeSeriesData(runningCategorySeries),
  );

  const runningRegionSeries = buildStackedTimeSeries(members.running_total_by_region || {}).series;
  addRenderedChart(
    charts,
    "members-running-region-chart",
    createStackedAreaChart("Members over time by region", runningRegionSeries, palette, {
      description: "Cumulative members split by region",
    }),
    hasStackedTimeSeriesData(runningRegionSeries),
  );

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
  addRenderedChart(
    charts,
    "events-running-chart",
    createAreaChart("Events over time", "Events", runningData, palette, {
      description: "Cumulative published events over time",
    }),
    hasTimeSeriesData(runningData),
  );

  addRenderedChart(
    charts,
    "events-monthly-chart",
    createMonthlyBarChart("Events per Month", "Events", events.per_month, palette, {
      description: "Published events by scheduled month",
      reservePeriodStart: true,
    }),
    hasChartData(events.per_month || []),
  );

  const groupCategoryData = toCategorySeries(events.total_by_group_category || []);
  addRenderedChart(
    charts,
    "events-group-category-chart",
    createHorizontalBarChart("Events by Group Category", groupCategoryData, palette, {
      description: "Published events split by group category",
    }),
    hasChartData(groupCategoryData),
  );

  const regionData = toCategorySeries(events.total_by_group_region || []);
  addRenderedChart(
    charts,
    "events-region-chart",
    createPieChart("Events by Region", "Events", regionData, palette, {
      description: "Published events split by region",
    }),
    hasChartData(regionData),
  );

  const categoryData = toCategorySeries(events.total_by_event_category || []);
  addRenderedChart(
    charts,
    "events-category-chart",
    createHorizontalBarChart("Events by Type", categoryData, palette, {
      description: "Published events split by event type",
    }),
    hasChartData(categoryData),
  );

  const runningByGroupCategory = buildStackedTimeSeries(events.running_total_by_group_category || {});
  addRenderedChart(
    charts,
    "events-running-group-category-chart",
    createStackedAreaChart("Events over time by group category", runningByGroupCategory.series, palette, {
      description: "Cumulative events by group category",
    }),
    hasStackedTimeSeriesData(runningByGroupCategory.series),
  );

  const runningByGroupRegion = buildStackedTimeSeries(events.running_total_by_group_region || {});
  addRenderedChart(
    charts,
    "events-running-group-region-chart",
    createStackedAreaChart("Events over time by group region", runningByGroupRegion.series, palette, {
      description: "Cumulative events by group region",
    }),
    hasStackedTimeSeriesData(runningByGroupRegion.series),
  );

  const runningByEventCategory = buildStackedTimeSeries(events.running_total_by_event_category || {});
  addRenderedChart(
    charts,
    "events-running-event-category-chart",
    createStackedAreaChart("Events over time by event category", runningByEventCategory.series, palette, {
      description: "Cumulative events by event type",
    }),
    hasStackedTimeSeriesData(runningByEventCategory.series),
  );

  const monthlyByGroupCategory = buildStackedMonthlySeries(events.per_month_by_group_category || {}, {
    reservePeriodStart: true,
  });
  addRenderedChart(
    charts,
    "events-monthly-group-category-chart",
    createStackedMonthlyChart(
      "Events per Month by group category",
      monthlyByGroupCategory.months,
      monthlyByGroupCategory.series,
      palette,
      { description: "Scheduled events each month by group category" },
    ),
    hasChartData(monthlyByGroupCategory.months),
  );

  const monthlyByGroupRegion = buildStackedMonthlySeries(events.per_month_by_group_region || {}, {
    reservePeriodStart: true,
  });
  addRenderedChart(
    charts,
    "events-monthly-group-region-chart",
    createStackedMonthlyChart(
      "Events per Month by group region",
      monthlyByGroupRegion.months,
      monthlyByGroupRegion.series,
      palette,
      { description: "Scheduled events each month by group region" },
    ),
    hasChartData(monthlyByGroupRegion.months),
  );

  const monthlyByEventCategory = buildStackedMonthlySeries(events.per_month_by_event_category || {}, {
    reservePeriodStart: true,
  });
  addRenderedChart(
    charts,
    "events-monthly-event-category-chart",
    createStackedMonthlyChart(
      "Events per Month by event category",
      monthlyByEventCategory.months,
      monthlyByEventCategory.series,
      palette,
      { description: "Scheduled events each month by event type" },
    ),
    hasChartData(monthlyByEventCategory.months),
  );

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
  addRenderedChart(
    charts,
    "attendees-running-chart",
    createAreaChart("Attendees over time", "Attendees", runningData, palette, {
      description: "Cumulative event RSVPs over time",
    }),
    hasTimeSeriesData(runningData),
  );

  addRenderedChart(
    charts,
    "attendees-monthly-chart",
    createMonthlyBarChart("Attendees per Month", "Attendees", attendees.per_month, palette, {
      description: "Event RSVPs created each month",
      reservePeriodStart: true,
    }),
    hasChartData(attendees.per_month || []),
  );

  const categoryData = toCategorySeries(attendees.total_by_event_category || []);
  addRenderedChart(
    charts,
    "attendees-category-chart",
    createHorizontalBarChart("Attendees by Event Type", categoryData, palette, {
      description: "Total RSVPs split by event type",
    }),
    hasChartData(categoryData),
  );

  const regionData = toCategorySeries(attendees.total_by_group_region || []);
  addRenderedChart(
    charts,
    "attendees-region-chart",
    createPieChart("Attendees by Region", "Attendees", regionData, palette, {
      description: "Total RSVPs split by group region",
    }),
    hasChartData(regionData),
  );

  const runningByGroupCategory = buildStackedTimeSeries(attendees.running_total_by_group_category || {});
  addRenderedChart(
    charts,
    "attendees-running-group-category-chart",
    createStackedAreaChart("Attendees over time by group category", runningByGroupCategory.series, palette, {
      description: "Cumulative RSVPs by group category",
    }),
    hasStackedTimeSeriesData(runningByGroupCategory.series),
  );

  const runningByGroupRegion = buildStackedTimeSeries(attendees.running_total_by_group_region || {});
  addRenderedChart(
    charts,
    "attendees-running-group-region-chart",
    createStackedAreaChart("Attendees over time by group region", runningByGroupRegion.series, palette, {
      description: "Cumulative RSVPs by group region",
    }),
    hasStackedTimeSeriesData(runningByGroupRegion.series),
  );

  const runningByEventCategory = buildStackedTimeSeries(attendees.running_total_by_event_category || {});
  addRenderedChart(
    charts,
    "attendees-running-event-category-chart",
    createStackedAreaChart("Attendees over time by event category", runningByEventCategory.series, palette, {
      description: "Cumulative RSVPs by event type",
    }),
    hasStackedTimeSeriesData(runningByEventCategory.series),
  );

  const monthlyByGroupCategory = buildStackedMonthlySeries(attendees.per_month_by_group_category || {}, {
    reservePeriodStart: true,
  });
  addRenderedChart(
    charts,
    "attendees-monthly-group-category-chart",
    createStackedMonthlyChart(
      "Attendees per Month by group category",
      monthlyByGroupCategory.months,
      monthlyByGroupCategory.series,
      palette,
      { description: "RSVPs created each month by group category" },
    ),
    hasChartData(monthlyByGroupCategory.months),
  );

  const monthlyByGroupRegion = buildStackedMonthlySeries(attendees.per_month_by_group_region || {}, {
    reservePeriodStart: true,
  });
  addRenderedChart(
    charts,
    "attendees-monthly-group-region-chart",
    createStackedMonthlyChart(
      "Attendees per Month by group region",
      monthlyByGroupRegion.months,
      monthlyByGroupRegion.series,
      palette,
      { description: "RSVPs created each month by group region" },
    ),
    hasChartData(monthlyByGroupRegion.months),
  );

  const monthlyByEventCategory = buildStackedMonthlySeries(attendees.per_month_by_event_category || {}, {
    reservePeriodStart: true,
  });
  addRenderedChart(
    charts,
    "attendees-monthly-event-category-chart",
    createStackedMonthlyChart(
      "Attendees per Month by event category",
      monthlyByEventCategory.months,
      monthlyByEventCategory.series,
      palette,
      { description: "RSVPs created each month by event type" },
    ),
    hasChartData(monthlyByEventCategory.months),
  );

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

/**
 * Initialize community analytics charts from the page JSON marker.
 * @param {Document|Element} root - Root element to search from.
 * @returns {Promise<void>} Promise resolved when initialization finishes.
 */
export const initializeCommunityAnalyticsFromPage = async (root = document) => {
  const marker = root.querySelector(COMMUNITY_ANALYTICS_DATA_SELECTOR);
  if (!marker || marker.dataset[COMMUNITY_ANALYTICS_READY_KEY] === "true") {
    return;
  }

  const stats = readCommunityAnalyticsPayload(marker);
  if (!stats) {
    return;
  }

  marker.dataset[COMMUNITY_ANALYTICS_READY_KEY] = "true";

  try {
    await initAnalyticsCharts(stats);
  } catch (error) {
    console.error("Failed to initialize analytics charts:", error);
  }
};

/**
 * Read the community analytics payload from an inert JSON marker.
 * @param {HTMLElement} marker - JSON marker element.
 * @returns {Object|null} Parsed stats payload.
 */
const readCommunityAnalyticsPayload = (marker) => {
  try {
    return JSON.parse(marker.textContent || "{}");
  } catch (error) {
    console.error("Failed to parse community analytics payload:", error);
    return null;
  }
};

initializeOnReady(() => initializeCommunityAnalyticsFromPage());
