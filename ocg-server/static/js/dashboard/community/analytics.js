import {
  getThemePalette,
  toCategorySeries,
  initChart,
  createAreaChart,
  createMonthlyBarChart,
  createHorizontalBarChart,
  createPieChart,
  buildStackedMonthlySeries,
  buildStackedTimeSeries,
  createStackedMonthlyChart,
  createStackedAreaChart,
  loadEChartsScript,
  hasChartData,
  hasTimeSeriesData,
  hasStackedTimeSeriesData,
  showChartEmptyState,
  clearChartElement,
} from "/static/js/dashboard/common.js";
import "/static/js/common/svg-spinner.js";
import { debounce } from "/static/js/common/common.js";

/**
 * Display a tab-level spinner overlay while charts hydrate.
 * @param {string} tab - Tab key to show the spinner on.
 */
const showTabSpinner = (tab) => {
  const content = document.querySelector(`[data-analytics-content="${tab}"]`);
  if (!content) return;

  const existingSpinner = content.querySelector(".tab-spinner");
  if (!existingSpinner) {
    const spinner = document.createElement("div");
    spinner.className =
      "tab-spinner absolute inset-0 flex items-center justify-center " +
      "bg-white/80 backdrop-blur-[1px] z-10";
    spinner.innerHTML = '<svg-spinner size="size-10"></svg-spinner>';
    content.style.position = "relative";
    content.appendChild(spinner);
  }
};

/**
 * Remove the spinner overlay from a tab content area.
 * @param {string} tab - Tab key to clear the spinner from.
 */
const hideTabSpinner = (tab) => {
  const content = document.querySelector(`[data-analytics-content="${tab}"]`);
  const spinner = content?.querySelector(".tab-spinner");
  if (spinner) {
    spinner.remove();
  }
};

/**
 * Render a chart or show an empty state based on data availability.
 * @param {string} elementId - Target chart element id.
 * @param {Object} option - ECharts option object.
 * @param {boolean} hasData - Whether the chart has data to render.
 * @returns {echarts.ECharts|null} Chart instance or null.
 */
const renderChart = (elementId, option, hasData) => {
  const seriesData = option?.series?.[0]?.data || [];
  const needsTrendLine = option?.xAxis?.type === "time" && option?.series?.[0]?.type === "line";
  const canRender = hasData && (!needsTrendLine || seriesData.length >= 2);

  if (!canRender) {
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
    createAreaChart("Groups over time", "Groups", runningData, palette),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = renderChart(
    "groups-monthly-chart",
    createMonthlyBarChart("New Groups per Month", "Groups", groups.per_month, palette),
    hasChartData(groups.per_month || []),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const categoryData = toCategorySeries(groups.total_by_category || []);
  const categoryChart = renderChart(
    "groups-category-chart",
    createHorizontalBarChart("Groups by Category", categoryData, palette),
    hasChartData(categoryData),
  );
  if (categoryChart) charts.push(categoryChart);

  const regionData = toCategorySeries(groups.total_by_region || []);
  const regionChart = renderChart(
    "groups-region-chart",
    createPieChart("Groups by Region", "Groups", regionData, palette),
    hasChartData(regionData),
  );
  if (regionChart) charts.push(regionChart);

  const runningCategorySeries = buildStackedTimeSeries(groups.running_total_by_category || {}).series;
  const runningCategoryChart = renderChart(
    "groups-running-category-chart",
    createStackedAreaChart("Groups over time by category", runningCategorySeries, palette),
    hasStackedTimeSeriesData(runningCategorySeries),
  );
  if (runningCategoryChart) charts.push(runningCategoryChart);

  const runningRegionSeries = buildStackedTimeSeries(groups.running_total_by_region || {}).series;
  const runningRegionChart = renderChart(
    "groups-running-region-chart",
    createStackedAreaChart("Groups over time by region", runningRegionSeries, palette),
    hasStackedTimeSeriesData(runningRegionSeries),
  );
  if (runningRegionChart) charts.push(runningRegionChart);

  const monthlyByCategory = buildStackedMonthlySeries(groups.per_month_by_category || {});
  const monthlyCategoryChart = renderChart(
    "groups-monthly-category-chart",
    createStackedMonthlyChart(
      "New Groups per Month by category",
      monthlyByCategory.months,
      monthlyByCategory.series,
      palette,
    ),
    hasChartData(monthlyByCategory.months),
  );
  if (monthlyCategoryChart) charts.push(monthlyCategoryChart);

  const monthlyByRegion = buildStackedMonthlySeries(groups.per_month_by_region || {});
  const monthlyRegionChart = renderChart(
    "groups-monthly-region-chart",
    createStackedMonthlyChart(
      "New Groups per Month by region",
      monthlyByRegion.months,
      monthlyByRegion.series,
      palette,
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
  const monthlyByCategory = buildStackedMonthlySeries(members.per_month_by_category || {});
  const monthlyCategoryChart = renderChart(
    "members-monthly-category-chart",
    createStackedMonthlyChart(
      "New Members per Month by category",
      monthlyByCategory.months,
      monthlyByCategory.series,
      palette,
    ),
    hasChartData(monthlyByCategory.months),
  );
  if (monthlyCategoryChart) charts.push(monthlyCategoryChart);

  const monthlyByRegion = buildStackedMonthlySeries(members.per_month_by_region || {});
  const monthlyRegionChart = renderChart(
    "members-monthly-region-chart",
    createStackedMonthlyChart(
      "New Members per Month by region",
      monthlyByRegion.months,
      monthlyByRegion.series,
      palette,
    ),
    hasChartData(monthlyByRegion.months),
  );
  if (monthlyRegionChart) charts.push(monthlyRegionChart);

  const runningChart = renderChart(
    "members-running-chart",
    createAreaChart("Members over time", "Members", runningData, palette),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = renderChart(
    "members-monthly-chart",
    createMonthlyBarChart("New Members per Month", "Members", members.per_month, palette),
    hasChartData(members.per_month || []),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const categoryData = toCategorySeries(members.total_by_category || []);
  const categoryChart = renderChart(
    "members-category-chart",
    createHorizontalBarChart("Members by Group Category", categoryData, palette),
    hasChartData(categoryData),
  );
  if (categoryChart) charts.push(categoryChart);

  const regionData = toCategorySeries(members.total_by_region || []);
  const regionChart = renderChart(
    "members-region-chart",
    createPieChart("Members by Region", "Members", regionData, palette),
    hasChartData(regionData),
  );
  if (regionChart) charts.push(regionChart);

  const runningCategorySeries = buildStackedTimeSeries(members.running_total_by_category || {}).series;
  const runningCategoryChart = renderChart(
    "members-running-category-chart",
    createStackedAreaChart("Members over time by category", runningCategorySeries, palette),
    hasStackedTimeSeriesData(runningCategorySeries),
  );
  if (runningCategoryChart) charts.push(runningCategoryChart);

  const runningRegionSeries = buildStackedTimeSeries(members.running_total_by_region || {}).series;
  const runningRegionChart = renderChart(
    "members-running-region-chart",
    createStackedAreaChart("Members over time by region", runningRegionSeries, palette),
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
    createAreaChart("Events over time", "Events", runningData, palette),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = renderChart(
    "events-monthly-chart",
    createMonthlyBarChart("New Events per Month", "Events", events.per_month, palette),
    hasChartData(events.per_month || []),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const groupCategoryData = toCategorySeries(events.total_by_group_category || []);
  const groupCategoryChart = renderChart(
    "events-group-category-chart",
    createHorizontalBarChart("Events by Group Category", groupCategoryData, palette),
    hasChartData(groupCategoryData),
  );
  if (groupCategoryChart) charts.push(groupCategoryChart);

  const regionData = toCategorySeries(events.total_by_group_region || []);
  const regionChart = renderChart(
    "events-region-chart",
    createPieChart("Events by Region", "Events", regionData, palette),
    hasChartData(regionData),
  );
  if (regionChart) charts.push(regionChart);

  const categoryData = toCategorySeries(events.total_by_event_category || []);
  const categoryChart = renderChart(
    "events-category-chart",
    createHorizontalBarChart("Events by Type", categoryData, palette),
    hasChartData(categoryData),
  );
  if (categoryChart) charts.push(categoryChart);

  const runningByGroupCategory = buildStackedTimeSeries(events.running_total_by_group_category || {});
  const runningGroupCategoryChart = renderChart(
    "events-running-group-category-chart",
    createStackedAreaChart("Events over time by group category", runningByGroupCategory.series, palette),
    hasStackedTimeSeriesData(runningByGroupCategory.series),
  );
  if (runningGroupCategoryChart) charts.push(runningGroupCategoryChart);

  const runningByGroupRegion = buildStackedTimeSeries(events.running_total_by_group_region || {});
  const runningGroupRegionChart = renderChart(
    "events-running-group-region-chart",
    createStackedAreaChart("Events over time by group region", runningByGroupRegion.series, palette),
    hasStackedTimeSeriesData(runningByGroupRegion.series),
  );
  if (runningGroupRegionChart) charts.push(runningGroupRegionChart);

  const runningByEventCategory = buildStackedTimeSeries(events.running_total_by_event_category || {});
  const runningEventCategoryChart = renderChart(
    "events-running-event-category-chart",
    createStackedAreaChart("Events over time by event category", runningByEventCategory.series, palette),
    hasStackedTimeSeriesData(runningByEventCategory.series),
  );
  if (runningEventCategoryChart) charts.push(runningEventCategoryChart);

  const monthlyByGroupCategory = buildStackedMonthlySeries(events.per_month_by_group_category || {});
  const monthlyGroupCategoryChart = renderChart(
    "events-monthly-group-category-chart",
    createStackedMonthlyChart(
      "New Events per Month by group category",
      monthlyByGroupCategory.months,
      monthlyByGroupCategory.series,
      palette,
    ),
    hasChartData(monthlyByGroupCategory.months),
  );
  if (monthlyGroupCategoryChart) charts.push(monthlyGroupCategoryChart);

  const monthlyByGroupRegion = buildStackedMonthlySeries(events.per_month_by_group_region || {});
  const monthlyGroupRegionChart = renderChart(
    "events-monthly-group-region-chart",
    createStackedMonthlyChart(
      "New Events per Month by group region",
      monthlyByGroupRegion.months,
      monthlyByGroupRegion.series,
      palette,
    ),
    hasChartData(monthlyByGroupRegion.months),
  );
  if (monthlyGroupRegionChart) charts.push(monthlyGroupRegionChart);

  const monthlyByEventCategory = buildStackedMonthlySeries(events.per_month_by_event_category || {});
  const monthlyEventCategoryChart = renderChart(
    "events-monthly-event-category-chart",
    createStackedMonthlyChart(
      "New Events per Month by event category",
      monthlyByEventCategory.months,
      monthlyByEventCategory.series,
      palette,
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
    createAreaChart("Attendees over time", "Attendees", runningData, palette),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = renderChart(
    "attendees-monthly-chart",
    createMonthlyBarChart("New Attendees per Month", "Attendees", attendees.per_month, palette),
    hasChartData(attendees.per_month || []),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const categoryData = toCategorySeries(attendees.total_by_event_category || []);
  const categoryChart = renderChart(
    "attendees-category-chart",
    createHorizontalBarChart("Attendees by Event Type", categoryData, palette),
    hasChartData(categoryData),
  );
  if (categoryChart) charts.push(categoryChart);

  const regionData = toCategorySeries(attendees.total_by_group_region || []);
  const regionChart = renderChart(
    "attendees-region-chart",
    createPieChart("Attendees by Region", "Attendees", regionData, palette),
    hasChartData(regionData),
  );
  if (regionChart) charts.push(regionChart);

  const runningByGroupCategory = buildStackedTimeSeries(attendees.running_total_by_group_category || {});
  const runningGroupCategoryChart = renderChart(
    "attendees-running-group-category-chart",
    createStackedAreaChart("Attendees over time by group category", runningByGroupCategory.series, palette),
    hasStackedTimeSeriesData(runningByGroupCategory.series),
  );
  if (runningGroupCategoryChart) charts.push(runningGroupCategoryChart);

  const runningByGroupRegion = buildStackedTimeSeries(attendees.running_total_by_group_region || {});
  const runningGroupRegionChart = renderChart(
    "attendees-running-group-region-chart",
    createStackedAreaChart("Attendees over time by group region", runningByGroupRegion.series, palette),
    hasStackedTimeSeriesData(runningByGroupRegion.series),
  );
  if (runningGroupRegionChart) charts.push(runningGroupRegionChart);

  const runningByEventCategory = buildStackedTimeSeries(attendees.running_total_by_event_category || {});
  const runningEventCategoryChart = renderChart(
    "attendees-running-event-category-chart",
    createStackedAreaChart("Attendees over time by event category", runningByEventCategory.series, palette),
    hasStackedTimeSeriesData(runningByEventCategory.series),
  );
  if (runningEventCategoryChart) charts.push(runningEventCategoryChart);

  const monthlyByGroupCategory = buildStackedMonthlySeries(attendees.per_month_by_group_category || {});
  const monthlyGroupCategoryChart = renderChart(
    "attendees-monthly-group-category-chart",
    createStackedMonthlyChart(
      "New Attendees per Month by group category",
      monthlyByGroupCategory.months,
      monthlyByGroupCategory.series,
      palette,
    ),
    hasChartData(monthlyByGroupCategory.months),
  );
  if (monthlyGroupCategoryChart) charts.push(monthlyGroupCategoryChart);

  const monthlyByGroupRegion = buildStackedMonthlySeries(attendees.per_month_by_group_region || {});
  const monthlyGroupRegionChart = renderChart(
    "attendees-monthly-group-region-chart",
    createStackedMonthlyChart(
      "New Attendees per Month by group region",
      monthlyByGroupRegion.months,
      monthlyByGroupRegion.series,
      palette,
    ),
    hasChartData(monthlyByGroupRegion.months),
  );
  if (monthlyGroupRegionChart) charts.push(monthlyGroupRegionChart);

  const monthlyByEventCategory = buildStackedMonthlySeries(attendees.per_month_by_event_category || {});
  const monthlyEventCategoryChart = renderChart(
    "attendees-monthly-event-category-chart",
    createStackedMonthlyChart(
      "New Attendees per Month by event category",
      monthlyByEventCategory.months,
      monthlyByEventCategory.series,
      palette,
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
    }

    const hydratedCharts = charts.filter(Boolean);
    hydratedCharts.forEach((chart) => allCharts.add(chart));
    chartsByTab.set(tab, hydratedCharts);
    initializedTabs.add(tab);
    hideTabSpinner(tab);
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

    showTabSpinner(tab);
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

  const resizeCharts = debounce(() => {
    allCharts.forEach((chart) => chart.resize());
  }, 200);

  window.addEventListener("resize", resizeCharts);
};

/**
 * Render spinner overlays for the active analytics tab before charts are ready.
 */
export const showActiveAnalyticsSpinners = () => {
  const activeButton = document.querySelector('[data-analytics-tab][data-active="true"]');
  const tab = activeButton?.dataset.analyticsTab;
  if (tab) {
    showTabSpinner(tab);
  }
};

/**
 * Render analytics charts with lazy tab initialization.
 * @param {Object} stats - Community statistics payload from the server.
 */
export const initAnalyticsCharts = async (stats) => {
  if (!stats) {
    return;
  }

  await loadEChartsScript();
  const palette = getThemePalette();
  setupAnalyticsTabs(stats, palette);
};
