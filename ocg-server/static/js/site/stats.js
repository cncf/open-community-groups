import {
  createAreaChart,
  createMonthlyBarChart,
  dashboardFontFamily,
  getThemePalette,
  getChartUiColors,
  hasChartData,
  hasTimeSeriesData,
  loadEChartsScript,
} from "/static/js/common/charts/charts.js";
import {
  getCategoryLabelInterval,
  getTimeSplitNumber,
  initializeChartsFromJsonMarker,
  renderChart,
} from "/static/js/common/charts/stats.js";
import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";
import { PHONE_MEDIA_QUERY, isPhoneViewport } from "/static/js/common/phone-viewport.js";

const PHONE_CHART_GRID = { left: 8, right: 24, top: 56, bottom: 8, containLabel: true };
const PHONE_MONTHLY_LABEL_TARGET = 4;
const PHONE_VALUE_FORMAT = new Intl.NumberFormat("en", { notation: "compact" });
const SITE_STATS_DATA_SELECTOR = "[data-site-stats]";
const SITE_STATS_READY_KEY = "siteStatsReady";

/** Latest stats payload, kept so a phone-boundary change can re-render the charts. */
let latestSiteStats = null;

/** Media query watched to re-render when the viewport crosses the phone layout boundary. */
let phoneViewportQuery = null;

/** Whether a render is in progress, so overlapping requests coalesce instead of racing. */
let siteStatsRendering = false;

/** Whether a render was requested while one was in progress. */
let siteStatsRenderQueued = false;

/**
 * Apply public stats page legend styling without affecting dashboard charts.
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
 * Builds plain phone options: no legend, and no media rule rotating the x labels.
 * @param {Object} option - ECharts option object.
 * @returns {Object} Phone ECharts option.
 */
const getPhoneChartOption = (option) => {
  const plainOption = option.baseOption || option;

  return {
    ...plainOption,
    grid: PHONE_CHART_GRID,
    legend: { show: false },
    yAxis: {
      ...plainOption.yAxis,
      axisLabel: {
        ...plainOption.yAxis?.axisLabel,
        fontSize: 10,
        formatter: (value) => PHONE_VALUE_FORMAT.format(value),
      },
    },
  };
};

/**
 * Applies the phone x-axis on top of a chart's own axis settings.
 * @param {Object} option - ECharts option object.
 * @returns {Object} ECharts option with the phone x-axis.
 */
const withPhoneXAxis = (option) => ({
  ...option,
  xAxis: {
    ...option.xAxis,
    axisLabel: { ...option.xAxis?.axisLabel, fontSize: 10, hideOverlap: true, rotate: 0 },
    splitNumber: 4,
  },
});

/**
 * Returns the target number of visible monthly x-axis labels for the viewport.
 * @returns {number} Visible label target.
 */
const getMonthlyLabelTarget = () => {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return 8;
  }

  if (isPhoneViewport()) {
    return PHONE_MONTHLY_LABEL_TARGET;
  }

  return window.matchMedia("(max-width: 640px)").matches ? 4 : 8;
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
  const isPhone = isPhoneViewport();
  const styleOption = isPhone ? getPhoneChartOption : styleStatsPageLegend;
  const finishOption = isPhone ? withPhoneXAxis : (option) => option;

  const runningData = section.running_total || [];
  const runningOption = styleOption(createAreaChart(`${label} over time`, label, runningData, palette));
  runningOption.xAxis = Object.assign({}, runningOption.xAxis, {
    axisLabel: Object.assign({}, runningOption.xAxis?.axisLabel, {
      formatter: "{yyyy}-{MM}",
      hideOverlap: true,
    }),
    splitNumber: getTimeSplitNumber(runningData.length),
  });
  const runningChart = renderChart(
    `${key}-running-chart`,
    finishOption(runningOption),
    hasTimeSeriesData(runningData),
  );
  if (runningChart) charts.push(runningChart);

  const monthlyData = section.per_month || [];
  const monthlyOption = styleOption(
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
  const monthlyChart = renderChart(
    `${key}-monthly-chart`,
    finishOption(monthlyOption),
    hasChartData(monthlyData),
  );
  if (monthlyChart) charts.push(monthlyChart);

  return charts;
};

/**
 * Re-renders the stats charts when the viewport crosses the phone layout boundary. The layout is
 * chosen per render from `isPhoneViewport()`, so a rotation or resize across the boundary would
 * otherwise keep the previous layout until the next full render.
 * @returns {void}
 */
const handlePhoneViewportChange = () => {
  if (!latestSiteStats || !document.querySelector(SITE_STATS_DATA_SELECTOR)) {
    return;
  }

  void initSiteStatsCharts(latestSiteStats);
};

/**
 * Watches the phone media query, rebinding so a single listener stays registered across reloads.
 * @returns {void}
 */
const watchPhoneViewport = () => {
  if (typeof window.matchMedia !== "function") {
    return;
  }

  phoneViewportQuery?.removeEventListener("change", handlePhoneViewportChange);
  phoneViewportQuery = window.matchMedia(PHONE_MEDIA_QUERY);
  phoneViewportQuery.addEventListener("change", handlePhoneViewportChange);
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

  latestSiteStats = stats;
  watchPhoneViewport();

  if (siteStatsRendering) {
    siteStatsRenderQueued = true;
    return;
  }

  siteStatsRendering = true;
  try {
    await loadEChartsScript();
    const sections = [
      { key: "groups", label: "Groups" },
      { key: "members", label: "Members" },
      { key: "events", label: "Events" },
      { key: "attendees", label: "Attendees" },
    ];

    do {
      siteStatsRenderQueued = false;
      const palette = getThemePalette();
      for (const section of sections) {
        await initSectionCharts(section.key, section.label, latestSiteStats, palette);
      }
    } while (siteStatsRenderQueued);
  } finally {
    siteStatsRendering = false;
  }
};

/**
 * Initialize site stats charts from the page JSON marker.
 * @param {Document|Element} root - Root element to search from.
 * @param {Object} context - Initialization lifecycle context.
 * @returns {Promise<void>} Promise resolved when initialization finishes.
 */
export const initializeSiteStatsFromPage = async (root = document, context = {}) => {
  return initializeChartsFromJsonMarker({
    root,
    selector: SITE_STATS_DATA_SELECTOR,
    readyKey: SITE_STATS_READY_KEY,
    initialize: initSiteStatsCharts,
    parseErrorMessage: "Failed to parse site stats payload:",
    initErrorMessage: "Failed to initialize site stats charts:",
    force: context.historyRestore === true,
  });
};

initializeOnReadyAndHtmxLoad(initializeSiteStatsFromPage);
