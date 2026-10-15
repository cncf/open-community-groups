import { getElementById, loadScriptOnce } from "/static/js/common/dom.js";
import { escapeHtml } from "/static/js/common/trusted-html.js";

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
  const el = getElementById(document, elementId);
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
  const el = getElementById(document, elementId);
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
 * Activity check for counts or key/count pairs.
 * @param {Array<number|[string|number, number|string]>} values - Counts or key/count pairs.
 * @returns {boolean} True when any count is not zero.
 */
export const hasActivity = (values = []) => {
  return (
    Array.isArray(values) &&
    values.some((value) => {
      const count = Array.isArray(value) ? value[1] : value;
      return Number(count) !== 0 && !Number.isNaN(Number(count));
    })
  );
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
  return loadScriptOnce("/static/vendor/js/echarts.v6.1.0.min.js", {
    isLoaded: () => typeof window.echarts !== "undefined",
  });
};

const ECHARTS_COLOR_PATTERN = /^(#|rgba?\(|hsla?\()/i;
const chartColorCache = new Map();
let chartColorContext = null;

/**
 * Convert a CSS color into a format ECharts can parse. ECharts derives hover
 * and blur colors itself and leaves elements transparent for formats it does
 * not understand, such as the oklch values of the Tailwind palette.
 * @param {string} value - CSS color value.
 * @returns {string} Color in a format ECharts can parse, or the original value.
 */
export const toChartColor = (value) => {
  if (!value || ECHARTS_COLOR_PATTERN.test(value) || !globalThis.CSS?.supports?.("color", value)) {
    return value;
  }
  if (chartColorCache.has(value)) {
    return chartColorCache.get(value);
  }

  if (!chartColorContext) {
    const canvas = document.createElement("canvas");
    canvas.width = 1;
    canvas.height = 1;
    chartColorContext = canvas.getContext("2d", { willReadFrequently: true });
  }
  if (!chartColorContext) {
    return value;
  }

  // Paint the color and read back its sRGB channels
  chartColorContext.clearRect(0, 0, 1, 1);
  chartColorContext.fillStyle = value;
  chartColorContext.fillRect(0, 0, 1, 1);
  const [red, green, blue, alpha] = chartColorContext.getImageData(0, 0, 1, 1).data;
  const color =
    alpha === 255
      ? `rgb(${red}, ${green}, ${blue})`
      : `rgba(${red}, ${green}, ${blue}, ${Number((alpha / 255).toFixed(3))})`;
  chartColorCache.set(value, color);
  return color;
};

/**
 * Read a CSS color variable in a format ECharts can parse.
 * @param {CSSStyleDeclaration} styles - Computed styles of the root element.
 * @param {string} name - CSS custom property name.
 * @returns {string} Chart color, or an empty string when unset.
 */
const readChartColor = (styles, name) => toChartColor(styles.getPropertyValue(name).trim());

/**
 * Read theme colors from CSS variables to keep charts aligned with the UI palette.
 * @returns {Object} Primary color scale keyed by shade.
 */
export const getThemePalette = () => {
  const styles = getComputedStyle(document.documentElement);
  const palette = {
    50: readChartColor(styles, "--color-primary-50"),
    100: readChartColor(styles, "--color-primary-100"),
    200: readChartColor(styles, "--color-primary-200"),
    300: readChartColor(styles, "--color-primary-300"),
    400: readChartColor(styles, "--color-primary-400"),
    500: readChartColor(styles, "--color-primary-500"),
    600: readChartColor(styles, "--color-primary-600"),
    700: readChartColor(styles, "--color-primary-700"),
    800: readChartColor(styles, "--color-primary-800"),
    900: readChartColor(styles, "--color-primary-900"),
    950: readChartColor(styles, "--color-primary-950"),
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
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

/**
 * Build a YYYY-MM key for recent monthly series lookups.
 * @param {Date} date - Source month.
 * @returns {string} Monthly bucket key.
 */
const formatRecentMonthKey = (date) => {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
};

/**
 * Format a day bucket label for recent daily charts.
 * @param {Date} date - Source date.
 * @returns {string} Label in DD Mon format.
 */
const formatRecentDayLabel = (date) => {
  return `${String(date.getUTCDate()).padStart(2, "0")} ${shortMonthNames[date.getUTCMonth()]}`;
};

/**
 * Format a month bucket label for recent monthly charts.
 * @param {Date} date - Source month.
 * @returns {string} Label in Mon'YY format.
 */
const formatRecentMonthLabel = (date) => {
  return `${shortMonthNames[date.getUTCMonth()]}'${String(date.getUTCFullYear()).slice(-2)}`;
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
 * Format a YYYY-MM-DD day key as a short axis label without timezone shifts.
 * @param {string} value - Day key.
 * @returns {string} Label in DD Mon format, or the value when it is not a day key.
 */
export const formatDayAxisLabel = (value) => {
  if (typeof value !== "string") {
    return value;
  }

  const parts = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!parts) {
    return value;
  }

  const monthIndex = Number(parts[2]) - 1;
  if (monthIndex < 0 || monthIndex >= shortMonthNames.length) {
    return value;
  }

  return `${parts[3]} ${shortMonthNames[monthIndex]}`;
};

/**
 * Build consecutive recent UTC month entries ending in the current month.
 * @param {number} count - Number of months to generate.
 * @param {Date} now - Reference time, defaulting to the current time.
 * @returns {Array<{key: string, label: string}>} Month keys and labels.
 */
const buildRecentMonthEntries = (count, now = new Date()) => {
  return Array.from({ length: count }, (_, index) => {
    const offset = count - index - 1;
    const date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - offset, 1));

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
 * @param {Date} options.now - Reference time used to build UTC buckets.
 * @returns {{categories: Array<string>, values: Array<number>}} Filled series.
 */
export const buildRecentBarSeries = (points = [], unit, defaultCount, options = {}) => {
  const { useFormattedMonthLabels = true, reservePeriodStart = true, now = new Date() } = options;

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
    buildRecentMonthEntries(count, now).forEach(({ key, label }) => {
      categories.push(useFormattedMonthLabels ? label : key);
      values.push(valuesByKey.get(key) ?? 0);
    });

    return { categories, values };
  }

  for (let offset = count - 1; offset >= 0; offset -= 1) {
    const date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - offset));

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
  return readChartColor(getComputedStyle(document.documentElement), "--color-stone-100");
};

/**
 * Read neutral tooltip colors.
 * @returns {{background: string, border: string, text: string}} Tooltip colors.
 */
const getChartTooltipColors = () => {
  const styles = getComputedStyle(document.documentElement);

  return {
    background: readChartColor(styles, "--color-white"),
    border: readChartColor(styles, "--color-stone-200"),
    text: readChartColor(styles, "--color-stone-700"),
  };
};

/**
 * Read neutral chart UI colors.
 * @returns {{text: string, muted: string, soft: string, surface: string}} UI colors.
 */
export const getChartUiColors = () => {
  const styles = getComputedStyle(document.documentElement);

  return {
    text: readChartColor(styles, "--color-stone-700"),
    muted: readChartColor(styles, "--color-stone-400"),
    soft: readChartColor(styles, "--color-stone-300"),
    surface: readChartColor(styles, "--color-white"),
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
  const el = getElementById(document, elementId);
  if (!el || typeof echarts === "undefined") {
    return null;
  }

  el.replaceChildren();
  const chart = echarts.init(el);
  chart.setOption(option);
  return chart;
};

/**
 * Shared typography configuration for charts.
 * @returns {Object} Text styling options.
 */
const baseText = () => {
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

/**
 * Create vertical bar chart configuration for daily data.
 * @param {string} title - Chart title.
 * @param {string} name - Series name.
 * @param {Array} data - Daily data pairs.
 * @param {Object} palette - Theme color palette.
 * @param {Object} options - Chart options.
 * @param {string} options.description - Short chart description.
 * @returns {Object} ECharts option.
 */
export const createDailyBarChart = (title, name, data, palette, options = {}) => {
  const { description = "" } = options;
  const seriesData = buildRecentBarSeries(data, "day", 30);
  const barSeriesStyle = getVerticalBarSeriesStyle(seriesData.values.length);

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
    xAxis: getVerticalBarCategoryAxisConfig(seriesData.categories),
    yAxis: getValueAxisConfig(),
    series: [
      {
        name,
        type: "bar",
        data: seriesData.values,
        ...barSeriesStyle,
      },
    ],
  });
};

/**
 * Build a palette for multi-series charts. Two or three series spread across
 * the ramp so neighboring colors stay clearly distinguishable.
 * @param {Object} palette - Theme color palette.
 * @param {number} count - Number of series.
 * @returns {Array<string>} Color list sized to the series count.
 */
const buildSeriesColors = (palette, count) => {
  if (count === 2) {
    return [palette[950], palette[400]];
  }
  if (count === 3) {
    return [palette[950], palette[600], palette[300]];
  }

  const highContrastPalette = [
    palette[950],
    palette[800],
    palette[600],
    palette[400],
    palette[200],
    palette[50],
  ];
  const fullPalette = [
    palette[950],
    palette[900],
    palette[800],
    palette[700],
    palette[600],
    palette[500],
    palette[400],
    palette[300],
    palette[200],
    palette[100],
    palette[50],
  ];
  const paletteToUse = count <= 6 ? highContrastPalette : fullPalette;

  if (count <= paletteToUse.length) {
    return paletteToUse.slice(0, count);
  }

  const colors = [];
  for (let i = 0; i < count; i += 1) {
    colors.push(paletteToUse[i % paletteToUse.length]);
  }
  return colors;
};

/**
 * Normalize monthly series maps into aligned stacks.
 * @param {Object<string, Array<[string, number|string]>>} seriesMap - Named series.
 * @param {Object} options - Series options.
 * @param {boolean} options.reservePeriodStart - Reserve empty buckets from the recent period start.
 * @param {number} options.recentWindowMonths - Number of months to display.
 * @param {Date} options.now - Reference time used to build UTC months.
 * @returns {{months: Array<string>, series: Array<{name: string, data: Array<number>}>}} Aligned data.
 */
export const buildStackedMonthlySeries = (seriesMap = {}, options = {}) => {
  const { now = new Date(), recentWindowMonths = 24, reservePeriodStart = false } = options;
  const seriesEntries = Object.entries(seriesMap).filter(([, points]) => Array.isArray(points));
  const hasSeriesData = seriesEntries.some(([, points]) => points.length > 0);

  if (!reservePeriodStart || !hasSeriesData) {
    const monthsSet = new Set();
    seriesEntries.forEach(([, points]) => {
      (points || []).forEach(([month]) => monthsSet.add(month));
    });

    const months = Array.from(monthsSet).sort();
    const seriesNames = Object.keys(seriesMap).sort((a, b) => a.localeCompare(b));

    return {
      months,
      series: seriesNames.map((name) => {
        const valuesByMonth = new Map(
          (seriesMap[name] || []).map(([month, value]) => [month, Number(value)]),
        );
        return { name, data: months.map((month) => valuesByMonth.get(month) ?? 0) };
      }),
    };
  }

  const months = buildRecentMonthEntries(recentWindowMonths, now).map(({ key }) => key);
  const seriesNames = Object.keys(seriesMap).sort((a, b) => a.localeCompare(b));

  return {
    months,
    series: seriesNames.map((name) => {
      const valuesByMonth = new Map((seriesMap[name] || []).map(([month, value]) => [month, Number(value)]));
      return { name, data: months.map((month) => valuesByMonth.get(month) ?? 0) };
    }),
  };
};

/**
 * Normalize time-based series maps into aligned stacks.
 * @param {Object<string, Array<[number|string, number|string]>>} seriesMap - Named series.
 * @returns {{timestamps: Array<number>, series: Array<{name: string, data: Array<[number, number]>}>}} Aligned series.
 */
export const buildStackedTimeSeries = (seriesMap = {}) => {
  const timestamps = new Set();
  Object.values(seriesMap).forEach((points) => {
    (points || []).forEach(([ts]) => timestamps.add(Number(ts)));
  });

  const sortedTs = Array.from(timestamps).sort((a, b) => a - b);
  const seriesNames = Object.keys(seriesMap).sort((a, b) => a.localeCompare(b));

  return {
    timestamps: sortedTs,
    series: seriesNames.map((name) => {
      const valuesByTs = new Map((seriesMap[name] || []).map(([ts, value]) => [Number(ts), Number(value)]));
      let last = 0;
      return {
        name,
        data: sortedTs.map((ts) => {
          const value = valuesByTs.get(ts);
          if (typeof value === "number") {
            last = value;
          }
          return [ts, last];
        }),
      };
    }),
  };
};

/**
 * Create stacked monthly bar chart configuration for grouped series.
 * @param {string} title - Chart title.
 * @param {Array<string>} months - Month labels.
 * @param {Array<{name: string, data: Array<number>}>} seriesData - Aligned series data.
 * @param {Object} palette - Theme color palette.
 * @param {Object} options - Chart options.
 * @param {string} options.description - Short chart description.
 * @returns {Object} ECharts option.
 */
export const createStackedMonthlyChart = (title, months, seriesData, palette, options = {}) => {
  const { description = "" } = options;
  const colors = buildSeriesColors(palette, seriesData.length || 1);
  const barSeriesStyle = getVerticalBarSeriesStyle(months.length);

  return Object.assign(baseText(), {
    title: getChartTitleConfig(title, palette, description),
    color: colors,
    tooltip: Object.assign(getAxisTooltipConfig(), { axisPointer: { type: "shadow" } }),
    legend: {
      type: seriesData.length > 5 ? "scroll" : "plain",
      bottom: 10,
      left: "center",
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 12 },
    },
    grid: { left: 70, right: 40, bottom: 100, top: getChartGridTop(description) },
    xAxis: getVerticalBarCategoryAxisConfig(months),
    yAxis: getValueAxisConfig(),
    series: seriesData.map((series) => ({
      name: series.name,
      type: "bar",
      stack: "total",
      emphasis: { focus: "series" },
      data: series.data,
      ...barSeriesStyle,
    })),
  });
};

/**
 * Create stacked area chart configuration for grouped running totals.
 * @param {string} title - Chart title.
 * @param {Array<{name: string, data: Array<[number, number]>}>} seriesData - Aligned series data.
 * @param {Object} palette - Theme color palette.
 * @param {Object} options - Chart options.
 * @param {string} options.description - Short chart description.
 * @returns {Object} ECharts option.
 */
export const createStackedAreaChart = (title, seriesData, palette, options = {}) => {
  const { description = "" } = options;
  const colors = buildSeriesColors(palette, seriesData.length || 1);

  return {
    baseOption: Object.assign(baseText(), {
      title: getChartTitleConfig(title, palette, description),
      color: colors,
      tooltip: getAxisTooltipConfig(),
      legend: {
        type: seriesData.length > 5 ? "scroll" : "plain",
        bottom: 10,
        left: "center",
        textStyle: { fontFamily: dashboardFontFamily, fontSize: 12 },
      },
      grid: { left: 70, right: 40, bottom: 90, top: getChartGridTop(description, 60) },
      xAxis: {
        type: "time",
        boundaryGap: false,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { fontSize: 11 },
        splitLine: { show: false },
      },
      yAxis: getValueAxisConfig(),
      series: seriesData.map((series) => ({
        name: series.name,
        type: "line",
        stack: "total",
        smooth: true,
        symbol: "none",
        showSymbol: false,
        areaStyle: { opacity: 0.35 },
        lineStyle: { width: 2 },
        emphasis: { focus: "series" },
        data: series.data,
      })),
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
 * Create horizontal bar chart configuration for category data.
 * @param {string} title - Chart title.
 * @param {Array<{name: string, value: number}>} categoryData - Category series data.
 * @param {Object} palette - Theme color palette.
 * @param {Object} options - Chart options.
 * @param {string} options.description - Short chart description.
 * @param {boolean} options.inverse - Whether the first category is drawn at the top.
 * @param {number} options.leftMargin - Left margin reserved for category labels.
 * @param {number} options.percentBase - Total used to compute percentages, defaulting to the data total.
 * @param {boolean} options.showValueAxisLabels - Whether the value axis shows its labels.
 * @param {"percent"|"count"} options.valueLabel - Value shown next to each bar; count mode also omits tooltip percentages.
 * @returns {Object} ECharts option.
 */
export const createHorizontalBarChart = (title, categoryData, palette, options = {}) => {
  const {
    description = "",
    inverse = false,
    leftMargin = 140,
    percentBase,
    showValueAxisLabels = true,
    valueLabel = "percent",
  } = options;
  const total = percentBase ?? categoryData.reduce((sum, d) => sum + d.value, 0);
  const formatPercent = (value) => (total > 0 ? ((value / total) * 100).toFixed(1) : 0);
  const uiColors = getChartUiColors();

  return Object.assign(baseText(), {
    title: getChartTitleConfig(title, palette, description),
    color: [palette[700]],
    tooltip: Object.assign(getItemTooltipConfig(), {
      formatter: (params) => {
        const label = `${escapeHtml(String(params.name ?? ""))}: ${params.value}`;
        return valueLabel === "count" ? label : `${label} (${formatPercent(params.value)}%)`;
      },
    }),
    grid: { left: leftMargin, right: 80, bottom: 40, top: getChartGridTop(description) },
    xAxis: {
      type: "value",
      minInterval: 1,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: uiColors.muted, fontSize: 11, show: showValueAxisLabels },
      splitLine: { lineStyle: { color: getChartGridLineColor(), type: "dashed" } },
    },
    yAxis: {
      type: "category",
      inverse,
      data: categoryData.map((d) => d.name),
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: uiColors.text, fontSize: 12 },
    },
    series: [
      {
        type: "bar",
        data: categoryData.map((d) => d.value),
        barCategoryGap: "30%",
        label: {
          show: true,
          position: "right",
          formatter: (params) =>
            valueLabel === "count" ? `${params.value}` : `${formatPercent(params.value)}%`,
          fontSize: 11,
          color: uiColors.muted,
        },
      },
    ],
  });
};

/**
 * Create pie chart configuration for distribution data.
 * @param {string} title - Chart title.
 * @param {string} name - Series name.
 * @param {Array<{name: string, value: number}>} data - Category series data.
 * @param {Object} palette - Theme color palette.
 * @param {Object} options - Chart options.
 * @param {Array<string>} options.colors - Explicit colors aligned with the data.
 * @param {string} options.description - Short chart description.
 * @param {boolean} options.groupTail - Whether slices beyond the sixth are grouped as "Other".
 * @param {"right"|"bottom"} options.legendPosition - Where the legend is placed next to the pie.
 * @param {boolean} options.showLabels - Whether slices show percentage labels.
 * @returns {Object} ECharts option.
 */
export const createPieChart = (title, name, data, palette, options = {}) => {
  const { colors, description = "", groupTail = true, legendPosition = "right", showLabels = true } = options;
  const isBottomLegend = legendPosition === "bottom";
  const uiColors = getChartUiColors();
  const pieColors = colors || buildSeriesColors(palette, data.length);

  let chartData = data;
  if (groupTail && data.length > 6) {
    // Keep dense distributions legible by grouping the long tail as "Other".
    const sorted = [...data].sort((a, b) => b.value - a.value);
    const top6 = sorted.slice(0, 6);
    const otherValue = sorted.slice(6).reduce((sum, item) => sum + item.value, 0);
    if (otherValue > 0) {
      top6.push({ name: "Other", value: otherValue });
    }
    chartData = top6;
  }

  return Object.assign(baseText(), {
    title: getChartTitleConfig(title, palette, description),
    color: pieColors,
    tooltip: Object.assign(getItemTooltipConfig(), { formatter: "{b}: {c} ({d}%)" }),
    legend: {
      ...(isBottomLegend
        ? { orient: "horizontal", left: "center", bottom: 0 }
        : { orient: "vertical", left: "55%", top: "30%" }),
      icon: "circle",
      itemWidth: 10,
      itemHeight: 10,
      itemGap: 12,
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14 },
      formatter: (label) => {
        if (label.length > 25) {
          return `${label.substring(0, 25)}...`;
        }
        return label;
      },
    },
    series: [
      {
        name,
        type: "pie",
        radius: isBottomLegend ? ["32%", "56%"] : ["30%", "55%"],
        center: isBottomLegend ? ["50%", "54%"] : ["28%", "58%"],
        avoidLabelOverlap: true,
        itemStyle: { borderColor: uiColors.surface, borderWidth: 2 },
        label: {
          show: showLabels,
          position: "outside",
          formatter: "{d}%",
          fontSize: 11,
          color: uiColors.muted,
        },
        labelLine: {
          show: showLabels,
          length: 8,
          length2: 6,
          lineStyle: { color: uiColors.soft },
        },
        emphasis: {
          label: { fontWeight: "bold" },
        },
        data: chartData,
      },
    ],
  });
};

/**
 * Build line symbol options that keep a single-day series visible.
 * @param {number} dayCount - Number of days on the category axis.
 * @returns {{symbol: string, showSymbol: boolean}} ECharts line symbol options.
 */
export const getDailyLineSymbolConfig = (dayCount) => {
  const isSingleDay = dayCount === 1;
  return { symbol: isSingleDay ? "circle" : "none", showSymbol: isSingleDay };
};

/**
 * Build mark lines placing timed markers on their UTC day.
 * @param {Array<{kind: string, ts: number}>} markers - Markers with Unix seconds timestamps.
 * @param {Object} options - Marker options.
 * @param {string} options.color - Mark line color.
 * @param {Array<string>} options.days - YYYY-MM-DD day keys shown on the axis.
 * @param {Function} options.labelForKind - Maps a marker kind to its display label.
 * @param {string} options.timeZone - IANA timezone used in tooltips.
 * @returns {Object|null} ECharts markLine config, or null without visible markers.
 */
export const getDayMarkersConfig = (markers = [], options = {}) => {
  const { color, days = [], labelForKind = (kind) => kind, timeZone = "UTC" } = options;
  const visibleDays = new Set(days);
  const formatter = new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    month: "short",
    timeZone,
    timeZoneName: "short",
    year: "numeric",
  });
  const detailsByDay = new Map();

  (markers || []).forEach(({ kind, ts }) => {
    const date = new Date(Number(ts) * 1000);
    if (Number.isNaN(date.getTime())) {
      return;
    }

    const day = date.toISOString().slice(0, 10);
    if (!visibleDays.has(day)) {
      return;
    }

    const details = detailsByDay.get(day) || [];
    details.push(`${labelForKind(kind)}: ${formatter.format(date)}`);
    detailsByDay.set(day, details);
  });

  if (detailsByDay.size === 0) {
    return null;
  }

  return {
    symbol: "none",
    silent: false,
    animation: false,
    label: { show: false },
    lineStyle: { color, type: "dashed", width: 1 },
    tooltip: {
      trigger: "item",
      formatter: (params) => (params.data?.details || []).join("<br/>"),
    },
    data: Array.from(detailsByDay, ([day, details]) => ({
      details,
      name: details.join(", "),
      xAxis: day,
    })),
  };
};

/**
 * Create stacked bar chart configuration for UTC day series.
 * @param {string} title - Chart title.
 * @param {Array<string>} days - YYYY-MM-DD day keys.
 * @param {Array<{name: string, data: Array<number>, color?: string}>} seriesData - Aligned series.
 * @param {Object} palette - Theme color palette.
 * @param {Object} options - Chart options.
 * @param {string} options.description - Short chart description.
 * @param {Object|null} options.markLine - Mark line config attached to the first series.
 * @returns {Object} ECharts option.
 */
export const createStackedDailyBarChart = (title, days, seriesData, palette, options = {}) => {
  const { description = "", markLine = null } = options;
  const colors = getExplicitSeriesColors(seriesData, palette);
  const barSeriesStyle = getVerticalBarSeriesStyle(days.length);

  return Object.assign(baseText(), {
    title: getChartTitleConfig(title, palette, description),
    color: colors,
    tooltip: Object.assign(getAxisTooltipConfig(), { axisPointer: { type: "shadow" } }),
    legend: getStackedLegendConfig(seriesData.length),
    grid: { left: 70, right: 40, bottom: 100, top: getChartGridTop(description) },
    xAxis: getDailyCategoryAxisConfig(days),
    yAxis: getValueAxisConfig(),
    series: seriesData.map((series, index) => ({
      name: series.name,
      type: "bar",
      stack: "total",
      emphasis: { focus: "series" },
      itemStyle: { color: colors[index] },
      data: series.data,
      ...barSeriesStyle,
      ...(index === 0 && markLine ? { markLine } : {}),
    })),
  });
};

/**
 * Build a category x-axis configuration for UTC day keys.
 * @param {Array<string>} days - YYYY-MM-DD day keys.
 * @returns {Object} ECharts category axis config.
 */
const getDailyCategoryAxisConfig = (days = []) => {
  return {
    type: "category",
    data: days,
    axisLine: { show: false },
    axisTick: { show: false },
    axisLabel: {
      fontSize: 10,
      formatter: (value, index) => {
        return shouldShowSparseAxisLabel(index, days.length, 8) ? formatDayAxisLabel(value) : "";
      },
    },
    splitLine: { show: false },
  };
};

/**
 * Resolve series colors, keeping explicit colors and filling the rest from the palette.
 * @param {Array<{color?: string}>} seriesData - Series data.
 * @param {Object} palette - Theme color palette.
 * @returns {Array<string>} Colors aligned with the series.
 */
const getExplicitSeriesColors = (seriesData, palette) => {
  const fallbackColors = buildSeriesColors(palette, seriesData.length || 1);
  return seriesData.map((series, index) => series.color || fallbackColors[index]);
};

/**
 * Build the bottom legend used by stacked charts.
 * @param {number} count - Number of series.
 * @returns {Object} ECharts legend config.
 */
const getStackedLegendConfig = (count) => {
  return {
    type: count > 5 ? "scroll" : "plain",
    bottom: 10,
    left: "center",
    textStyle: { fontFamily: dashboardFontFamily, fontSize: 12 },
  };
};
