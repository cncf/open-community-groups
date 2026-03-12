/**
 * Dashboard common utilities
 */

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
 * Triggers a change event on the specified form using htmx.
 * @param {string} formId - The ID of the form to trigger change on
 */
export const triggerChangeOnForm = (formId) => {
  const form = document.getElementById(formId);
  if (form) {
    // Trigger change event using htmx
    htmx.trigger(form, "change");
  }
};

/**
 * Dynamically loads the ECharts library if not already present.
 * @returns {Promise<void>} Promise that resolves when ECharts is loaded
 */
export const loadEChartsScript = () => {
  return new Promise((resolve, reject) => {
    // Check if ECharts is already loaded
    if (typeof window.echarts !== "undefined") {
      resolve();
      return;
    }

    // Check if script is already being loaded
    const existingScript = document.querySelector('script[src*="echarts"]');
    if (existingScript) {
      // Wait for existing script to load
      existingScript.addEventListener("load", () => resolve());
      existingScript.addEventListener("error", () => reject(new Error("Failed to load ECharts")));
      return;
    }

    // Create and inject script tag
    const script = document.createElement("script");
    script.src = "/static/vendor/js/echarts.v6.0.0.min.js";
    script.onload = () => resolve();
    script.onerror = () => reject(new Error("Failed to load ECharts"));
    document.head.appendChild(script);
  });
};

/**
 * Defers work until an HTMX swap settles to avoid acting on stale nodes.
 * This prevents empty-state rendering from targeting elements replaced by a swap.
 * @param {() => Promise<void> | void} task - Work to run after swap settles.
 * @returns {Promise<void>} Promise resolved when task completes.
 */
export const deferUntilHtmxSettled = (task) => {
  const body = document.body;
  const shouldDefer = Boolean(
    window.htmx &&
    body &&
    (body.classList.contains("htmx-swapping") || body.classList.contains("htmx-settling")),
  );

  if (!shouldDefer) {
    return Promise.resolve().then(() => task());
  }

  return new Promise((resolve, reject) => {
    let hasRun = false;

    const runTask = () => {
      if (hasRun) {
        return;
      }
      hasRun = true;
      Promise.resolve()
        .then(() => task())
        .then(resolve)
        .catch(reject);
    };

    body.addEventListener("htmx:afterSwap", runTask, { once: true });
    body.addEventListener("htmx:afterSettle", runTask, { once: true });
  });
};

/**
 * Read theme colors from CSS variables to keep charts aligned with the dashboard palette.
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

/** Typography family shared across dashboard charts. */
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
 * @returns {Object} ECharts title config.
 */
export const getChartTitleConfig = (title, palette) => {
  return {
    text: title,
    left: "center",
    top: 12,
    textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: palette[950] },
  };
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
 * @returns {Object} ECharts option.
 */
export const createAreaChart = (title, name, data, palette) => {
  return {
    baseOption: Object.assign(baseText(), {
      title: getChartTitleConfig(title, palette),
      color: [palette[700]],
      tooltip: getAxisTooltipConfig(),
      grid: { left: 70, right: 40, bottom: 90, top: 80 },
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
 * @param {number} options.recentWindowMonths - Number of months to display on the axis.
 * @param {boolean} options.reservePeriodStart - Reserve empty buckets from the recent period start.
 * @returns {Object} ECharts option.
 */
export const createMonthlyBarChart = (title, name, data, palette, options = {}) => {
  const { recentWindowMonths = 24, reservePeriodStart = false } = options;
  const filledSeries = buildRecentBarSeries(data, "month", recentWindowMonths, {
    useFormattedMonthLabels: true,
    reservePeriodStart,
  });
  const barSeriesStyle = getVerticalBarSeriesStyle(filledSeries.values.length);

  return Object.assign(baseText(), {
    title: getChartTitleConfig(title, palette),
    color: [palette[700]],
    tooltip: getAxisTooltipConfig(),
    legend: {
      bottom: 10,
      left: "center",
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 12 },
    },
    grid: { left: 70, right: 40, bottom: 100, top: 80 },
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
 * @returns {Object} ECharts option.
 */
export const createDailyBarChart = (title, name, data, palette) => {
  const seriesData = buildRecentBarSeries(data, "day", 30);
  const barSeriesStyle = getVerticalBarSeriesStyle(seriesData.values.length);

  return Object.assign(baseText(), {
    title: getChartTitleConfig(title, palette),
    color: [palette[700]],
    tooltip: getAxisTooltipConfig(),
    legend: {
      bottom: 10,
      left: "center",
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 12 },
    },
    grid: { left: 70, right: 40, bottom: 100, top: 80 },
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
 * Build a palette for multi-series charts.
 * @param {Object} palette - Theme color palette.
 * @param {number} count - Number of series.
 * @returns {Array<string>} Color list sized to the series count.
 */
export const buildSeriesColors = (palette, count) => {
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
 * @returns {{months: Array<string>, series: Array<{name: string, data: Array<number>}>}} Aligned data.
 */
export const buildStackedMonthlySeries = (seriesMap = {}, options = {}) => {
  const { recentWindowMonths = 24, reservePeriodStart = false } = options;
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

  const months = buildRecentMonthEntries(recentWindowMonths).map(({ key }) => key);
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
 * @returns {Object} ECharts option.
 */
export const createStackedMonthlyChart = (title, months, seriesData, palette) => {
  const colors = buildSeriesColors(palette, seriesData.length || 1);
  const barSeriesStyle = getVerticalBarSeriesStyle(months.length);

  return Object.assign(baseText(), {
    title: getChartTitleConfig(title, palette),
    color: colors,
    tooltip: Object.assign(getAxisTooltipConfig(), { axisPointer: { type: "shadow" } }),
    legend: {
      type: seriesData.length > 5 ? "scroll" : "plain",
      bottom: 10,
      left: "center",
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 12 },
    },
    grid: { left: 70, right: 40, bottom: 100, top: 80 },
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
 * @returns {Object} ECharts option.
 */
export const createStackedAreaChart = (title, seriesData, palette) => {
  const colors = buildSeriesColors(palette, seriesData.length || 1);

  return {
    baseOption: Object.assign(baseText(), {
      title: getChartTitleConfig(title, palette),
      color: colors,
      tooltip: getAxisTooltipConfig(),
      legend: {
        type: seriesData.length > 5 ? "scroll" : "plain",
        bottom: 10,
        left: "center",
        textStyle: { fontFamily: dashboardFontFamily, fontSize: 12 },
      },
      grid: { left: 70, right: 40, bottom: 90, top: 60 },
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
 * @param {Array} categoryData - Category series data.
 * @param {Object} palette - Theme color palette.
 * @param {number} leftMargin - Left margin for labels.
 * @returns {Object} ECharts option.
 */
export const createHorizontalBarChart = (title, categoryData, palette, leftMargin = 140) => {
  const total = categoryData.reduce((sum, d) => sum + d.value, 0);
  const gridLineColor = getChartGridLineColor();
  const tooltipColors = getChartTooltipColors();
  const uiColors = getChartUiColors();

  return Object.assign(baseText(), {
    title: {
      text: title,
      left: "center",
      top: 12,
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: palette[950] },
    },
    color: [palette[700]],
    tooltip: {
      trigger: "item",
      backgroundColor: tooltipColors.background,
      borderColor: tooltipColors.border,
      borderWidth: 1,
      textStyle: { color: tooltipColors.text },
      formatter: (params) => {
        const percent = total > 0 ? ((params.value / total) * 100).toFixed(1) : 0;
        return `${params.name}: ${params.value} (${percent}%)`;
      },
    },
    grid: { left: leftMargin, right: 80, bottom: 40, top: 80 },
    xAxis: {
      type: "value",
      minInterval: 1,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: uiColors.muted, fontSize: 11 },
      splitLine: { lineStyle: { color: gridLineColor, type: "dashed" } },
    },
    yAxis: {
      type: "category",
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
          formatter: (params) => {
            const percent = total > 0 ? ((params.value / total) * 100).toFixed(1) : 0;
            return `${percent}%`;
          },
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
 * @param {Array} data - Category series data.
 * @param {Object} palette - Theme color palette.
 * @returns {Object} ECharts option.
 */
export const createPieChart = (title, name, data, palette) => {
  const tooltipColors = getChartTooltipColors();
  const uiColors = getChartUiColors();
  const pieColors =
    data.length <= 6
      ? [palette[950], palette[800], palette[600], palette[400], palette[200], palette[50]]
      : [
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

  let chartData = data;
  if (data.length > 6) {
    const sorted = [...data].sort((a, b) => b.value - a.value);
    const top6 = sorted.slice(0, 6);
    const otherValue = sorted.slice(6).reduce((sum, item) => sum + item.value, 0);
    if (otherValue > 0) {
      top6.push({ name: "Other", value: otherValue });
    }
    chartData = top6;
  }

  return Object.assign(baseText(), {
    title: {
      text: title,
      left: "center",
      top: 12,
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: palette[950] },
    },
    color: pieColors,
    tooltip: {
      trigger: "item",
      backgroundColor: tooltipColors.background,
      borderColor: tooltipColors.border,
      borderWidth: 1,
      textStyle: { color: tooltipColors.text },
      formatter: "{b}: {c} ({d}%)",
    },
    legend: {
      orient: "vertical",
      left: "55%",
      top: "30%",
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
        radius: ["30%", "55%"],
        center: ["28%", "58%"],
        avoidLabelOverlap: true,
        itemStyle: { borderColor: uiColors.surface, borderWidth: 2 },
        label: {
          show: true,
          position: "outside",
          formatter: "{d}%",
          fontSize: 11,
          color: uiColors.muted,
        },
        labelLine: {
          show: true,
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
