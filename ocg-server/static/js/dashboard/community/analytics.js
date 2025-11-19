/** Read community theme colors from CSS variables. */
function getThemePalette() {
  const styles = getComputedStyle(document.documentElement);
  const palette = {
    50: styles.getPropertyValue('--color-primary-50').trim(),
    100: styles.getPropertyValue('--color-primary-100').trim(),
    200: styles.getPropertyValue('--color-primary-200').trim(),
    300: styles.getPropertyValue('--color-primary-300').trim(),
    400: styles.getPropertyValue('--color-primary-400').trim(),
    500: styles.getPropertyValue('--color-primary-500').trim(),
    600: styles.getPropertyValue('--color-primary-600').trim(),
    700: styles.getPropertyValue('--color-primary-700').trim(),
    800: styles.getPropertyValue('--color-primary-800').trim(),
    900: styles.getPropertyValue('--color-primary-900').trim(),
  };

  const fallback = palette[700] || palette[500];
  Object.entries(palette).forEach(([key, value]) => {
    if (!value) {
      palette[key] = fallback;
    }
  });

  return palette;
}

/** Keep typography aligned with dashboard typography. */
const fontFamily =
  '"Inter", "ui-sans-serif", "system-ui", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "sans-serif"';

/**
 * Cast stats tuples into ECharts-friendly time series.
 * @param {Array<[number|string, number|string]>} points - Timestamp/value pairs.
 * @returns {Array<[number, number]>} Normalized series.
 */
function toTimeSeries(points = []) {
  return points.map(([ts, value]) => [Number(ts), Number(value)]);
}

/**
 * Normalize category/value tuples for charts.
 * @param {Array<[string, number|string]>} pairs - Category/value pairs.
 * @returns {Array<{name: string, value: number}>} Labeled series.
 */
function toCategorySeries(pairs = []) {
  return pairs.map(([label, value]) => ({ name: label, value: Number(value) }));
}

/**
 * Initialize an ECharts instance if the element and library are available.
 * @param {string} elementId - Target element id.
 * @param {Object} option - ECharts option object.
 * @returns {echarts.ECharts | null} Chart instance or null when unavailable.
 */
function initChart(elementId, option) {
  const el = document.getElementById(elementId);
  if (!el || typeof echarts === 'undefined') {
    return null;
  }

  const chart = echarts.init(el);
  chart.setOption(option);
  return chart;
}

/**
 * Shared typography configuration for charts.
 * @returns {Object} Text styling options.
 */
function baseText() {
  return {
    textStyle: { fontFamily },
    legend: { textStyle: { fontFamily } },
    tooltip: { textStyle: { fontFamily } },
  };
}

/**
 * Create area chart configuration for running totals.
 * @param {string} title - Chart title.
 * @param {string} name - Series name.
 * @param {Array} data - Time series data.
 * @param {Object} palette - Theme color palette.
 * @returns {Object} ECharts option.
 */
function createAreaChart(title, name, data, palette) {
  return Object.assign(baseText(), {
    title: {
      text: title,
      left: 'center',
      top: 12,
      textStyle: { fontFamily, fontSize: 14, fontWeight: 500, color: '#334155' },
    },
    color: [palette[700]],
    tooltip: {
      trigger: 'axis',
      backgroundColor: '#fff',
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: '#334155' },
    },
    grid: { left: 70, right: 40, bottom: 70, top: 80 },
    xAxis: {
      type: 'time',
      boundaryGap: false,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: '#94a3b8', fontSize: 11 },
      splitLine: { show: false },
    },
    yAxis: {
      type: 'value',
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: '#94a3b8', fontSize: 11 },
      splitLine: { lineStyle: { color: '#f1f5f9', type: 'dashed' } },
    },
    series: [
      {
        name,
        type: 'line',
        smooth: true,
        symbol: 'none',
        showSymbol: false,
        lineStyle: { width: 2, color: palette[700] },
        areaStyle: {
          color: {
            type: 'linear',
            x: 0,
            y: 0,
            x2: 0,
            y2: 1,
            colorStops: [
              { offset: 0, color: palette[500] },
              { offset: 1, color: 'rgba(255, 255, 255, 0)' },
            ],
          },
        },
        data: toTimeSeries(data),
      },
    ],
  });
}

/**
 * Create vertical bar chart configuration for monthly data.
 * @param {string} title - Chart title.
 * @param {string} name - Series name.
 * @param {Array} data - Monthly data pairs.
 * @param {Object} palette - Theme color palette.
 * @returns {Object} ECharts option.
 */
function createMonthlyBarChart(title, name, data, palette) {
  return Object.assign(baseText(), {
    title: {
      text: title,
      left: 'center',
      top: 12,
      textStyle: { fontFamily, fontSize: 14, fontWeight: 500, color: '#334155' },
    },
    color: [palette[700]],
    tooltip: {
      trigger: 'axis',
      backgroundColor: '#fff',
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: '#334155' },
    },
    grid: { left: 70, right: 40, bottom: 90, top: 80 },
    xAxis: {
      type: 'category',
      data: (data || []).map((d) => d[0]),
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { rotate: 45, color: '#94a3b8', fontSize: 10 },
    },
    yAxis: {
      type: 'value',
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: '#94a3b8', fontSize: 11 },
      splitLine: { lineStyle: { color: '#f1f5f9', type: 'dashed' } },
    },
    series: [
      {
        name,
        type: 'bar',
        data: (data || []).map((d) => Number(d[1])),
        barCategoryGap: '30%',
      },
    ],
  });
}

/**
 * Build a palette for multi-series charts.
 * @param {Object} palette - Theme color palette.
 * @param {number} count - Number of series.
 * @returns {Array<string>} Color list sized to the series count.
 */
function buildSeriesColors(palette, count) {
  const baseColors = [
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

  if (count <= baseColors.length) {
    return baseColors.slice(0, count);
  }

  const colors = [];
  for (let i = 0; i < count; i += 1) {
    colors.push(baseColors[i % baseColors.length]);
  }
  return colors;
}

/**
 * Normalize monthly series maps into aligned stacks.
 * @param {Object<string, Array<[string, number|string]>>} seriesMap - Named series.
 * @returns {{months: Array<string>, series: Array<{name: string, data: Array<number>}>}} Aligned data.
 */
function buildStackedMonthlySeries(seriesMap = {}) {
  const monthsSet = new Set();
  Object.values(seriesMap).forEach((points) => {
    (points || []).forEach(([month]) => monthsSet.add(month));
  });

  const months = Array.from(monthsSet).sort();
  const seriesNames = Object.keys(seriesMap).sort((a, b) => a.localeCompare(b));

  return {
    months,
    series: seriesNames.map((name) => {
      const valuesByMonth = new Map(
        (seriesMap[name] || []).map(([month, value]) => [month, Number(value)])
      );
      return { name, data: months.map((month) => valuesByMonth.get(month) ?? 0) };
    }),
  };
}

/**
 * Normalize time-based series maps into aligned stacks.
 * @param {Object<string, Array<[number|string, number|string]>>} seriesMap - Named series.
 * @returns {{timestamps: Array<number>, series: Array<{name: string, data: Array<[number, number]>}>}} Aligned series.
 */
function buildStackedTimeSeries(seriesMap = {}) {
  const timestamps = new Set();
  Object.values(seriesMap).forEach((points) => {
    (points || []).forEach(([ts]) => timestamps.add(Number(ts)));
  });

  const sortedTs = Array.from(timestamps).sort((a, b) => a - b);
  const seriesNames = Object.keys(seriesMap).sort((a, b) => a.localeCompare(b));

  return {
    timestamps: sortedTs,
    series: seriesNames.map((name) => {
      const valuesByTs = new Map(
        (seriesMap[name] || []).map(([ts, value]) => [Number(ts), Number(value)])
      );
      let last = 0;
      return {
        name,
        data: sortedTs.map((ts) => {
          const value = valuesByTs.get(ts);
          if (typeof value === 'number') {
            last = value;
          }
          return [ts, last];
        }),
      };
    }),
  };
}

/**
 * Create stacked monthly bar chart configuration for grouped series.
 * @param {string} title - Chart title.
 * @param {Array<string>} months - Month labels.
 * @param {Array<{name: string, data: Array<number>}>} seriesData - Aligned series data.
 * @param {Object} palette - Theme color palette.
 * @returns {Object} ECharts option.
 */
function createStackedMonthlyChart(title, months, seriesData, palette) {
  const colors = buildSeriesColors(palette, seriesData.length || 1);

  return Object.assign(baseText(), {
    title: {
      text: title,
      left: 'center',
      top: 12,
      textStyle: { fontFamily, fontSize: 14, fontWeight: 500, color: '#334155' },
    },
    color: colors,
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      backgroundColor: '#fff',
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: '#334155' },
    },
    legend: {
      type: seriesData.length > 5 ? 'scroll' : 'plain',
      bottom: 10,
      left: 'center',
      textStyle: { fontFamily, fontSize: 12, color: '#475569' },
    },
    grid: { left: 70, right: 40, bottom: 140, top: 80 },
    xAxis: {
      type: 'category',
      data: months,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { rotate: 45, color: '#94a3b8', fontSize: 10 },
    },
    yAxis: {
      type: 'value',
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: '#94a3b8', fontSize: 11 },
      splitLine: { lineStyle: { color: '#f1f5f9', type: 'dashed' } },
    },
    series: seriesData.map((series) => ({
      name: series.name,
      type: 'bar',
      stack: 'total',
      emphasis: { focus: 'series' },
      data: series.data,
      barCategoryGap: '35%',
    })),
  });
}

/**
 * Create stacked area chart configuration for grouped running totals.
 * @param {string} title - Chart title.
 * @param {Array<{name: string, data: Array<[number, number]>}>} seriesData - Aligned series data.
 * @param {Object} palette - Theme color palette.
 * @returns {Object} ECharts option.
 */
function createStackedAreaChart(title, seriesData, palette) {
  const colors = buildSeriesColors(palette, seriesData.length || 1);

  return Object.assign(baseText(), {
    title: {
      text: title,
      left: 'center',
      top: 12,
      textStyle: { fontFamily, fontSize: 14, fontWeight: 500, color: '#334155' },
    },
    color: colors,
    tooltip: {
      trigger: 'axis',
      backgroundColor: '#fff',
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: '#334155' },
    },
    legend: {
      type: seriesData.length > 5 ? 'scroll' : 'plain',
      bottom: 10,
      left: 'center',
      textStyle: { fontFamily, fontSize: 12, color: '#475569' },
    },
    grid: { left: 70, right: 40, bottom: 120, top: 60 },
    xAxis: {
      type: 'time',
      boundaryGap: false,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: '#94a3b8', fontSize: 11 },
      splitLine: { show: false },
    },
    yAxis: {
      type: 'value',
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: '#94a3b8', fontSize: 11 },
      splitLine: { lineStyle: { color: '#f1f5f9', type: 'dashed' } },
    },
    series: seriesData.map((series) => ({
      name: series.name,
      type: 'line',
      stack: 'total',
      smooth: true,
      symbol: 'none',
      showSymbol: false,
      areaStyle: { opacity: 0.35 },
      lineStyle: { width: 2 },
      emphasis: { focus: 'series' },
      data: series.data,
    })),
  });
}

/**
 * Create horizontal bar chart configuration for category data.
 * @param {string} title - Chart title.
 * @param {Array} categoryData - Category series data.
 * @param {Object} palette - Theme color palette.
 * @param {number} leftMargin - Left margin for labels.
 * @returns {Object} ECharts option.
 */
function createHorizontalBarChart(title, categoryData, palette, leftMargin = 140) {
  // Calculate total for percentages
  const total = categoryData.reduce((sum, d) => sum + d.value, 0);

  return Object.assign(baseText(), {
    title: {
      text: title,
      left: 'center',
      top: 12,
      textStyle: { fontFamily, fontSize: 14, fontWeight: 500, color: '#334155' },
    },
    color: [palette[700]],
    tooltip: {
      trigger: 'item',
      backgroundColor: '#fff',
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: '#334155' },
      formatter: (params) => {
        const percent = total > 0 ? ((params.value / total) * 100).toFixed(1) : 0;
        return `${params.name}: ${params.value} (${percent}%)`;
      },
    },
    grid: { left: leftMargin, right: 80, bottom: 40, top: 80 },
    xAxis: {
      type: 'value',
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: '#94a3b8', fontSize: 11 },
      splitLine: { lineStyle: { color: '#f1f5f9', type: 'dashed' } },
    },
    yAxis: {
      type: 'category',
      data: categoryData.map((d) => d.name),
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: '#334155', fontSize: 12 },
    },
    series: [
      {
        type: 'bar',
        data: categoryData.map((d) => d.value),
        barCategoryGap: '30%',
        label: {
          show: true,
          position: 'right',
          formatter: (params) => {
            const percent = total > 0 ? ((params.value / total) * 100).toFixed(1) : 0;
            return `${percent}%`;
          },
          fontSize: 11,
          color: '#64748b',
        },
      },
    ],
  });
}

/**
 * Create pie chart configuration for distribution data.
 * @param {string} title - Chart title.
 * @param {string} name - Series name.
 * @param {Array} data - Category series data.
 * @param {Object} palette - Theme color palette.
 * @returns {Object} ECharts option.
 */
function createPieChart(title, name, data, palette) {
  // Generate monochromatic color shades for pie slices
  const pieColors = [
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

  // Limit to top 6 entries, group rest as "Other"
  let chartData = data;
  if (data.length > 6) {
    const sorted = [...data].sort((a, b) => b.value - a.value);
    const top6 = sorted.slice(0, 6);
    const otherValue = sorted.slice(6).reduce((sum, item) => sum + item.value, 0);
    if (otherValue > 0) {
      top6.push({ name: 'Other', value: otherValue });
    }
    chartData = top6;
  }

  return Object.assign(baseText(), {
    title: {
      text: title,
      left: 'center',
      top: 12,
      textStyle: { fontFamily, fontSize: 14, fontWeight: 500, color: '#334155' },
    },
    color: pieColors,
    tooltip: {
      trigger: 'item',
      backgroundColor: '#fff',
      borderColor: palette[100],
      borderWidth: 1,
      textStyle: { color: '#334155' },
      formatter: '{b}: {c} ({d}%)',
    },
    legend: {
      orient: 'vertical',
      left: '55%',
      top: '30%',
      icon: 'circle',
      itemWidth: 10,
      itemHeight: 10,
      itemGap: 12,
      textStyle: { fontFamily, fontSize: 14, color: '#334155' },
      formatter: (name) => {
        if (name.length > 25) {
          return name.substring(0, 25) + '...';
        }
        return name;
      },
    },
    series: [
      {
        name,
        type: 'pie',
        radius: ['30%', '55%'],
        center: ['28%', '58%'],
        avoidLabelOverlap: true,
        itemStyle: { borderColor: '#fff', borderWidth: 2 },
        label: {
          show: true,
          position: 'outside',
          formatter: '{d}%',
          fontSize: 11,
          color: '#64748b',
        },
        labelLine: {
          show: true,
          length: 8,
          length2: 6,
          lineStyle: { color: '#cbd5e1' },
        },
        emphasis: {
          label: { fontWeight: 'bold' },
        },
        data: chartData,
      },
    ],
  });
}

/**
 * Render all analytics charts for the community dashboard.
 * @param {Object} stats - Community statistics payload from the server.
 */
export function initAnalyticsCharts(stats) {
  if (!stats || typeof echarts === 'undefined') {
    return;
  }

  const palette = getThemePalette();
  const activeCharts = [];
  const groups = stats.groups || {};
  const members = stats.members || {};
  const events = stats.events || {};
  const attendees = stats.attendees || {};

  // Groups: cumulative trend (area chart)
  const groupsRunningChart = initChart(
    'groups-running-chart',
    createAreaChart('Groups over time', 'Groups', groups.running_total || [], palette)
  );
  if (groupsRunningChart) activeCharts.push(groupsRunningChart);

  // Groups: monthly additions (bar chart)
  const groupsMonthlyChart = initChart(
    'groups-monthly-chart',
    createMonthlyBarChart('New Groups per Month', 'Groups', groups.per_month, palette)
  );
  if (groupsMonthlyChart) activeCharts.push(groupsMonthlyChart);

  // Groups: by category (horizontal bar chart)
  const groupsCategory = toCategorySeries(groups.total_by_category || []);
  const groupsCategoryChart = initChart(
    'groups-category-chart',
    createHorizontalBarChart('Groups by Category', groupsCategory, palette)
  );
  if (groupsCategoryChart) activeCharts.push(groupsCategoryChart);

  // Groups: by region (pie chart)
  const groupsRegion = toCategorySeries(groups.total_by_region || []);
  const groupsRegionChart = initChart(
    'groups-region-chart',
    createPieChart('Groups by Region', 'Groups', groupsRegion, palette)
  );
  if (groupsRegionChart) activeCharts.push(groupsRegionChart);

  // Groups: running total by category (stacked area chart)
  const groupsRunningByCategory = buildStackedTimeSeries(groups.running_total_by_category || {});
  const groupsRunningCategoryChart = initChart(
    'groups-running-category-chart',
    createStackedAreaChart(
      'Groups over time by category',
      groupsRunningByCategory.series,
      palette
    )
  );
  if (groupsRunningCategoryChart) activeCharts.push(groupsRunningCategoryChart);

  // Groups: running total by region (stacked area chart)
  const groupsRunningByRegion = buildStackedTimeSeries(groups.running_total_by_region || {});
  const groupsRunningRegionChart = initChart(
    'groups-running-region-chart',
    createStackedAreaChart('Groups over time by region', groupsRunningByRegion.series, palette)
  );
  if (groupsRunningRegionChart) activeCharts.push(groupsRunningRegionChart);

  // Groups: per-month by category (stacked bar chart)
  const groupsMonthlyByCategory = buildStackedMonthlySeries(groups.per_month_by_category || {});
  const groupsMonthlyCategoryChart = initChart(
    'groups-monthly-category-chart',
    createStackedMonthlyChart(
      'New Groups per Month by category',
      groupsMonthlyByCategory.months,
      groupsMonthlyByCategory.series,
      palette
    )
  );
  if (groupsMonthlyCategoryChart) activeCharts.push(groupsMonthlyCategoryChart);

  // Groups: per-month by region (stacked bar chart)
  const groupsMonthlyByRegion = buildStackedMonthlySeries(groups.per_month_by_region || {});
  const groupsMonthlyRegionChart = initChart(
    'groups-monthly-region-chart',
    createStackedMonthlyChart(
      'New Groups per Month by region',
      groupsMonthlyByRegion.months,
      groupsMonthlyByRegion.series,
      palette
    )
  );
  if (groupsMonthlyRegionChart) activeCharts.push(groupsMonthlyRegionChart);

  // Members: per-month by category (stacked bar chart)
  const membersMonthlyByCategory = buildStackedMonthlySeries(members.per_month_by_category || {});
  const membersMonthlyCategoryChart = initChart(
    'members-monthly-category-chart',
    createStackedMonthlyChart(
      'New Members per Month by category',
      membersMonthlyByCategory.months,
      membersMonthlyByCategory.series,
      palette
    )
  );
  if (membersMonthlyCategoryChart) activeCharts.push(membersMonthlyCategoryChart);

  // Members: per-month by region (stacked bar chart)
  const membersMonthlyByRegion = buildStackedMonthlySeries(members.per_month_by_region || {});
  const membersMonthlyRegionChart = initChart(
    'members-monthly-region-chart',
    createStackedMonthlyChart(
      'New Members per Month by region',
      membersMonthlyByRegion.months,
      membersMonthlyByRegion.series,
      palette
    )
  );
  if (membersMonthlyRegionChart) activeCharts.push(membersMonthlyRegionChart);

  // Members: cumulative trend (area chart)
  const membersRunningChart = initChart(
    'members-running-chart',
    createAreaChart('Members over time', 'Members', members.running_total || [], palette)
  );
  if (membersRunningChart) activeCharts.push(membersRunningChart);

  // Members: monthly (bar chart)
  const membersMonthlyChart = initChart(
    'members-monthly-chart',
    createMonthlyBarChart('New Members per Month', 'Members', members.per_month, palette)
  );
  if (membersMonthlyChart) activeCharts.push(membersMonthlyChart);

  // Members: by category (horizontal bar chart)
  const membersCategory = toCategorySeries(members.total_by_category || []);
  const membersCategoryChart = initChart(
    'members-category-chart',
    createHorizontalBarChart('Members by Group Category', membersCategory, palette)
  );
  if (membersCategoryChart) activeCharts.push(membersCategoryChart);

  // Members: by region (pie chart)
  const membersRegion = toCategorySeries(members.total_by_region || []);
  const membersRegionChart = initChart(
    'members-region-chart',
    createPieChart('Members by Region', 'Members', membersRegion, palette)
  );
  if (membersRegionChart) activeCharts.push(membersRegionChart);

  // Members: running total by category (stacked area chart)
  const membersRunningByCategory = buildStackedTimeSeries(members.running_total_by_category || {});
  const membersRunningCategoryChart = initChart(
    'members-running-category-chart',
    createStackedAreaChart(
      'Members over time by category',
      membersRunningByCategory.series,
      palette
    )
  );
  if (membersRunningCategoryChart) activeCharts.push(membersRunningCategoryChart);

  // Members: running total by region (stacked area chart)
  const membersRunningByRegion = buildStackedTimeSeries(members.running_total_by_region || {});
  const membersRunningRegionChart = initChart(
    'members-running-region-chart',
    createStackedAreaChart('Members over time by region', membersRunningByRegion.series, palette)
  );
  if (membersRunningRegionChart) activeCharts.push(membersRunningRegionChart);

  // Events: cumulative trend (area chart)
  const eventsRunningChart = initChart(
    'events-running-chart',
    createAreaChart('Events over time', 'Events', events.running_total || [], palette)
  );
  if (eventsRunningChart) activeCharts.push(eventsRunningChart);

  // Events: monthly (bar chart)
  const eventsMonthlyChart = initChart(
    'events-monthly-chart',
    createMonthlyBarChart('New Events per Month', 'Events', events.per_month, palette)
  );
  if (eventsMonthlyChart) activeCharts.push(eventsMonthlyChart);

  // Events: by group category (horizontal bar chart)
  const eventsGroupCategory = toCategorySeries(events.total_by_group_category || []);
  const eventsGroupCategoryChart = initChart(
    'events-group-category-chart',
    createHorizontalBarChart('Events by Group Category', eventsGroupCategory, palette)
  );
  if (eventsGroupCategoryChart) activeCharts.push(eventsGroupCategoryChart);

  // Events: by region (pie chart)
  const eventsRegion = toCategorySeries(events.total_by_group_region || []);
  const eventsRegionChart = initChart(
    'events-region-chart',
    createPieChart('Events by Region', 'Events', eventsRegion, palette)
  );
  if (eventsRegionChart) activeCharts.push(eventsRegionChart);

  // Events: by event category (horizontal bar chart)
  const eventsCategory = toCategorySeries(events.total_by_event_category || []);
  const eventsCategoryChart = initChart(
    'events-category-chart',
    createHorizontalBarChart('Events by Type', eventsCategory, palette)
  );
  if (eventsCategoryChart) activeCharts.push(eventsCategoryChart);

  // Events: running total by group category (stacked area chart)
  const eventsRunningByGroupCategory = buildStackedTimeSeries(
    events.running_total_by_group_category || {}
  );
  const eventsRunningGroupCategoryChart = initChart(
    'events-running-group-category-chart',
    createStackedAreaChart(
      'Events over time by group category',
      eventsRunningByGroupCategory.series,
      palette
    )
  );
  if (eventsRunningGroupCategoryChart) activeCharts.push(eventsRunningGroupCategoryChart);

  // Events: running total by group region (stacked area chart)
  const eventsRunningByGroupRegion = buildStackedTimeSeries(events.running_total_by_group_region || {});
  const eventsRunningGroupRegionChart = initChart(
    'events-running-group-region-chart',
    createStackedAreaChart(
      'Events over time by group region',
      eventsRunningByGroupRegion.series,
      palette
    )
  );
  if (eventsRunningGroupRegionChart) activeCharts.push(eventsRunningGroupRegionChart);

  // Events: running total by event category (stacked area chart)
  const eventsRunningByEventCategory = buildStackedTimeSeries(
    events.running_total_by_event_category || {}
  );
  const eventsRunningEventCategoryChart = initChart(
    'events-running-event-category-chart',
    createStackedAreaChart(
      'Events over time by event category',
      eventsRunningByEventCategory.series,
      palette
    )
  );
  if (eventsRunningEventCategoryChart) activeCharts.push(eventsRunningEventCategoryChart);

  // Events: per-month by group category (stacked bar chart)
  const eventsMonthlyByGroupCategory = buildStackedMonthlySeries(
    events.per_month_by_group_category || {}
  );
  const eventsMonthlyGroupCategoryChart = initChart(
    'events-monthly-group-category-chart',
    createStackedMonthlyChart(
      'New Events per Month by group category',
      eventsMonthlyByGroupCategory.months,
      eventsMonthlyByGroupCategory.series,
      palette
    )
  );
  if (eventsMonthlyGroupCategoryChart) activeCharts.push(eventsMonthlyGroupCategoryChart);

  // Events: per-month by group region (stacked bar chart)
  const eventsMonthlyByGroupRegion = buildStackedMonthlySeries(events.per_month_by_group_region || {});
  const eventsMonthlyGroupRegionChart = initChart(
    'events-monthly-group-region-chart',
    createStackedMonthlyChart(
      'New Events per Month by group region',
      eventsMonthlyByGroupRegion.months,
      eventsMonthlyByGroupRegion.series,
      palette
    )
  );
  if (eventsMonthlyGroupRegionChart) activeCharts.push(eventsMonthlyGroupRegionChart);

  // Events: per-month by event category (stacked bar chart)
  const eventsMonthlyByEventCategory = buildStackedMonthlySeries(events.per_month_by_event_category || {});
  const eventsMonthlyEventCategoryChart = initChart(
    'events-monthly-event-category-chart',
    createStackedMonthlyChart(
      'New Events per Month by event category',
      eventsMonthlyByEventCategory.months,
      eventsMonthlyByEventCategory.series,
      palette
    )
  );
  if (eventsMonthlyEventCategoryChart) activeCharts.push(eventsMonthlyEventCategoryChart);

  // Attendees: cumulative (area chart)
  const attendeesRunningChart = initChart(
    'attendees-running-chart',
    createAreaChart('Attendees over time', 'Attendees', attendees.running_total || [], palette)
  );
  if (attendeesRunningChart) activeCharts.push(attendeesRunningChart);

  // Attendees: monthly (bar chart)
  const attendeesMonthlyChart = initChart(
    'attendees-monthly-chart',
    createMonthlyBarChart('New Attendees per Month', 'Attendees', attendees.per_month, palette)
  );
  if (attendeesMonthlyChart) activeCharts.push(attendeesMonthlyChart);

  // Attendees: by event category (horizontal bar chart)
  const attendeesCategory = toCategorySeries(attendees.total_by_event_category || []);
  const attendeesCategoryChart = initChart(
    'attendees-category-chart',
    createHorizontalBarChart('Attendees by Event Type', attendeesCategory, palette)
  );
  if (attendeesCategoryChart) activeCharts.push(attendeesCategoryChart);

  // Attendees: by region (pie chart)
  const attendeesRegion = toCategorySeries(attendees.total_by_group_region || []);
  const attendeesRegionChart = initChart(
    'attendees-region-chart',
    createPieChart('Attendees by Region', 'Attendees', attendeesRegion, palette)
  );
  if (attendeesRegionChart) activeCharts.push(attendeesRegionChart);

  // Attendees: running total by group category (stacked area chart)
  const attendeesRunningByGroupCategory = buildStackedTimeSeries(
    attendees.running_total_by_group_category || {}
  );
  const attendeesRunningGroupCategoryChart = initChart(
    'attendees-running-group-category-chart',
    createStackedAreaChart(
      'Attendees over time by group category',
      attendeesRunningByGroupCategory.series,
      palette
    )
  );
  if (attendeesRunningGroupCategoryChart) activeCharts.push(attendeesRunningGroupCategoryChart);

  // Attendees: running total by group region (stacked area chart)
  const attendeesRunningByGroupRegion = buildStackedTimeSeries(
    attendees.running_total_by_group_region || {}
  );
  const attendeesRunningGroupRegionChart = initChart(
    'attendees-running-group-region-chart',
    createStackedAreaChart(
      'Attendees over time by group region',
      attendeesRunningByGroupRegion.series,
      palette
    )
  );
  if (attendeesRunningGroupRegionChart) activeCharts.push(attendeesRunningGroupRegionChart);

  // Attendees: running total by event category (stacked area chart)
  const attendeesRunningByEventCategory = buildStackedTimeSeries(
    attendees.running_total_by_event_category || {}
  );
  const attendeesRunningEventCategoryChart = initChart(
    'attendees-running-event-category-chart',
    createStackedAreaChart(
      'Attendees over time by event category',
      attendeesRunningByEventCategory.series,
      palette
    )
  );
  if (attendeesRunningEventCategoryChart) activeCharts.push(attendeesRunningEventCategoryChart);

  // Attendees: per-month by group category (stacked bar chart)
  const attendeesMonthlyByGroupCategory = buildStackedMonthlySeries(
    attendees.per_month_by_group_category || {}
  );
  const attendeesMonthlyGroupCategoryChart = initChart(
    'attendees-monthly-group-category-chart',
    createStackedMonthlyChart(
      'New Attendees per Month by group category',
      attendeesMonthlyByGroupCategory.months,
      attendeesMonthlyByGroupCategory.series,
      palette
    )
  );
  if (attendeesMonthlyGroupCategoryChart) activeCharts.push(attendeesMonthlyGroupCategoryChart);

  // Attendees: per-month by group region (stacked bar chart)
  const attendeesMonthlyByGroupRegion = buildStackedMonthlySeries(
    attendees.per_month_by_group_region || {}
  );
  const attendeesMonthlyGroupRegionChart = initChart(
    'attendees-monthly-group-region-chart',
    createStackedMonthlyChart(
      'New Attendees per Month by group region',
      attendeesMonthlyByGroupRegion.months,
      attendeesMonthlyByGroupRegion.series,
      palette
    )
  );
  if (attendeesMonthlyGroupRegionChart) activeCharts.push(attendeesMonthlyGroupRegionChart);

  // Attendees: per-month by event category (stacked bar chart)
  const attendeesMonthlyByEventCategory = buildStackedMonthlySeries(
    attendees.per_month_by_event_category || {}
  );
  const attendeesMonthlyEventCategoryChart = initChart(
    'attendees-monthly-event-category-chart',
    createStackedMonthlyChart(
      'New Attendees per Month by event category',
      attendeesMonthlyByEventCategory.months,
      attendeesMonthlyByEventCategory.series,
      palette
    )
  );
  if (attendeesMonthlyEventCategoryChart) activeCharts.push(attendeesMonthlyEventCategoryChart);

  window.addEventListener('resize', () => {
    activeCharts.forEach((chart) => chart.resize());
  });
}
