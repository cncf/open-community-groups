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
  return Object.assign(baseText(), {
    title: {
      text: title,
      left: "center",
      top: 12,
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: "#334155" },
    },
    color: [palette[700]],
    tooltip: {
      trigger: "axis",
      backgroundColor: "#fff",
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: "#334155" },
    },
    grid: { left: 70, right: 40, bottom: 90, top: 80 },
    xAxis: {
      type: "time",
      boundaryGap: false,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: "#94a3b8", fontSize: 11 },
      splitLine: { show: false },
    },
    yAxis: {
      type: "value",
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: "#94a3b8", fontSize: 11 },
      splitLine: { lineStyle: { color: "#f1f5f9", type: "dashed" } },
    },
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
  });
};

/**
 * Create vertical bar chart configuration for monthly data.
 * @param {string} title - Chart title.
 * @param {string} name - Series name.
 * @param {Array} data - Monthly data pairs.
 * @param {Object} palette - Theme color palette.
 * @returns {Object} ECharts option.
 */
export const createMonthlyBarChart = (title, name, data, palette) => {
  return Object.assign(baseText(), {
    title: {
      text: title,
      left: "center",
      top: 12,
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: "#334155" },
    },
    color: [palette[700]],
    tooltip: {
      trigger: "axis",
      backgroundColor: "#fff",
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: "#334155" },
    },
    grid: { left: 70, right: 40, bottom: 110, top: 80 },
    xAxis: {
      type: "category",
      data: (data || []).map((d) => d[0]),
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { rotate: 45, color: "#94a3b8", fontSize: 10 },
    },
    yAxis: {
      type: "value",
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: "#94a3b8", fontSize: 11 },
      splitLine: { lineStyle: { color: "#f1f5f9", type: "dashed" } },
    },
    series: [
      {
        name,
        type: "bar",
        data: (data || []).map((d) => Number(d[1])),
        barCategoryGap: "30%",
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
 * @returns {{months: Array<string>, series: Array<{name: string, data: Array<number>}>}} Aligned data.
 */
export const buildStackedMonthlySeries = (seriesMap = {}) => {
  const monthsSet = new Set();
  Object.values(seriesMap).forEach((points) => {
    (points || []).forEach(([month]) => monthsSet.add(month));
  });

  const months = Array.from(monthsSet).sort();
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

  return Object.assign(baseText(), {
    title: {
      text: title,
      left: "center",
      top: 12,
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: "#334155" },
    },
    color: colors,
    tooltip: {
      trigger: "axis",
      axisPointer: { type: "shadow" },
      backgroundColor: "#fff",
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: "#334155" },
    },
    legend: {
      type: seriesData.length > 5 ? "scroll" : "plain",
      bottom: 10,
      left: "center",
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 12, color: "#475569" },
    },
    grid: { left: 70, right: 40, bottom: 100, top: 80 },
    xAxis: {
      type: "category",
      data: months,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { rotate: 45, color: "#94a3b8", fontSize: 10 },
    },
    yAxis: {
      type: "value",
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: "#94a3b8", fontSize: 11 },
      splitLine: { lineStyle: { color: "#f1f5f9", type: "dashed" } },
    },
    series: seriesData.map((series) => ({
      name: series.name,
      type: "bar",
      stack: "total",
      emphasis: { focus: "series" },
      data: series.data,
      barCategoryGap: "35%",
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

  return Object.assign(baseText(), {
    title: {
      text: title,
      left: "center",
      top: 12,
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: "#334155" },
    },
    color: colors,
    tooltip: {
      trigger: "axis",
      backgroundColor: "#fff",
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: "#334155" },
    },
    legend: {
      type: seriesData.length > 5 ? "scroll" : "plain",
      bottom: 10,
      left: "center",
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 12, color: "#475569" },
    },
    grid: { left: 70, right: 40, bottom: 90, top: 60 },
    xAxis: {
      type: "time",
      boundaryGap: false,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: "#94a3b8", fontSize: 11 },
      splitLine: { show: false },
    },
    yAxis: {
      type: "value",
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: "#94a3b8", fontSize: 11 },
      splitLine: { lineStyle: { color: "#f1f5f9", type: "dashed" } },
    },
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
  });
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

  return Object.assign(baseText(), {
    title: {
      text: title,
      left: "center",
      top: 12,
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: "#334155" },
    },
    color: [palette[700]],
    tooltip: {
      trigger: "item",
      backgroundColor: "#fff",
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: "#334155" },
      formatter: (params) => {
        const percent = total > 0 ? ((params.value / total) * 100).toFixed(1) : 0;
        return `${params.name}: ${params.value} (${percent}%)`;
      },
    },
    grid: { left: leftMargin, right: 80, bottom: 40, top: 80 },
    xAxis: {
      type: "value",
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: "#94a3b8", fontSize: 11 },
      splitLine: { lineStyle: { color: "#f1f5f9", type: "dashed" } },
    },
    yAxis: {
      type: "category",
      data: categoryData.map((d) => d.name),
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: "#334155", fontSize: 12 },
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
          color: "#64748b",
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
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, fontWeight: 500, color: "#334155" },
    },
    color: pieColors,
    tooltip: {
      trigger: "item",
      backgroundColor: "#fff",
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: "#334155" },
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
      textStyle: { fontFamily: dashboardFontFamily, fontSize: 14, color: "#334155" },
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
        itemStyle: { borderColor: "#fff", borderWidth: 2 },
        label: {
          show: true,
          position: "outside",
          formatter: "{d}%",
          fontSize: 11,
          color: "#64748b",
        },
        labelLine: {
          show: true,
          length: 8,
          length2: 6,
          lineStyle: { color: "#cbd5e1" },
        },
        emphasis: {
          label: { fontWeight: "bold" },
        },
        data: chartData,
      },
    ],
  });
};
