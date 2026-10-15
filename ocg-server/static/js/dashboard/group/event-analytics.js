import {
  createHorizontalBarChart,
  createPieChart,
  createStackedDailyBarChart,
  createTooltipDateTimeFormatter,
  dashboardFontFamily,
  formatDayAxisLabel,
  getAxisTooltipConfig,
  getChartTitleConfig,
  getChartUiColors,
  getDailyLineSymbolConfig,
  getDayMarkersConfig,
  getThemePalette,
  getValueAxisConfig,
  getVerticalBarSeriesStyle,
  hasActivity,
} from "/static/js/common/charts/charts.js";
import {
  getCategoryLabelInterval,
  initializeChartsFromJsonMarker,
  renderChart,
} from "/static/js/common/charts/stats.js";
import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";

/** Selector of the event analytics JSON marker. */
const EVENT_ANALYTICS_DATA_SELECTOR = "[data-event-analytics]";

/** Dataset key set once the event analytics charts are initialized. */
const EVENT_ANALYTICS_READY_KEY = "eventAnalyticsReady";

/** Display labels of the day markers shown on daily charts. */
const MARKER_LABELS = {
  announcement: "Announcement",
  "event-start": "Event start",
  published: "Published",
  "registration-closes": "Registration closes",
  "registration-opens": "Registration opens",
  "reminder-sent": "Reminder sent",
};

/** Display label used when a value is missing. */
const NOT_SPECIFIED_LABEL = "Not specified";

/** Combinations table columns sorted numerically. */
const NUMERIC_SORT_KEYS = new Set(["views"]);

/** Registration paths in display order, with their labels. */
const REGISTRATION_PATHS = [
  ["direct", "Direct"],
  ["approval", "Approved request"],
  ["waitlist", "Waiting list"],
  ["organizer_invitation", "Organizer invitation"],
  ["unknown", "Unknown"],
];

/** Number of sources shown individually in the share chart. */
const SHARE_TOP_SOURCES = 3;

/** Display labels of synthetic views series. */
const VIEWS_SERIES_LABELS = {
  "no-source": NOT_SPECIFIED_LABEL,
  "other-sources": "Other sources",
  untagged: "Unattributed",
};

/**
 * Analytics roots whose delegated controls are bound. Kept in memory, unlike a
 * dataset marker, so roots restored from the HTMX history cache bind again.
 */
const boundRoots = new WeakSet();

/** Statistics of each initialized analytics root, read by delegated controls. */
const statsByRoot = new WeakMap();

/**
 * Initializes the event analytics charts and their interactive controls.
 * @param {Object} stats - Event analytics payload from the server.
 * @param {Object} context - Initialization context.
 * @param {Element} context.marker - JSON marker the payload was read from.
 * @returns {Promise<void>} Promise resolved when the charts are rendered.
 */
export const initEventAnalyticsCharts = async (stats, context = {}) => {
  if (!stats) {
    return;
  }

  const root = context.marker?.parentElement || document.body;
  const palette = getThemePalette();
  const colors = buildEventSeriesColors(stats, palette);
  const hasEnded = Boolean(root.querySelector("[data-event-analytics-check-ins]"));

  // Traffic charts
  renderViewsDailyChart(stats, palette, colors);
  renderUtmShareChart(stats, palette, colors);
  renderUtmValuesChart(stats, palette, getSelectedUtmDimension(root));

  // Registration charts
  renderRegistrationsDailyChart(stats, palette);
  renderFillCurveChart(stats, palette);
  renderFunnelChart(stats, palette, hasEnded);
  renderRegistrationPathsChart(stats, palette);

  // Attendance charts
  if (hasEnded) {
    renderCheckInsChart(stats, palette);
  }

  // Interactive controls read the latest statistics of their root
  statsByRoot.set(root, { palette, stats });
  bindAnalyticsControls(root);
};

/**
 * Assigns a stable color to every traffic source series, shared by the daily
 * views and share charts. Sources shown only in the share chart take colors
 * not used by the other sources in that chart, preferring colors no other
 * source uses.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @returns {Map<string, string>} Colors keyed by series key.
 */
export const buildEventSeriesColors = (stats, palette) => {
  const sourceRamp = [
    palette[950],
    palette[700],
    palette[500],
    palette[300],
    palette[800],
    palette[600],
    palette[400],
  ];
  const colors = new Map();

  // Top sources of the charted days take the ramp in rank order
  (stats?.traffic?.views_by_source_per_day || [])
    .filter((series) => series.kind === "source")
    .forEach((series, index) => colors.set(getViewsSeriesKey(series), sourceRamp[index % sourceRamp.length]));

  // All-time top sources missing from the charted days avoid the colors of their share chart peers
  const shareKeys = (stats?.utm?.by_source?.values || [])
    .slice(0, SHARE_TOP_SOURCES)
    .map(({ value }) => `source:${value}`);
  const assignedColors = new Set(colors.values());
  const shareColors = new Set(shareKeys.filter((key) => colors.has(key)).map((key) => colors.get(key)));
  const freeColors = [
    ...sourceRamp.filter((color) => !assignedColors.has(color)),
    ...sourceRamp.filter((color) => assignedColors.has(color) && !shareColors.has(color)),
  ];
  shareKeys.filter((key) => !colors.has(key)).forEach((key, index) => colors.set(key, freeColors[index]));

  // Synthetic groups use fixed colors so they never shift between charts
  const uiColors = getChartUiColors();
  colors.set("other-sources", palette[200]);
  colors.set("no-source", uiColors.muted);
  colors.set("untagged", uiColors.soft);

  return colors;
};

/**
 * Formats check-in bin labels in the event timezone, adding the date when the
 * bins span several days.
 * @param {Array<number>} timestamps - Bin starts in Unix milliseconds.
 * @param {string} timeZone - IANA event timezone.
 * @returns {Array<string>} Axis labels.
 */
export const formatCheckInBinLabels = (timestamps = [], timeZone = "UTC") => {
  const dayFormatter = new Intl.DateTimeFormat("en-CA", { dateStyle: "short", timeZone });
  const timeFormatter = new Intl.DateTimeFormat("en-US", {
    hour: "2-digit",
    hourCycle: "h23",
    minute: "2-digit",
    timeZone,
  });
  const dateFormatter = new Intl.DateTimeFormat("en-US", { day: "numeric", month: "short", timeZone });
  const spansDays = new Set(timestamps.map((ts) => dayFormatter.format(new Date(ts)))).size > 1;

  return timestamps.map((ts) => {
    const date = new Date(ts);
    const time = timeFormatter.format(date);
    return spansDays ? `${dateFormatter.format(date)} ${time}` : time;
  });
};

/**
 * Returns the display label of a registrations series.
 * @param {Object} series - Registrations series.
 * @param {Object} stats - Event analytics payload.
 * @returns {string} Series label.
 */
export const getRegistrationsSeriesLabel = (series, stats) => {
  if (series.kind === "ticket-type" && series.title) {
    return series.title;
  }

  return stats?.tickets ? "Unknown ticket type" : "Registrations";
};

/**
 * Returns the display label of a views series.
 * @param {Object} series - Views series.
 * @returns {string} Series label.
 */
export const getViewsSeriesLabel = (series) => {
  if (series.kind === "source") {
    return series.source || NOT_SPECIFIED_LABEL;
  }

  return VIEWS_SERIES_LABELS[series.kind] || series.kind;
};

/**
 * Initializes the event analytics charts from the page JSON marker.
 * @param {Document|Element} root - Root element to search from.
 * @param {Object} context - Initialization lifecycle context.
 * @returns {Promise<void>} Promise resolved when initialization finishes.
 */
export const initializeEventAnalyticsFromPage = async (root = document, context = {}) => {
  return initializeChartsFromJsonMarker({
    root,
    selector: EVENT_ANALYTICS_DATA_SELECTOR,
    readyKey: EVENT_ANALYTICS_READY_KEY,
    initialize: initEventAnalyticsCharts,
    parseErrorMessage: "Failed to parse event analytics payload:",
    initErrorMessage: "Failed to initialize event analytics charts:",
    force: context.historyRestore === true,
  });
};

/**
 * Sorts the UTM combinations table rows, keeping ties in their original order
 * and empty values last.
 * @param {HTMLTableSectionElement} tbody - Table body with combination rows.
 * @param {string} key - Sort key from the column button.
 * @param {"ascending"|"descending"} direction - Sort direction.
 * @returns {void}
 */
export const sortUtmCombinationRows = (tbody, key, direction) => {
  const rows = Array.from(tbody.querySelectorAll("tr[data-utm-row]"));
  rows.forEach((row, index) => {
    if (row.dataset.utmIndex === undefined) {
      row.dataset.utmIndex = String(index);
    }
  });

  const datasetKey = key.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
  const factor = direction === "ascending" ? 1 : -1;
  const sortedRows = [...rows].sort((left, right) => {
    const leftValue = left.dataset[datasetKey] || "";
    const rightValue = right.dataset[datasetKey] || "";
    let order = 0;

    if (NUMERIC_SORT_KEYS.has(key)) {
      order = (Number(leftValue) - Number(rightValue)) * factor;
    } else if (!leftValue || !rightValue) {
      order = Number(!leftValue) - Number(!rightValue);
    } else {
      order = leftValue.localeCompare(rightValue) * factor;
    }

    return order || Number(left.dataset.utmIndex) - Number(right.dataset.utmIndex);
  });

  tbody.append(...sortedRows);
};

/**
 * Shows or hides the options of a registration question beyond the visible
 * ones, keeping the toggle label and expanded state in sync.
 * @param {HTMLButtonElement} button - Question options toggle button.
 * @returns {void}
 */
export const toggleQuestionOptions = (button) => {
  const list = document.getElementById(button.getAttribute("aria-controls") || "");
  if (!list) {
    return;
  }

  const expanded = button.getAttribute("aria-expanded") !== "true";
  list.querySelectorAll("[data-question-option-hidden]").forEach((option) => {
    option.hidden = !expanded;
  });
  button.setAttribute("aria-expanded", String(expanded));
  const label = button.querySelector("[data-question-options-label]") || button;
  label.textContent = expanded ? button.dataset.labelExpanded : button.dataset.labelCollapsed;
};

/**
 * Binds the delegated UTM dimension switch, table sorting and question
 * options toggles once per root.
 * @param {Element} root - Analytics root element.
 * @returns {void}
 */
const bindAnalyticsControls = (root) => {
  if (boundRoots.has(root)) {
    return;
  }
  boundRoots.add(root);

  root.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    const state = statsByRoot.get(root);
    if (!target || !state) {
      return;
    }

    // Switch the UTM dimension shown by the values chart
    const dimensionButton = target.closest("[data-utm-dimension]");
    if (dimensionButton && root.contains(dimensionButton)) {
      const group = dimensionButton.closest("[data-utm-dimension-switch]");
      group?.querySelectorAll("[data-utm-dimension]").forEach((button) => {
        button.setAttribute("aria-pressed", button === dimensionButton ? "true" : "false");
      });
      renderUtmValuesChart(state.stats, state.palette, dimensionButton.dataset.utmDimension);
      return;
    }

    // Sort the combinations table by the selected column
    const sortButton = target.closest("[data-utm-sort]");
    if (sortButton && root.contains(sortButton)) {
      handleCombinationsSort(sortButton);
      return;
    }

    // Expand or collapse the options of a registration question
    const optionsToggle = target.closest("[data-question-options-toggle]");
    if (optionsToggle && root.contains(optionsToggle)) {
      toggleQuestionOptions(optionsToggle);
    }
  });
};

/**
 * Builds the check-ins chart option with labels in the event timezone.
 * @param {Object} checkIns - Check-in statistics.
 * @param {Object} palette - Theme color palette.
 * @param {string} timeZone - IANA event timezone.
 * @returns {Object} ECharts option.
 */
const buildCheckInsOption = (checkIns, palette, timeZone) => {
  const bins = checkIns?.bins || [];
  const labels = formatCheckInBinLabels(
    bins.map(([ts]) => Number(ts)),
    timeZone,
  );
  const tooltipFormatter = createTooltipDateTimeFormatter(timeZone);

  return {
    textStyle: { fontFamily: dashboardFontFamily },
    title: getChartTitleConfig(
      "Check-ins over time",
      palette,
      `Arrivals per ${checkIns?.bin_minutes || 15} minutes in ${timeZone}`,
    ),
    color: [palette[700]],
    tooltip: Object.assign(getAxisTooltipConfig(), {
      axisPointer: { type: "shadow" },
      formatter: (params) => {
        const point = Array.isArray(params) ? params[0] : params;
        const ts = bins[point?.dataIndex]?.[0];
        const when = ts === undefined ? point?.name : tooltipFormatter.format(new Date(Number(ts)));
        return `${when}<br/>Check-ins: ${point?.value ?? 0}`;
      },
    }),
    grid: { left: 70, right: 40, bottom: 60, top: 100 },
    xAxis: {
      type: "category",
      data: labels,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { fontSize: 10, interval: getCategoryLabelInterval(labels.length, 10) },
    },
    yAxis: getValueAxisConfig(),
    series: [
      {
        name: "Check-ins",
        type: "bar",
        data: bins.map(([, count]) => Number(count)),
        ...getVerticalBarSeriesStyle(bins.length),
      },
    ],
  };
};

/**
 * Builds the fill curve chart option.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @returns {Object} ECharts option.
 */
const buildFillCurveOption = (stats, palette) => {
  const runningTotal = stats.traffic?.registrations_running_total || [];
  const days = runningTotal.map(([day]) => day);
  const uiColors = getChartUiColors();
  const capacity = stats.event?.capacity;
  const windowArea = buildRegistrationWindowArea(stats.audience, days, palette);

  return {
    textStyle: { fontFamily: dashboardFontFamily },
    title: getChartTitleConfig("Registrations over time", palette, "Cumulative registrations per UTC day"),
    color: [palette[700]],
    tooltip: getAxisTooltipConfig(),
    grid: { left: 70, right: 40, bottom: 60, top: 100 },
    xAxis: {
      type: "category",
      boundaryGap: false,
      data: days,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: {
        fontSize: 10,
        formatter: (value) => formatDayAxisLabel(value),
        interval: getCategoryLabelInterval(days.length, 8),
      },
    },
    yAxis: Object.assign(
      getValueAxisConfig(),
      capacity > 0 ? { max: (value) => Math.max(value.max, capacity) } : {},
    ),
    series: [
      {
        name: "Registrations",
        type: "line",
        ...getDailyLineSymbolConfig(days.length),
        lineStyle: { width: 2, color: palette[700] },
        areaStyle: { color: palette[500], opacity: 0.2 },
        data: runningTotal.map(([, total]) => Number(total)),
        ...(capacity > 0
          ? {
              markLine: {
                symbol: "none",
                silent: true,
                lineStyle: { color: uiColors.muted, type: "solid" },
                label: { formatter: `Capacity ${capacity}`, position: "insideEndTop", color: uiColors.text },
                data: [{ yAxis: capacity }],
              },
            }
          : {}),
        ...(windowArea ? { markArea: windowArea } : {}),
      },
    ],
  };
};

/**
 * Builds the registration window mark area of the fill curve, describing
 * inferred and capped bounds.
 * @param {Object} audience - Audience statistics.
 * @param {Array<string>} days - Chart day keys.
 * @param {Object} palette - Theme color palette.
 * @returns {Object|null} ECharts markArea config, or null outside the chart.
 */
const buildRegistrationWindowArea = (audience, days, palette) => {
  if (!audience?.window_starts_at || !audience?.window_ends_at || days.length === 0) {
    return null;
  }

  const toDay = (seconds) => new Date(Number(seconds) * 1000).toISOString().slice(0, 10);
  const startDay = [toDay(audience.window_starts_at), days[0]].sort().at(-1);
  const endDay = [toDay(audience.window_ends_at), days.at(-1)].sort()[0];
  if (startDay > endDay) {
    return null;
  }

  const notes = [];
  if (audience.window_start_inferred) {
    notes.push("opens at publication");
  }
  if (audience.window_end_capped) {
    notes.push("cut short");
  } else if (audience.window_end_inferred) {
    notes.push("no close set");
  }
  const isExplicit = notes.length === 0;

  return {
    silent: true,
    itemStyle: {
      borderColor: palette[400],
      borderType: isExplicit ? "solid" : "dashed",
      borderWidth: 1,
      color: palette[100],
      opacity: isExplicit ? 0.45 : 0.25,
    },
    label: {
      color: palette[900],
      fontSize: 10,
      formatter: notes.length ? `Registration window (${notes.join(", ")})` : "Registration window",
      position: "insideTop",
    },
    data: [[{ xAxis: startDay }, { xAxis: endDay }]],
  };
};

/**
 * Returns the day keys of the daily series.
 * @param {Object} stats - Event analytics payload.
 * @returns {Array<string>} YYYY-MM-DD day keys.
 */
const getChartDays = (stats) => {
  const firstSeries =
    stats.traffic?.views_by_source_per_day?.[0]?.series ||
    stats.traffic?.registrations_by_ticket_type_per_day?.[0]?.series ||
    stats.traffic?.registrations_running_total ||
    [];
  return firstSeries.map(([day]) => day);
};

/**
 * Builds the day markers of the daily charts.
 * @param {Object} stats - Event analytics payload.
 * @param {Array<string>} days - Chart day keys.
 * @returns {Object|null} ECharts markLine config.
 */
const getChartMarkers = (stats, days) => {
  return getDayMarkersConfig(stats.markers || [], {
    color: getChartUiColors().muted,
    days,
    labelForKind: (kind) => MARKER_LABELS[kind] || kind,
    timeZone: stats.event?.timezone || "UTC",
  });
};

/**
 * Returns the UTM dimension currently selected in a root.
 * @param {Element} root - Analytics root element.
 * @returns {string} Selected dimension.
 */
const getSelectedUtmDimension = (root) => {
  return root.querySelector('[data-utm-dimension][aria-pressed="true"]')?.dataset.utmDimension || "source";
};

/**
 * Returns the key identifying a views series across charts.
 * @param {Object} series - Views series.
 * @returns {string} Series key.
 */
const getViewsSeriesKey = (series) => {
  return series.kind === "source" ? `source:${series.source}` : series.kind;
};

/**
 * Sorts the combinations table by a column and syncs the column sort state.
 * @param {HTMLElement} sortButton - Column sort button.
 * @returns {void}
 */
const handleCombinationsSort = (sortButton) => {
  const table = sortButton.closest("table");
  const header = sortButton.closest("th");
  const tbody = table?.querySelector("tbody");
  if (!table || !header || !tbody) {
    return;
  }

  // Toggle the current column, or start with its natural direction
  const key = sortButton.dataset.utmSort;
  const currentDirection = header.getAttribute("aria-sort");
  let direction = NUMERIC_SORT_KEYS.has(key) ? "descending" : "ascending";
  if (currentDirection === "ascending") {
    direction = "descending";
  } else if (currentDirection === "descending") {
    direction = "ascending";
  }

  // Keep a single sorted column announced to assistive technologies
  table.querySelectorAll("th[aria-sort]").forEach((column) => {
    column.setAttribute("aria-sort", column === header ? direction : "none");
  });
  sortUtmCombinationRows(tbody, key, direction);
};

/**
 * Renders the check-ins chart.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @returns {void}
 */
const renderCheckInsChart = (stats, palette) => {
  const bins = stats.check_ins?.bins || [];
  renderChart(
    "event-check-ins-chart",
    buildCheckInsOption(stats.check_ins, palette, stats.event?.timezone || "UTC"),
    hasActivity(bins),
  );
};

/**
 * Renders the fill curve chart.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @returns {void}
 */
const renderFillCurveChart = (stats, palette) => {
  const runningTotal = stats.traffic?.registrations_running_total || [];
  renderChart("event-fill-curve-chart", buildFillCurveOption(stats, palette), hasActivity(runningTotal));
};

/**
 * Renders the registration funnel chart with count labels.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @param {boolean} hasEnded - Whether the event has ended.
 * @returns {void}
 */
const renderFunnelChart = (stats, palette, hasEnded) => {
  const stages = [
    { name: "Page views", value: Number(stats.traffic?.views_total || 0) },
    { name: "Registrations", value: Number(stats.enrollment?.registrations || 0) },
  ];
  if (hasEnded) {
    stages.push({ name: "Checked in", value: Number(stats.enrollment?.checked_in || 0) });
  }

  renderChart(
    "event-funnel-chart",
    createHorizontalBarChart("Registration funnel", stages, palette, {
      description: "Current registrations, conversion is approximate",
      inverse: true,
      showValueAxisLabels: false,
      valueLabel: "count",
    }),
    hasActivity(stages.map(({ value }) => value)),
  );
};

/**
 * Renders the registrations of each admission path with their share.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @returns {void}
 */
const renderRegistrationPathsChart = (stats, palette) => {
  const counts = stats.enrollment?.registrations_by_path || {};
  const paths = REGISTRATION_PATHS.map(([key, name]) => ({ name, value: Number(counts[key] || 0) })).filter(
    ({ value }) => value > 0,
  );

  renderChart(
    "event-registration-paths-chart",
    createHorizontalBarChart("Registration paths", paths, palette, {
      description: "Share of current registrations",
      inverse: true,
      percentBase: Number(stats.enrollment?.registrations || 0),
      showValueAxisLabels: false,
    }),
    paths.length > 0,
  );
};

/**
 * Renders the daily registrations chart stacked by ticket type.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @returns {void}
 */
const renderRegistrationsDailyChart = (stats, palette) => {
  const days = getChartDays(stats);
  const seriesData = (stats.traffic?.registrations_by_ticket_type_per_day || []).map((series) => ({
    name: getRegistrationsSeriesLabel(series, stats),
    data: series.series.map(([, count]) => Number(count)),
  }));

  renderChart(
    "event-registrations-daily-chart",
    createStackedDailyBarChart("Registrations per day", days, seriesData, palette, {
      description: "Stacked by ticket type, UTC days",
      markLine: getChartMarkers(stats, days),
    }),
    seriesData.some((series) => hasActivity(series.data)),
  );
};

/**
 * Renders the share of page views by the top sources, the other sources, the
 * attributed views without a source and the unattributed views.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @param {Map<string, string>} colors - Series colors.
 * @returns {void}
 */
const renderUtmShareChart = (stats, palette, colors) => {
  const bySource = stats.utm?.by_source || {};
  const values = bySource.values || [];
  const topValues = values.slice(0, SHARE_TOP_SOURCES);
  const otherSourcesViews =
    values.slice(SHARE_TOP_SOURCES).reduce((sum, { views }) => sum + Number(views), 0) +
    Number(bySource.remainder_views || 0);
  const untaggedViews = Number(stats.traffic?.views_total || 0) - Number(stats.utm?.tagged_views || 0);
  const slices = [
    ...topValues.map(({ value, views }) => ({
      color: colors.get(`source:${value}`),
      name: value,
      value: Number(views),
    })),
    { color: colors.get("other-sources"), name: VIEWS_SERIES_LABELS["other-sources"], value: otherSourcesViews },
    {
      color: colors.get("no-source"),
      name: VIEWS_SERIES_LABELS["no-source"],
      value: Number(bySource.not_specified || 0),
    },
    { color: colors.get("untagged"), name: VIEWS_SERIES_LABELS.untagged, value: untaggedViews },
  ].filter((slice) => slice.value > 0);

  renderChart(
    "event-utm-share-chart",
    createPieChart(
      "Page views by source",
      "Page views",
      slices.map(({ name, value }) => ({ name, value })),
      palette,
      {
        colors: slices.map(({ color }) => color),
        description: "Share of all page views",
        groupTail: false,
        legendPosition: "bottom",
      },
    ),
    stats.traffic?.attribution_consistent === true && slices.length > 0,
  );
};

/**
 * Renders the views of one UTM dimension as horizontal bars.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @param {string} dimension - UTM dimension: source, medium or campaign.
 * @returns {void}
 */
const renderUtmValuesChart = (stats, palette, dimension) => {
  const dimensionStats = stats.utm?.[`by_${dimension}`] || {};
  const categories = (dimensionStats.values || []).map(({ value, views }) => ({
    name: value,
    value: Number(views),
  }));
  if (Number(dimensionStats.not_specified) > 0) {
    categories.push({ name: NOT_SPECIFIED_LABEL, value: Number(dimensionStats.not_specified) });
  }
  if (Number(dimensionStats.remainder_count) > 0) {
    categories.push({
      name: `Other (${dimensionStats.remainder_count} values)`,
      value: Number(dimensionStats.remainder_views),
    });
  }

  const isConsistent = stats.traffic?.attribution_consistent === true;
  renderChart(
    "event-utm-values-chart",
    createHorizontalBarChart(`Page views by ${dimension}`, categories, palette, {
      description: isConsistent ? "Share of all page views" : "Attributed page views",
      inverse: true,
      percentBase: Number(stats.traffic?.views_total || 0),
      showValueAxisLabels: false,
      valueLabel: isConsistent ? "percent" : "count",
    }),
    categories.length > 0,
  );
};

/**
 * Renders the daily views chart stacked by source, or as raw totals when the
 * attribution is inconsistent.
 * @param {Object} stats - Event analytics payload.
 * @param {Object} palette - Theme color palette.
 * @param {Map<string, string>} colors - Series colors.
 * @returns {void}
 */
const renderViewsDailyChart = (stats, palette, colors) => {
  const days = getChartDays(stats);
  const viewsSeries = stats.traffic?.views_by_source_per_day || [];
  let seriesData = viewsSeries.map((series) => ({
    color: colors.get(getViewsSeriesKey(series)),
    data: series.series.map(([, count]) => Number(count)),
    name: getViewsSeriesLabel(series),
  }));

  // Inconsistent attribution falls back to a single total series
  if (stats.traffic?.attribution_consistent !== true) {
    seriesData = [
      {
        data: days.map((_, index) => seriesData.reduce((sum, series) => sum + (series.data[index] || 0), 0)),
        name: "Page views",
      },
    ];
  }

  renderChart(
    "event-views-daily-chart",
    createStackedDailyBarChart("Page views per day", days, seriesData, palette, {
      description:
        stats.traffic?.attribution_consistent === true
          ? "Stacked by UTM source, UTC days"
          : "Total page views, UTC days",
      markLine: getChartMarkers(stats, days),
    }),
    seriesData.some((series) => hasActivity(series.data)),
  );
};

initializeOnReadyAndHtmxLoad(initializeEventAnalyticsFromPage);
