import { expect } from "@open-wc/testing";

import { disposeChartsWithin } from "/static/js/common/charts/stats.js";
import {
  formatCheckInBinLabels,
  getRegistrationsSeriesLabel,
  groupOtherViewsSeries,
  initEventAnalyticsCharts,
  initializeEventAnalyticsFromPage,
  toggleQuestionOptions,
} from "/static/js/dashboard/group/event-analytics.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const CHART_IDS = [
  "event-check-ins-chart",
  "event-fill-curve-chart",
  "event-funnel-chart",
  "event-registration-paths-chart",
  "event-registrations-daily-chart",
  "event-utm-share-chart",
  "event-utm-values-chart",
  "event-views-daily-chart",
];

const DAYS = ["2025-03-01", "2025-03-02", "2025-03-03"];

/** Builds a day series aligned with the fixture days. */
const daySeries = (counts) => DAYS.map((day, index) => [day, counts[index]]);

/** Builds an event analytics payload shaped like the server JSON. */
const getEventAnalyticsPayload = () => ({
  audience: {
    questions: [
      {
        kind: "multi-select",
        options: [
          { count: 3, label: "AI", option_id: "o1" },
          { count: 1, label: "Cloud", option_id: "o2" },
        ],
        prompt: "Interests",
        question_id: "q1",
        respondents: 3,
        selections: 4,
      },
    ],
    window_end_capped: true,
    window_end_inferred: false,
    window_start_inferred: true,
    members_joined_in_window: 2,
    members_joined_in_window_registered: 1,
    new_attendees: 3,
    returning_attendees: 1,
    window_ends_at: Date.UTC(2025, 2, 3, 12) / 1000,
    window_starts_at: Date.UTC(2025, 2, 1, 10) / 1000,
  },
  check_ins: {
    bin_minutes: 15,
    bins: [
      [Date.UTC(2025, 2, 3, 16, 45), 1],
      [Date.UTC(2025, 2, 3, 17, 0), 2],
    ],
    outside_range: 0,
  },
  enrollment: {
    admission_offers: [],
    cancellations: 0,
    checked_in: 3,
    invitation_requests: { accepted: 0, pending: 0, rejected: 0 },
    registrations: 4,
    registrations_by_path: { approval: 1, direct: 3, organizer_invitation: 0, unknown: 0, waitlist: 0 },
    waitlist: 0,
  },
  event: {
    canceled: false,
    is_paid: true,
    published: true,
    timezone: "Europe/Madrid",
    capacity: 10,
    ends_at: Date.UTC(2025, 2, 3, 19) / 1000,
    published_at: Date.UTC(2025, 2, 1, 10) / 1000,
    registration_ends_at: null,
    registration_starts_at: null,
    starts_at: Date.UTC(2025, 2, 3, 17) / 1000,
  },
  markers: [
    { kind: "published", ts: Date.UTC(2025, 2, 1, 10) / 1000 },
    { kind: "event-start", ts: Date.UTC(2025, 2, 3, 17) / 1000 },
  ],
  markers_announcements_omitted: 0,
  range: { end_day: "2025-03-03", start_day: "2025-03-01" },
  tickets: { discount_codes: [], ticket_types: [] },
  traffic: {
    attribution_consistent: true,
    registrations_baseline: 1,
    registrations_by_ticket_type_per_day: [
      {
        kind: "ticket-type",
        series: daySeries([1, 1, 0]),
        event_ticket_type_id: "t1",
        order: 1,
        title: "General",
      },
      { kind: "unknown", series: daySeries([0, 0, 1]), event_ticket_type_id: null, order: null, title: null },
    ],
    registrations_running_total: daySeries([2, 3, 4]),
    views_after_end: 0,
    views_before_start: 0,
    views_by_source_per_day: [
      { kind: "source", series: daySeries([4, 0, 0]), source: "alpha" },
      { kind: "source", series: daySeries([0, 3, 0]), source: "other" },
      { kind: "other-sources", series: daySeries([1, 0, 0]), source: null },
      { kind: "no-source", series: daySeries([0, 0, 2]), source: null },
      { kind: "untagged", series: daySeries([5, 5, 5]), source: null },
    ],
    views_total: 25,
  },
  utm: {
    by_campaign: {
      not_specified: 8,
      remainder_count: 0,
      remainder_views: 0,
      values: [{ value: "spring", views: 2 }],
    },
    by_medium: {
      not_specified: 2,
      remainder_count: 0,
      remainder_views: 0,
      values: [{ value: "email", views: 8 }],
    },
    by_source: {
      not_specified: 2,
      remainder_count: 0,
      remainder_views: 0,
      values: [
        { value: "alpha", views: 4 },
        { value: "other", views: 3 },
        { value: "beta", views: 1 },
      ],
    },
    combinations: [],
    combinations_remainder_views: 0,
    combinations_total_count: 0,
    tagged_views: 10,
  },
});

/** Renders the analytics partial fixture with its chart slots, controls and JSON marker. */
const renderAnalyticsFixture = (payload, { includeCheckIns = true } = {}) => {
  document.body.innerHTML = `
    <div id="analytics-content">
      ${CHART_IDS.filter((id) => includeCheckIns || id !== "event-check-ins-chart")
        .map((id) => `<div id="${id}"></div>`)
        .join("")}
      ${includeCheckIns ? "<section data-event-analytics-check-ins></section>" : ""}
      <div role="group" data-utm-dimension-switch>
        <button type="button" aria-pressed="true" data-utm-dimension="source">Source</button>
        <button type="button" aria-pressed="false" data-utm-dimension="medium">Medium</button>
        <button type="button" aria-pressed="false" data-utm-dimension="campaign">Campaign</button>
      </div>
      <table data-utm-combinations>
        <thead>
          <tr>
            <th aria-sort="none"><button type="button" data-utm-sort="source">Source</button></th>
            <th aria-sort="descending"><button type="button" data-utm-sort="views">Views</button></th>
            <th>Share</th>
          </tr>
        </thead>
        <tbody>
          <tr data-utm-row data-source="beta" data-views="5"><td>beta</td></tr>
          <tr data-utm-row data-source="" data-views="5"><td>Not specified</td></tr>
          <tr data-utm-row data-source="alpha" data-views="2"><td>alpha</td></tr>
        </tbody>
      </table>
      <script type="application/json" data-event-analytics>${JSON.stringify(payload)}</script>
    </div>
  `;
  return document.getElementById("analytics-content");
};

describe("dashboard group event analytics", () => {
  const originalEcharts = globalThis.echarts;
  let optionsById;
  let failInit;

  /** Returns the last option rendered into a chart element. */
  const getOption = (id) => optionsById.get(id);

  beforeEach(() => {
    resetDom();
    [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950].forEach((shade, index) => {
      document.documentElement.style.setProperty(
        `--color-primary-${shade}`,
        `#0000${String(index).padStart(2, "0")}`,
      );
    });
    document.documentElement.style.setProperty("--color-stone-300", "#d6d3d1");
    optionsById = new Map();
    failInit = false;
    globalThis.echarts = {
      getInstanceByDom() {
        return null;
      },
      init(element) {
        if (failInit) {
          throw new Error("chart failure");
        }
        return {
          dispose() {},
          resize() {},
          setOption(option) {
            optionsById.set(element.id, option);
          },
        };
      },
    };
  });

  afterEach(() => {
    disposeChartsWithin(document.body);
    resetDom();
    if (originalEcharts) {
      globalThis.echarts = originalEcharts;
    } else {
      delete globalThis.echarts;
    }
  });

  it("initializes every chart from the page marker and retries after a failure", async () => {
    // Render the fixture and fail the first initialization.
    const root = renderAnalyticsFixture(getEventAnalyticsPayload());
    const marker = root.querySelector("[data-event-analytics]");
    const originalConsoleError = console.error;
    console.error = () => {};
    failInit = true;
    try {
      await initializeEventAnalyticsFromPage(root);
    } finally {
      console.error = originalConsoleError;
    }
    expect(marker.dataset.eventAnalyticsReady).to.equal(undefined);

    // Retry once the chart library works.
    failInit = false;
    await initializeEventAnalyticsFromPage(root);

    // Assert every chart rendered and the marker is ready.
    expect(Array.from(optionsById.keys()).sort()).to.deep.equal(CHART_IDS);
    expect(marker.dataset.eventAnalyticsReady).to.equal("true");
  });

  it("skips initialization when the analytics root is detached while loading", async () => {
    // Start initialization and detach the root before it resumes.
    const root = renderAnalyticsFixture(getEventAnalyticsPayload());
    const pending = initializeEventAnalyticsFromPage(root);
    root.remove();
    await pending;

    // Assert no chart rendered.
    expect(optionsById.size).to.equal(0);
  });

  it("groups other sources and no source views into one other series", () => {
    // Group the series of other sources and views without a source.
    const grouped = groupOtherViewsSeries(getEventAnalyticsPayload().traffic.views_by_source_per_day);

    // Assert the other series sums both groups where the first one was.
    expect(grouped.map((series) => series.kind)).to.deep.equal(["source", "source", "other", "untagged"]);
    expect(grouped[2].series).to.deep.equal(daySeries([1, 0, 2]));
    expect(groupOtherViewsSeries([])).to.deep.equal([]);
  });

  it("labels and colors stacked views consistently, keeping a literal other source distinct", async () => {
    // Initialize the charts.
    const payload = getEventAnalyticsPayload();
    const root = renderAnalyticsFixture(payload);
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });

    // Assert the daily views series labels and stacked markers.
    const viewsOption = getOption("event-views-daily-chart");
    const viewsNames = viewsOption.series.map((series) => series.name);
    expect(viewsNames).to.deep.equal(["alpha", "other", "Other", "Untagged"]);
    expect(viewsOption.series[2].data).to.deep.equal([1, 0, 2]);
    expect(viewsOption.series[0].markLine.data.map((marker) => marker.xAxis)).to.deep.equal([
      "2025-03-01",
      "2025-03-03",
    ]);

    // Assert source colors match across the daily and share charts.
    const viewsColors = Object.fromEntries(
      viewsOption.series.map((series) => [series.name, series.itemStyle.color]),
    );
    const shareOption = getOption("event-utm-share-chart");
    const shareSlices = shareOption.series[0].data;
    expect(shareSlices.map((slice) => slice.name)).to.deep.equal([
      "alpha",
      "other",
      "beta",
      "Other",
      "Untagged",
    ]);
    expect(shareSlices[3].value).to.equal(2);
    expect(shareOption.color[0]).to.equal(viewsColors.alpha);
    expect(shareOption.color[1]).to.equal(viewsColors.other);
    expect(shareOption.color[3]).to.equal(viewsColors.Other);
    expect(viewsColors.other).to.not.equal(viewsColors.Other);

    // Assert the share chart keeps its legend below the pie with percentage slice labels.
    expect(shareOption.legend.orient).to.equal("horizontal");
    expect(shareOption.series[0].label).to.include({ formatter: "{d}%", show: true });
    expect(shareOption.series[0].labelLine.show).to.equal(true);
  });

  it("keeps share chart source colors distinct when charted and all-time top sources differ", async () => {
    // Rank three sources in the charted days and mostly different ones all-time.
    const payload = getEventAnalyticsPayload();
    payload.traffic.views_by_source_per_day = ["a", "b", "c"].map((source) => ({
      kind: "source",
      series: daySeries([1, 0, 0]),
      source,
    }));
    payload.utm.by_source.values = ["a", "f", "g", "h"].map((value) => ({ value, views: 2 }));
    const root = renderAnalyticsFixture(payload);
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });

    // Assert every share chart source has its own color.
    const shareOption = getOption("event-utm-share-chart");
    const shareNames = shareOption.series[0].data.map((slice) => slice.name);
    expect(shareNames.slice(0, 3)).to.deep.equal(["a", "f", "g"]);
    const shareSourceColors = shareOption.color.slice(0, 3);
    expect(new Set(shareSourceColors).size).to.equal(3);

    // Assert charted sources keep their daily chart colors in the share chart.
    const viewsOption = getOption("event-views-daily-chart");
    const viewsColors = Object.fromEntries(
      viewsOption.series.map((series) => [series.name, series.itemStyle.color]),
    );
    expect(shareSourceColors[0]).to.equal(viewsColors.a);
  });

  it("falls back to total views when attribution is inconsistent", async () => {
    // Initialize the charts with inconsistent attribution.
    const payload = getEventAnalyticsPayload();
    payload.traffic.attribution_consistent = false;
    const root = renderAnalyticsFixture(payload);
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });

    // Assert a single total series and no share chart.
    const viewsOption = getOption("event-views-daily-chart");
    expect(viewsOption.series).to.have.length(1);
    expect(viewsOption.series[0].name).to.equal("Page views");
    expect(viewsOption.series[0].data).to.deep.equal([10, 8, 7]);
    expect(optionsById.has("event-utm-share-chart")).to.equal(false);
    expect(document.getElementById("event-utm-share-chart").classList.contains("chart-empty-state")).to.equal(
      true,
    );
    expect(getOption("event-utm-values-chart").series[0].label.formatter({ value: 4 })).to.equal("4");
    expect(getOption("event-utm-values-chart").tooltip.formatter({ name: "alpha", value: 4 })).to.equal(
      "alpha: 4",
    );
  });

  it("shows empty states for all-zero data and renders single-day ranges", async () => {
    // Initialize the charts with all-zero daily data on one day.
    const payload = getEventAnalyticsPayload();
    payload.traffic.views_by_source_per_day = [
      { kind: "untagged", series: [["2025-03-01", 0]], source: null },
    ];
    payload.traffic.registrations_by_ticket_type_per_day = [];
    payload.traffic.registrations_running_total = [["2025-03-01", 0]];
    payload.check_ins.bins = [];
    const root = renderAnalyticsFixture(payload);
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });

    // Assert empty states replace the inactive charts.
    [
      "event-views-daily-chart",
      "event-registrations-daily-chart",
      "event-fill-curve-chart",
      "event-check-ins-chart",
    ].forEach((id) => {
      expect(optionsById.has(id)).to.equal(false);
      expect(document.getElementById(id).textContent).to.equal("No data available yet");
    });

    // Assert a single active day still renders with visible line points.
    payload.traffic.views_by_source_per_day = [
      { kind: "source", series: [["2025-03-01", 2]], source: "newsletter" },
      { kind: "untagged", series: [["2025-03-01", 3]], source: null },
    ];
    payload.traffic.registrations_running_total = [["2025-03-01", 2]];
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });
    expect(getOption("event-views-daily-chart").xAxis.data).to.deep.equal(["2025-03-01"]);
    expect(getOption("event-fill-curve-chart").series[0]).to.include({ showSymbol: true, symbol: "circle" });
  });

  it("switches the UTM dimension and sorts combinations with synced aria state", async () => {
    // Initialize the charts.
    const payload = getEventAnalyticsPayload();
    const root = renderAnalyticsFixture(payload);
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });
    expect(getOption("event-utm-values-chart").yAxis.data).to.deep.equal([
      "alpha",
      "other",
      "beta",
      "Not specified",
    ]);

    // Switch to the medium dimension.
    root.querySelector('[data-utm-dimension="medium"]').click();
    expect(getOption("event-utm-values-chart").yAxis.data).to.deep.equal(["email", "Not specified"]);
    expect(
      Array.from(root.querySelectorAll("[data-utm-dimension]")).map((button) =>
        button.getAttribute("aria-pressed"),
      ),
    ).to.deep.equal(["false", "true", "false"]);

    // Sort by source ascending, keeping empty values last.
    const sourceHeader = root.querySelector('[data-utm-sort="source"]');
    sourceHeader.click();
    const rowSources = () => Array.from(root.querySelectorAll("tbody tr")).map((row) => row.dataset.source);
    expect(rowSources()).to.deep.equal(["alpha", "beta", ""]);
    expect(sourceHeader.closest("th").getAttribute("aria-sort")).to.equal("ascending");
    expect(root.querySelector('[data-utm-sort="views"]').closest("th").getAttribute("aria-sort")).to.equal(
      "none",
    );

    // Sort by views ascending, keeping tied rows in their original order.
    const viewsHeader = root.querySelector('[data-utm-sort="views"]');
    viewsHeader.click();
    viewsHeader.click();
    expect(viewsHeader.closest("th").getAttribute("aria-sort")).to.equal("ascending");
    expect(rowSources()).to.deep.equal(["alpha", "beta", ""]);
    viewsHeader.click();
    expect(viewsHeader.closest("th").getAttribute("aria-sort")).to.equal("descending");
    expect(rowSources()).to.deep.equal(["beta", "", "alpha"]);
  });

  it("charts registration paths as shares without value axis labels", async () => {
    // Initialize the charts.
    const payload = getEventAnalyticsPayload();
    const root = renderAnalyticsFixture(payload);
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });

    // Assert only used paths are charted as shares of the registrations.
    const pathsOption = getOption("event-registration-paths-chart");
    expect(pathsOption.yAxis.data).to.deep.equal(["Direct", "Approved request"]);
    expect(pathsOption.series[0].label.formatter({ value: 3 })).to.equal("75.0%");
    expect(pathsOption.xAxis.axisLabel.show).to.equal(false);
  });

  it("expands and collapses the hidden options of a registration question", async () => {
    // Render a question list with a hidden option and initialize the controls.
    const payload = getEventAnalyticsPayload();
    const root = renderAnalyticsFixture(payload);
    root.insertAdjacentHTML(
      "beforeend",
      `<ul id="event-question-0-options">
        <li>AI</li>
        <li hidden data-question-option-hidden>Cloud</li>
      </ul>
      <button type="button" aria-controls="event-question-0-options" aria-expanded="false"
        data-question-options-toggle data-label-collapsed="Show 1 more options"
        data-label-expanded="Show fewer options"><span data-question-options-label>Show 1 more options</span
        ><div class="svg-icon" aria-hidden="true"></div></button>`,
    );
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });
    const toggle = root.querySelector("[data-question-options-toggle]");
    const hiddenOption = root.querySelector("[data-question-option-hidden]");

    // Expand the options through the delegated control.
    toggle.click();
    expect(hiddenOption.hidden).to.equal(false);
    expect(toggle.getAttribute("aria-expanded")).to.equal("true");
    expect(toggle.textContent).to.equal("Show fewer options");
    expect(toggle.querySelector(".svg-icon")).to.not.equal(null);

    // Collapse them again.
    toggleQuestionOptions(toggle);
    expect(hiddenOption.hidden).to.equal(true);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    expect(toggle.textContent).to.equal("Show 1 more options");
  });

  it("labels registrations without a ticket type for paid and free events", () => {
    // Build an unknown registrations series.
    const series = { kind: "unknown", series: [], event_ticket_type_id: null, order: null, title: null };

    // Assert paid events name the missing ticket type and free events use a generic label.
    expect(getRegistrationsSeriesLabel(series, { tickets: { ticket_types: [] } })).to.equal(
      "Unknown ticket type",
    );
    expect(getRegistrationsSeriesLabel(series, { tickets: null })).to.equal("Registrations");
    expect(
      getRegistrationsSeriesLabel({ ...series, kind: "ticket-type", title: "VIP" }, { tickets: null }),
    ).to.equal("VIP");
  });

  it("formats check-in labels in the event timezone and adds dates across days", async () => {
    // Format bins within one day and across midnight in Madrid.
    const sameDay = formatCheckInBinLabels(
      [Date.UTC(2025, 2, 3, 16, 45), Date.UTC(2025, 2, 3, 17, 0)],
      "Europe/Madrid",
    );
    const acrossDays = formatCheckInBinLabels(
      [Date.UTC(2025, 2, 3, 22, 45), Date.UTC(2025, 2, 3, 23, 0)],
      "Europe/Madrid",
    );

    // Assert the labels use the event timezone.
    expect(sameDay).to.deep.equal(["17:45", "18:00"]);
    expect(acrossDays).to.deep.equal(["Mar 3 23:45", "Mar 4 00:00"]);

    // Assert the chart tooltip shows the UTC offset.
    const payload = getEventAnalyticsPayload();
    const root = renderAnalyticsFixture(payload);
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });
    const checkInsOption = getOption("event-check-ins-chart");
    expect(checkInsOption.xAxis.data).to.deep.equal(["17:45", "18:00"]);
    expect(checkInsOption.tooltip.formatter([{ dataIndex: 1, value: 2 }])).to.equal(
      "Mar 3, 2025, 6:00 PM GMT+1<br/>Check-ins: 2",
    );
  });

  it("skips check-ins before the event ends and adds them to the funnel afterwards", async () => {
    // Initialize the charts without the check-in section.
    const payload = getEventAnalyticsPayload();
    const root = renderAnalyticsFixture(payload, { includeCheckIns: false });
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });

    // Assert the funnel stops at registrations.
    expect(getOption("event-funnel-chart").yAxis.data).to.deep.equal(["Page views", "Registrations"]);
    expect(optionsById.has("event-check-ins-chart")).to.equal(false);

    // Assert the funnel includes check-ins once the section is rendered.
    const endedRoot = renderAnalyticsFixture(payload);
    await initEventAnalyticsCharts(payload, { marker: endedRoot.querySelector("[data-event-analytics]") });
    expect(getOption("event-funnel-chart").yAxis.data).to.deep.equal([
      "Page views",
      "Registrations",
      "Checked in",
    ]);
    expect(getOption("event-funnel-chart").xAxis.axisLabel.show).to.equal(false);
  });

  it("describes inferred and capped registration window bounds on the fill curve", async () => {
    // Initialize the charts with an inferred start and a capped end.
    const payload = getEventAnalyticsPayload();
    const root = renderAnalyticsFixture(payload);
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });

    // Assert the window area marks the inferred and capped bounds.
    const fillOption = getOption("event-fill-curve-chart");
    const markArea = fillOption.series[0].markArea;
    expect(markArea.label.formatter).to.equal("Registration window (opens at publication, cut short)");
    expect(markArea.itemStyle.borderType).to.equal("dashed");
    expect(markArea.data).to.deep.equal([[{ xAxis: "2025-03-01" }, { xAxis: "2025-03-03" }]]);
    expect(fillOption.series[0].markLine.data).to.deep.equal([{ yAxis: 10 }]);

    // Assert explicit bounds use a solid border and a plain label.
    payload.audience.window_end_capped = false;
    payload.audience.window_start_inferred = false;
    await initEventAnalyticsCharts(payload, { marker: root.querySelector("[data-event-analytics]") });
    const explicitArea = getOption("event-fill-curve-chart").series[0].markArea;
    expect(explicitArea.label.formatter).to.equal("Registration window");
    expect(explicitArea.itemStyle.borderType).to.equal("solid");
  });
});
