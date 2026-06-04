import { loadScriptOnce } from "/static/js/common/dom.js";

/**
 * Dispose of any existing ECharts instance on the given element.
 * @param {HTMLElement} element - Target element.
 */
const disposeChartInstance = (element) => {
  if (!element || typeof echarts === "undefined") {
    return;
  }

  const existingChart = echarts.getInstanceByDom(element);
  if (existingChart) {
    existingChart.dispose();
  }
};

/**
 * Remove empty state styling, text, and chart instances from a target element.
 * @param {string} elementId - Target element id.
 * @returns {HTMLElement|null} Cleared element or null when missing.
 */
export const clearChartElement = (elementId) => {
  const el = document.getElementById(elementId);
  if (!el) {
    return null;
  }

  disposeChartInstance(el);
  el.classList.remove("chart-empty-state");
  el.textContent = "";
  return el;
};

/**
 * Render a standard empty state for charts lacking data.
 * @param {string} elementId - Target element id.
 * @param {string} message - Empty state message.
 */
export const showChartEmptyState = (elementId, message = "No data available yet") => {
  const el = document.getElementById(elementId);
  if (!el) {
    return;
  }

  el.classList.add("chart-empty-state");
  el.textContent = message;
};

/**
 * Basic data availability check for non-time-series charts.
 * @param {Array} data - Chart data array.
 * @returns {boolean} True when data has at least one point.
 */
export const hasChartData = (data = []) => {
  return Array.isArray(data) && data.length > 0;
};

/**
 * Data availability check for time-series charts that need a trend line.
 * @param {Array} data - Time-series data array.
 * @returns {boolean} True when data has at least two points.
 */
export const hasTimeSeriesData = (data = []) => {
  return Array.isArray(data) && data.length >= 2;
};

/**
 * Data availability check for stacked time-series charts.
 * @param {Array} series - Series collection with data arrays.
 * @param {number} minPoints - Minimum points required per series.
 * @returns {boolean} True when any series satisfies the threshold.
 */
export const hasStackedTimeSeriesData = (series = [], minPoints = 2) => {
  if (!Array.isArray(series) || series.length === 0) {
    return false;
  }

  return series.some((item) => Array.isArray(item.data) && item.data.length >= minPoints);
};

/**
 * Dynamically loads the ECharts library if not already present.
 * @returns {Promise<void>} Promise that resolves when ECharts is loaded
 */
export const loadEChartsScript = () => {
  return loadScriptOnce("/static/vendor/js/echarts.v6.0.0.min.js", {
    isLoaded: () => typeof window.echarts !== "undefined",
  });
};

/**
 * Read theme colors from CSS variables to keep charts aligned with the UI palette.
 * @returns {Object} Primary color scale keyed by shade.
 */
export const getThemePalette = () => {
  const styles = getComputedStyle(document.documentElement);
  const palette = {
    50: styles.getPropertyValue("--color-primary-50").trim(),
    100: styles.getPropertyValue("--color-primary-100").trim(),
    200: styles.getPropertyValue("--color-primary-200").trim(),
    300: styles.getPropertyValue("--color-primary-300").trim(),
    400: styles.getPropertyValue("--color-primary-400").trim(),
    500: styles.getPropertyValue("--color-primary-500").trim(),
    600: styles.getPropertyValue("--color-primary-600").trim(),
    700: styles.getPropertyValue("--color-primary-700").trim(),
    800: styles.getPropertyValue("--color-primary-800").trim(),
    900: styles.getPropertyValue("--color-primary-900").trim(),
    950: styles.getPropertyValue("--color-primary-950").trim(),
  };

  const fallback = palette[700] || palette[500];
  Object.entries(palette).forEach(([key, value]) => {
    if (!value) {
      palette[key] = fallback;
    }
  });

  return palette;
};

/** Typography family shared across charts. */
export const dashboardFontFamily =
  '"Inter", "ui-sans-serif", "system-ui", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "sans-serif"';

/**
 * Cast stats tuples into ECharts-friendly time series.
 * @param {Array<[number|string, number|string]>} points - Timestamp/value pairs.
 * @returns {Array<[number, number]>} Normalized series.
 */
export const toTimeSeries = (points = []) => {
  return points.map(([ts, value]) => [Number(ts), Number(value)]);
};

const shortMonthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/**
 * Build a YYYY-MM-DD key for recent daily series lookups.
 * @param {Date} date - Source date.
 * @returns {string} Daily bucket key.
 */
const formatRecentDayKey = (date) => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

/**
 * Build a YYYY-MM key for recent monthly series lookups.
 * @param {Date} date - Source month.
 * @returns {string} Monthly bucket key.
 */
const formatRecentMonthKey = (date) => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
};

/**
 * Format a day bucket label for recent daily charts.
 * @param {Date} date - Source date.
 * @returns {string} Label in DD Mon format.
 */
const formatRecentDayLabel = (date) => {
  return `${String(date.getDate()).padStart(2, "0")} ${shortMonthNames[date.getMonth()]}`;
};

/**
 * Format a month bucket label for recent monthly charts.
 * @param {Date} date - Source month.
 * @returns {string} Label in Mon'YY format.
 */
const formatRecentMonthLabel = (date) => {
  return `${shortMonthNames[date.getMonth()]}'${String(date.getFullYear()).slice(-2)}`;
};

/**
 * Normalize raw YYYY-MM labels to the shared month axis format.
 * @param {string} value - Raw month value.
 * @returns {string} Formatted month label.
 */
const formatMonthAxisLabel = (value) => {
  if (typeof value !== "string") {
    return value;
  }

  const parts = value.match(/^(\d{4})-(\d{2})$/);
  if (!parts) {
    return value;
  }

  const monthIndex = Number(parts[2]) - 1;
  if (monthIndex < 0 || monthIndex >= shortMonthNames.length) {
    return value;
  }

  return `${shortMonthNames[monthIndex]}'${parts[1].slice(-2)}`;
};

/**
 * Build consecutive recent month entries ending in the current month.
 * @param {number} count - Number of months to generate.
 * @returns {Array<{key: string, label: string}>} Month keys and labels.
 */
const buildRecentMonthEntries = (count) => {
  const now = new Date();

  return Array.from({ length: count }, (_, index) => {
    const offset = count - index - 1;
    const date = new Date(now.getFullYear(), now.getMonth() - offset, 1);

    return {
      key: formatRecentMonthKey(date),
      label: formatRecentMonthLabel(date),
    };
  });
};

/**
 * Decide whether a sparse axis label should be shown.
 * @param {number} index - Current label index.
 * @param {number} total - Total labels available.
 * @param {number} targetCount - Approximate visible label count.
 * @returns {boolean} True when the label should be rendered.
 */
const shouldShowSparseAxisLabel = (index, total, targetCount) => {
  if (index === 0 || index === total - 1) {
    return true;
  }

  const step = Math.max(1, Math.ceil(total / targetCount));
  return index % step === 0;
};

/**
 * Build a recent day or month series with zero-filled gaps.
 * @param {Array<[string, number|string]>} points - Raw key/value pairs.
 * @param {"day"|"month"} unit - Series unit.
 * @param {number} defaultCount - Default period size.
 * @param {Object} options - Series options.
 * @param {boolean} options.useFormattedMonthLabels - Use short month labels for monthly categories.
 * @param {boolean} options.reservePeriodStart - Reserve empty buckets from the recent period start.
 * @returns {{categories: Array<string>, values: Array<number>}} Filled series.
 */
export const buildRecentBarSeries = (points = [], unit, defaultCount, options = {}) => {
  const { useFormattedMonthLabels = true, reservePeriodStart = true } = options;

  if (!reservePeriodStart) {
    return {
      categories: (points || []).map(([key]) =>
        unit === "month" && useFormattedMonthLabels ? formatMonthAxisLabel(key) : key,
      ),
      values: (points || []).map(([, value]) => Number(value)),
    };
  }

  const count = defaultCount;
  const valuesByKey = new Map((points || []).map(([key, value]) => [key, Number(value)]));
  const categories = [];
  const values = [];

  if (unit === "month") {
    buildRecentMonthEntries(count).forEach(({ key, label }) => {
      categories.push(useFormattedMonthLabels ? label : key);
      values.push(valuesByKey.get(key) ?? 0);
    });

    return { categories, values };
  }

  const now = new Date();
  for (let offset = count - 1; offset >= 0; offset -= 1) {
    const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset);

    categories.push(formatRecentDayLabel(date));
    values.push(valuesByKey.get(formatRecentDayKey(date)) ?? 0);
  }

  return { categories, values };
};

/**
 * Read a neutral color for chart grid lines.
 * @returns {string} Grid line color.
 */
export const getChartGridLineColor = () => {
  return getComputedStyle(document.documentElement).getPropertyValue("--color-stone-100").trim();
};

/**
 * Read neutral tooltip colors.
 * @returns {{background: string, border: string, text: string}} Tooltip colors.
 */
export const getChartTooltipColors = () => {
  const styles = getComputedStyle(document.documentElement);

  return {
    background: styles.getPropertyValue("--color-white").trim(),
    border: styles.getPropertyValue("--color-stone-200").trim(),
    text: styles.getPropertyValue("--color-stone-700").trim(),
  };
};

/**
 * Read neutral chart UI colors.
 * @returns {{text: string, muted: string, soft: string, surface: string}} UI colors.
 */
export const getChartUiColors = () => {
  const styles = getComputedStyle(document.documentElement);

  return {
    text: styles.getPropertyValue("--color-stone-700").trim(),
    muted: styles.getPropertyValue("--color-stone-400").trim(),
    soft: styles.getPropertyValue("--color-stone-300").trim(),
    surface: styles.getPropertyValue("--color-white").trim(),
  };
};

/**
 * Build a shared chart title configuration.
 * @param {string} title - Chart title text.
 * @param {Object} palette - Theme color palette.
 * @param {string} description - Short chart description.
 * @returns {Object} ECharts title config.
 */
export const getChartTitleConfig = (title, palette, description = "") => {
  const uiColors = getChartUiColors();
  const config = {
    text: title,
    left: "center",
    top: 12,
    textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: palette[950] },
  };

  if (description) {
    config.subtext = description;
    config.itemGap = 6;
    config.subtextStyle = {
      color: uiColors.muted,
      fontFamily: dashboardFontFamily,
      fontSize: 12,
      lineHeight: 16,
    };
  }

  return config;
};

/**
 * Leave extra room when chart titles include a one-line description.
 * @param {string} description - Short chart description.
 * @param {number} top - Base grid top padding.
 * @returns {number} Adjusted grid top padding.
 */
const getChartGridTop = (description, top = 80) => {
  return description ? top + 20 : top;
};

/**
 * Build a shared axis tooltip configuration.
 * @returns {Object} ECharts tooltip config.
 */
export const getAxisTooltipConfig = () => {
  const tooltipColors = getChartTooltipColors();

  return {
    trigger: "axis",
    backgroundColor: tooltipColors.background,
    borderColor: tooltipColors.border,
    borderWidth: 1,
    textStyle: { color: tooltipColors.text },
  };
};

/**
 * Build a shared item tooltip configuration.
 * @returns {Object} ECharts tooltip config.
 */
export const getItemTooltipConfig = () => {
  const tooltipColors = getChartTooltipColors();

  return {
    trigger: "item",
    backgroundColor: tooltipColors.background,
    borderColor: tooltipColors.border,
    borderWidth: 1,
    textStyle: { color: tooltipColors.text },
  };
};

/**
 * Build a shared numeric axis configuration.
 * @returns {Object} ECharts value axis config.
 */
export const getValueAxisConfig = () => {
  return {
    type: "value",
    minInterval: 1,
    axisLine: { show: false },
    axisTick: { show: false },
    axisLabel: { fontSize: 11 },
    splitLine: { lineStyle: { color: getChartGridLineColor(), type: "dashed" } },
  };
};

/**
 * Build a shared category x-axis configuration for vertical bar charts.
 * @param {Array<string>} categories - Axis categories.
 * @returns {Object} ECharts category axis config.
 */
export const getVerticalBarCategoryAxisConfig = (categories = []) => {
  return {
    type: "category",
    data: categories,
    axisLine: { show: false },
    axisTick: { show: false },
    axisLabel: {
      fontSize: 10,
      formatter: (value, index) => {
        return shouldShowSparseAxisLabel(index, categories.length, 8) ? value : "";
      },
    },
    splitLine: { show: false },
  };
};

/**
 * Shared sizing rules for vertical bar charts.
 * @param {number} count - Number of categories.
 * @returns {Object} Bar sizing options.
 */
export const getVerticalBarSeriesStyle = (count = 0) => {
  const hasDenseSeries = count > 36;
  const isVeryDenseSeries = count > 72;

  return {
    barMaxWidth: isVeryDenseSeries ? 8 : hasDenseSeries ? 11 : 35,
    ...(hasDenseSeries ? {} : { barMinWidth: 12 }),
    barCategoryGap: isVeryDenseSeries ? "35%" : hasDenseSeries ? "45%" : "30%",
  };
};

/**
 * Normalize category/value tuples for charts.
 * @param {Array<[string, number|string]>} pairs - Category/value pairs.
 * @returns {Array<{name: string, value: number}>} Labeled series.
 */
export const toCategorySeries = (pairs = []) => {
  return pairs.map(([label, value]) => ({ name: label, value: Number(value) }));
};

/**
 * Initialize an ECharts instance if the element and library are available.
 * @param {string} elementId - Target element id.
 * @param {Object} option - ECharts option object.
 * @returns {echarts.ECharts | null} Chart instance or null when unavailable.
 */
export const initChart = (elementId, option) => {
  const el = document.getElementById(elementId);
  if (!el || typeof echarts === "undefined") {
    return null;
  }

  el.innerHTML = "";
  const chart = echarts.init(el);
  chart.setOption(option);
  return chart;
};

/**
 * Shared typography configuration for charts.
 * @returns {Object} Text styling options.
 */
export const baseText = () => {
  return {
    textStyle: { fontFamily: dashboardFontFamily },
    legend: { textStyle: { fontFamily: dashboardFontFamily } },
    tooltip: { textStyle: { fontFamily: dashboardFontFamily } },
  };
};

/**
 * Create area chart configuration for running totals.
 * @param {string} title - Chart title.
 * @param {string} name - Series name.
 * @param {Array} data - Time series data.
 * @param {Object} palette - Theme color palette.
 * @param {Object} options - Chart options.
 * @param {string} options.description - Short chart description.
 * @returns {Object} ECharts option.
 */
export const createAreaChart = (title, name, data, palette, options = {}) => {
  const { description = "" } = options;

  return {
    baseOption: Object.assign(baseText(), {
      title: getChartTitleConfig(title, palette, description),
      color: [palette[700]],
      tooltip: getAxisTooltipConfig(),
      grid: { left: 70, right: 40, bottom: 90, top: getChartGridTop(description) },
      xAxis: {
        type: "time",
        boundaryGap: false,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { fontSize: 11 },
        splitLine: { show: false },
      },
      yAxis: getValueAxisConfig(),
      series: [
        {
          name,
          type: "line",
          smooth: true,
          symbol: "none",
          showSymbol: false,
          lineStyle: { width: 2, color: palette[700] },
          areaStyle: {
            color: {
              type: "linear",
              x: 0,
              y: 0,
              x2: 0,
              y2: 1,
              colorStops: [
                { offset: 0, color: palette[500] },
                { offset: 1, color: "rgba(255, 255, 255, 0)" },
              ],
            },
          },
          data: toTimeSeries(data),
        },
      ],
    }),
    media: [
      {
        query: { maxWidth: 500 },
        option: { xAxis: { axisLabel: { rotate: 45 } } },
      },
    ],
  };
};

/**
 * Create vertical bar chart configuration for monthly data.
 * @param {string} title - Chart title.
 * @param {string} name - Series name.
 * @param {Array} data - Monthly data pairs.
 * @param {Object} palette - Theme color palette.
 * @param {Object} options - Chart options.
 * @param {string} options.description - Short chart description.
 * @param {number} options.recentWindowMonths - Number of months to display on the axis.
 * @param {boolean} options.reservePeriodStart - Reserve empty buckets from the recent period start.
 * @returns {Object} ECharts option.
 */
export const createMonthlyBarChart = (title, name, data, palette, options = {}) => {
  const { description = "", recentWindowMonths = 24, reservePeriodStart = false } = options;
  const filledSeries = buildRecentBarSeries(data, "month", recentWindowMonths, {
    useFormattedMonthLabels: true,
    reservePeriodStart,
  });
  const barSeriesStyle = getVerticalBarSeriesStyle(filledSeries.values.length);

  return Object.assign(baseText(), {
    title: getChartTitleConfig(title, palette, description),
    color: [palette[700]],
    tooltip: getAxisTooltipConfig(),
    legend: {
      bottom: 10,
      left: "center",
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 12 },
    },
    grid: { left: 70, right: 40, bottom: 100, top: getChartGridTop(description) },
    xAxis: getVerticalBarCategoryAxisConfig(filledSeries.categories),
    yAxis: getValueAxisConfig(),
    series: [
      {
        name,
        type: "bar",
        data: filledSeries.values,
        ...barSeriesStyle,
      },
    ],
  });
};
