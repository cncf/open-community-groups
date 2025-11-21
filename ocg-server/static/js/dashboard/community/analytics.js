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
} from "/static/js/dashboard/common.js";
import "/static/js/common/svg-spinner.js";
import { debounce } from "/static/js/common/common.js";

function showTabSpinner(tab) {
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
}

function hideTabSpinner(tab) {
  const content = document.querySelector(`[data-analytics-content="${tab}"]`);
  const spinner = content?.querySelector(".tab-spinner");
  if (spinner) {
    spinner.remove();
  }
}

/**
 * Render groups charts.
 * @param {Object} groups - Group stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
async function initGroupsCharts(groups = {}, palette) {
  await loadEChartsScript();

  const charts = [];

  const runningChart = initChart(
    "groups-running-chart",
    createAreaChart("Groups over time", "Groups", groups.running_total || [], palette),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = initChart(
    "groups-monthly-chart",
    createMonthlyBarChart("New Groups per Month", "Groups", groups.per_month, palette),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const categoryChart = initChart(
    "groups-category-chart",
    createHorizontalBarChart("Groups by Category", toCategorySeries(groups.total_by_category || []), palette),
  );
  if (categoryChart) charts.push(categoryChart);

  const regionChart = initChart(
    "groups-region-chart",
    createPieChart("Groups by Region", "Groups", toCategorySeries(groups.total_by_region || []), palette),
  );
  if (regionChart) charts.push(regionChart);

  const runningCategoryChart = initChart(
    "groups-running-category-chart",
    createStackedAreaChart(
      "Groups over time by category",
      buildStackedTimeSeries(groups.running_total_by_category || {}).series,
      palette,
    ),
  );
  if (runningCategoryChart) charts.push(runningCategoryChart);

  const runningRegionChart = initChart(
    "groups-running-region-chart",
    createStackedAreaChart(
      "Groups over time by region",
      buildStackedTimeSeries(groups.running_total_by_region || {}).series,
      palette,
    ),
  );
  if (runningRegionChart) charts.push(runningRegionChart);

  const monthlyByCategory = buildStackedMonthlySeries(groups.per_month_by_category || {});
  const monthlyCategoryChart = initChart(
    "groups-monthly-category-chart",
    createStackedMonthlyChart(
      "New Groups per Month by category",
      monthlyByCategory.months,
      monthlyByCategory.series,
      palette,
    ),
  );
  if (monthlyCategoryChart) charts.push(monthlyCategoryChart);

  const monthlyByRegion = buildStackedMonthlySeries(groups.per_month_by_region || {});
  const monthlyRegionChart = initChart(
    "groups-monthly-region-chart",
    createStackedMonthlyChart(
      "New Groups per Month by region",
      monthlyByRegion.months,
      monthlyByRegion.series,
      palette,
    ),
  );
  if (monthlyRegionChart) charts.push(monthlyRegionChart);

  return charts;
}

/**
 * Render members charts.
 * @param {Object} members - Member stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
async function initMembersCharts(members = {}, palette) {
  await loadEChartsScript();

  const charts = [];

  const monthlyByCategory = buildStackedMonthlySeries(members.per_month_by_category || {});
  const monthlyCategoryChart = initChart(
    "members-monthly-category-chart",
    createStackedMonthlyChart(
      "New Members per Month by category",
      monthlyByCategory.months,
      monthlyByCategory.series,
      palette,
    ),
  );
  if (monthlyCategoryChart) charts.push(monthlyCategoryChart);

  const monthlyByRegion = buildStackedMonthlySeries(members.per_month_by_region || {});
  const monthlyRegionChart = initChart(
    "members-monthly-region-chart",
    createStackedMonthlyChart(
      "New Members per Month by region",
      monthlyByRegion.months,
      monthlyByRegion.series,
      palette,
    ),
  );
  if (monthlyRegionChart) charts.push(monthlyRegionChart);

  const runningChart = initChart(
    "members-running-chart",
    createAreaChart("Members over time", "Members", members.running_total || [], palette),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = initChart(
    "members-monthly-chart",
    createMonthlyBarChart("New Members per Month", "Members", members.per_month, palette),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const categoryChart = initChart(
    "members-category-chart",
    createHorizontalBarChart(
      "Members by Group Category",
      toCategorySeries(members.total_by_category || []),
      palette,
    ),
  );
  if (categoryChart) charts.push(categoryChart);

  const regionChart = initChart(
    "members-region-chart",
    createPieChart("Members by Region", "Members", toCategorySeries(members.total_by_region || []), palette),
  );
  if (regionChart) charts.push(regionChart);

  const runningCategoryChart = initChart(
    "members-running-category-chart",
    createStackedAreaChart(
      "Members over time by category",
      buildStackedTimeSeries(members.running_total_by_category || {}).series,
      palette,
    ),
  );
  if (runningCategoryChart) charts.push(runningCategoryChart);

  const runningRegionChart = initChart(
    "members-running-region-chart",
    createStackedAreaChart(
      "Members over time by region",
      buildStackedTimeSeries(members.running_total_by_region || {}).series,
      palette,
    ),
  );
  if (runningRegionChart) charts.push(runningRegionChart);

  return charts;
}

/**
 * Render events charts.
 * @param {Object} events - Event stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
async function initEventsCharts(events = {}, palette) {
  await loadEChartsScript();

  const charts = [];

  const runningChart = initChart(
    "events-running-chart",
    createAreaChart("Events over time", "Events", events.running_total || [], palette),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = initChart(
    "events-monthly-chart",
    createMonthlyBarChart("New Events per Month", "Events", events.per_month, palette),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const groupCategoryChart = initChart(
    "events-group-category-chart",
    createHorizontalBarChart(
      "Events by Group Category",
      toCategorySeries(events.total_by_group_category || []),
      palette,
    ),
  );
  if (groupCategoryChart) charts.push(groupCategoryChart);

  const regionChart = initChart(
    "events-region-chart",
    createPieChart(
      "Events by Region",
      "Events",
      toCategorySeries(events.total_by_group_region || []),
      palette,
    ),
  );
  if (regionChart) charts.push(regionChart);

  const categoryChart = initChart(
    "events-category-chart",
    createHorizontalBarChart(
      "Events by Type",
      toCategorySeries(events.total_by_event_category || []),
      palette,
    ),
  );
  if (categoryChart) charts.push(categoryChart);

  const runningByGroupCategory = buildStackedTimeSeries(events.running_total_by_group_category || {});
  const runningGroupCategoryChart = initChart(
    "events-running-group-category-chart",
    createStackedAreaChart("Events over time by group category", runningByGroupCategory.series, palette),
  );
  if (runningGroupCategoryChart) charts.push(runningGroupCategoryChart);

  const runningByGroupRegion = buildStackedTimeSeries(events.running_total_by_group_region || {});
  const runningGroupRegionChart = initChart(
    "events-running-group-region-chart",
    createStackedAreaChart("Events over time by group region", runningByGroupRegion.series, palette),
  );
  if (runningGroupRegionChart) charts.push(runningGroupRegionChart);

  const runningByEventCategory = buildStackedTimeSeries(events.running_total_by_event_category || {});
  const runningEventCategoryChart = initChart(
    "events-running-event-category-chart",
    createStackedAreaChart("Events over time by event category", runningByEventCategory.series, palette),
  );
  if (runningEventCategoryChart) charts.push(runningEventCategoryChart);

  const monthlyByGroupCategory = buildStackedMonthlySeries(events.per_month_by_group_category || {});
  const monthlyGroupCategoryChart = initChart(
    "events-monthly-group-category-chart",
    createStackedMonthlyChart(
      "New Events per Month by group category",
      monthlyByGroupCategory.months,
      monthlyByGroupCategory.series,
      palette,
    ),
  );
  if (monthlyGroupCategoryChart) charts.push(monthlyGroupCategoryChart);

  const monthlyByGroupRegion = buildStackedMonthlySeries(events.per_month_by_group_region || {});
  const monthlyGroupRegionChart = initChart(
    "events-monthly-group-region-chart",
    createStackedMonthlyChart(
      "New Events per Month by group region",
      monthlyByGroupRegion.months,
      monthlyByGroupRegion.series,
      palette,
    ),
  );
  if (monthlyGroupRegionChart) charts.push(monthlyGroupRegionChart);

  const monthlyByEventCategory = buildStackedMonthlySeries(events.per_month_by_event_category || {});
  const monthlyEventCategoryChart = initChart(
    "events-monthly-event-category-chart",
    createStackedMonthlyChart(
      "New Events per Month by event category",
      monthlyByEventCategory.months,
      monthlyByEventCategory.series,
      palette,
    ),
  );
  if (monthlyEventCategoryChart) charts.push(monthlyEventCategoryChart);

  return charts;
}

/**
 * Render attendees charts.
 * @param {Object} attendees - Attendee stats payload.
 * @param {Object} palette - Theme palette.
 * @returns {Array<echarts.ECharts>} Initialized charts.
 */
async function initAttendeesCharts(attendees = {}, palette) {
  await loadEChartsScript();

  const charts = [];

  const runningChart = initChart(
    "attendees-running-chart",
    createAreaChart("Attendees over time", "Attendees", attendees.running_total || [], palette),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyChart = initChart(
    "attendees-monthly-chart",
    createMonthlyBarChart("New Attendees per Month", "Attendees", attendees.per_month, palette),
  );
  if (monthlyChart) charts.push(monthlyChart);

  const categoryChart = initChart(
    "attendees-category-chart",
    createHorizontalBarChart(
      "Attendees by Event Type",
      toCategorySeries(attendees.total_by_event_category || []),
      palette,
    ),
  );
  if (categoryChart) charts.push(categoryChart);

  const regionChart = initChart(
    "attendees-region-chart",
    createPieChart(
      "Attendees by Region",
      "Attendees",
      toCategorySeries(attendees.total_by_group_region || []),
      palette,
    ),
  );
  if (regionChart) charts.push(regionChart);

  const runningByGroupCategory = buildStackedTimeSeries(attendees.running_total_by_group_category || {});
  const runningGroupCategoryChart = initChart(
    "attendees-running-group-category-chart",
    createStackedAreaChart("Attendees over time by group category", runningByGroupCategory.series, palette),
  );
  if (runningGroupCategoryChart) charts.push(runningGroupCategoryChart);

  const runningByGroupRegion = buildStackedTimeSeries(attendees.running_total_by_group_region || {});
  const runningGroupRegionChart = initChart(
    "attendees-running-group-region-chart",
    createStackedAreaChart("Attendees over time by group region", runningByGroupRegion.series, palette),
  );
  if (runningGroupRegionChart) charts.push(runningGroupRegionChart);

  const runningByEventCategory = buildStackedTimeSeries(attendees.running_total_by_event_category || {});
  const runningEventCategoryChart = initChart(
    "attendees-running-event-category-chart",
    createStackedAreaChart("Attendees over time by event category", runningByEventCategory.series, palette),
  );
  if (runningEventCategoryChart) charts.push(runningEventCategoryChart);

  const monthlyByGroupCategory = buildStackedMonthlySeries(attendees.per_month_by_group_category || {});
  const monthlyGroupCategoryChart = initChart(
    "attendees-monthly-group-category-chart",
    createStackedMonthlyChart(
      "New Attendees per Month by group category",
      monthlyByGroupCategory.months,
      monthlyByGroupCategory.series,
      palette,
    ),
  );
  if (monthlyGroupCategoryChart) charts.push(monthlyGroupCategoryChart);

  const monthlyByGroupRegion = buildStackedMonthlySeries(attendees.per_month_by_group_region || {});
  const monthlyGroupRegionChart = initChart(
    "attendees-monthly-group-region-chart",
    createStackedMonthlyChart(
      "New Attendees per Month by group region",
      monthlyByGroupRegion.months,
      monthlyByGroupRegion.series,
      palette,
    ),
  );
  if (monthlyGroupRegionChart) charts.push(monthlyGroupRegionChart);

  const monthlyByEventCategory = buildStackedMonthlySeries(attendees.per_month_by_event_category || {});
  const monthlyEventCategoryChart = initChart(
    "attendees-monthly-event-category-chart",
    createStackedMonthlyChart(
      "New Attendees per Month by event category",
      monthlyByEventCategory.months,
      monthlyByEventCategory.series,
      palette,
    ),
  );
  if (monthlyEventCategoryChart) charts.push(monthlyEventCategoryChart);

  return charts;
}

function setupAnalyticsTabs(stats, palette) {
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
}

/**
 * Render spinner overlays for the active analytics tab before charts are ready.
 */
export function showActiveAnalyticsSpinners() {
  const activeButton = document.querySelector('[data-analytics-tab][data-active="true"]');
  const tab = activeButton?.dataset.analyticsTab;
  if (tab) {
    showTabSpinner(tab);
  }
}

/**
 * Render analytics charts with lazy tab initialization.
 * @param {Object} stats - Community statistics payload from the server.
 */
export async function initAnalyticsCharts(stats) {
  if (!stats) {
    return;
  }

  await loadEChartsScript();
  const palette = getThemePalette();
  setupAnalyticsTabs(stats, palette);
}
