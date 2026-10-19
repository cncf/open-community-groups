import { expect } from "@open-wc/testing";

/** Loads a server template source as text. */
const loadTemplate = async (path) => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return response.text();
};

/**
 * Collapses whitespace runs so template assertions ignore indentation.
 * @param {string} value - Template source.
 * @returns {string} Source with single spaces between tokens.
 */
const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group event analytics template", () => {
  it("renders cards with the shared stat card macro and cache copy", async () => {
    // Load the event analytics partial.
    const template = normalizeWhitespace(await loadTemplate("dashboard/group/event_analytics.html"));

    // Assert the docs link, cache copy and summary cards.
    expect(template).to.include('docs_href = "/docs#/guides/event-operations?id=analytics"');
    expect(template).to.include("Analytics are cached for up to an hour");
    expect(template).to.include('stats_macro::stat_card(title = "Page views"');
    expect(template).to.include('stats_macro::stat_card(title = "Fill rate", value = self.fill_rate_label()');
    expect(template).to.include(
      'stats_macro::stat_card(title = "Conversion", value = self.conversion_rate_label(), description = "Approximate registrations per page view"',
    );
    expect(template).to.include(
      '{% if has_ended -%} {{ stats_macro::stat_card(title = "Check-in rate", value = self.check_in_rate_label()',
    );
  });

  it("exposes chart slots with activity flags and text summaries", async () => {
    // Load the event analytics partial.
    const template = normalizeWhitespace(await loadTemplate("dashboard/group/event_analytics.html"));

    // Assert every chart slot passes its activity flag and summary.
    [
      'chart_id = "event-views-daily-chart", data = stats.traffic.views_by_source_per_day, wrapper_class = "mt-3", has_data = stats.traffic.has_views_activity(), summary = self.views_summary()',
      'chart_id = "event-registrations-daily-chart"',
      'chart_id = "event-utm-share-chart"',
      'chart_id = "event-utm-values-chart"',
      'chart_id = "event-funnel-chart", data = self.funnel_stages()',
      'chart_id = "event-registration-paths-chart", data = registration_paths',
      'chart_id = "event-fill-curve-chart"',
      'chart_id = "event-check-ins-chart"',
    ].forEach((fragment) => expect(template).to.include(fragment));
    expect(template).to.not.include("event-utm-sources-daily-chart");
    expect(template).to.not.include("event-question-{}-chart");
  });

  it("lists registration question options with the shared breakdown macro", async () => {
    // Load the event analytics partial.
    const template = normalizeWhitespace(await loadTemplate("dashboard/group/event_analytics.html"));

    // Assert each question renders the shared breakdown with an analytics list id.
    expect(template).to.include('{% import "macros/question_answers.html" as question_answers -%}');
    expect(template).to.include(
      '{% let options_id = "event-analytics-question-{}-options"|format(loop.index0) -%}',
    );
    expect(template).to.include(
      '<div data-event-analytics-question> {{ question_answers::breakdown(question = question, options_id = options_id, empty_message = "No answers yet.") -}} </div>',
    );
    expect(template).not.to.include("line-clamp");
  });

  it("groups the analytics in traffic, registrations, tickets, audience, check-ins and surveys sections", async () => {
    // Load the event analytics partial.
    const template = normalizeWhitespace(await loadTemplate("dashboard/group/event_analytics.html"));

    // Assert the sections appear in order.
    const sectionPositions = [
      '<section data-event-analytics-traffic> {{ dashboard::form_title(title = "Traffic"',
      '<section data-event-analytics-registrations> {{ dashboard::form_title(title = "Registrations"',
      "<section data-event-analytics-tickets>",
      '{{ dashboard::form_title(title = "Audience"',
      "<section data-event-analytics-check-ins>",
      '<section data-event-analytics-surveys> {{ dashboard::form_title(title = "Surveys"',
    ].map((fragment) => template.indexOf(fragment));
    expect(sectionPositions.every((position) => position >= 0)).to.equal(true);
    expect([...sectionPositions].sort((left, right) => left - right)).to.deep.equal(sectionPositions);

    // Assert the traffic totals, enrollment cards and admission offer summaries.
    expect(template).to.include('stats_macro::stat_card(title = "Total page views"');
    expect(template).to.include("description = self.attributed_views_description()");
    expect(template).to.include(
      "value = self.unattributed_views_label(), description = self.unattributed_views_description()",
    );
    expect(template).to.include(
      'stats_macro::stat_card(title = "Invitation requests", value = invitation_requests_total|num_fmt',
    );
    expect(template).to.include("{% for source in admission_offer_sources -%}");
    expect(template).to.include("data-event-analytics-range-unavailable");
  });

  it("wires the UTM dimension switch and sortable combinations table", async () => {
    // Load the event analytics partial.
    const template = normalizeWhitespace(await loadTemplate("dashboard/group/event_analytics.html"));

    // Assert the switch exposes pressed state on grouped buttons.
    expect(template).to.include('<div role="group" aria-label="UTM parameter"');
    expect(template).to.include("aria-pressed:border-primary-500 aria-pressed:text-primary-500");
    expect(template).to.include('aria-pressed="true" data-utm-dimension="source">Source</button>');
    expect(template).to.include('aria-pressed="false" data-utm-dimension="campaign">Campaign</button>');

    // Assert the first and last day columns only show on 2xl screens.
    expect(template).to.include(
      '<td class="hidden px-3 py-3 2xl:table-cell xl:px-5">{{ combination.first_day }}</td>',
    );
    expect(template).to.include(
      '<td class="hidden px-3 py-3 2xl:table-cell xl:px-5">{{ combination.last_day }}</td>',
    );
    expect(template).not.to.include(" xl:table-cell");
    expect(template).not.to.include("lg:table-cell");

    // Assert the table caption, sortable headers and remainder row.
    expect(template).to.include("Top 10 combinations by views; sorting applies to these rows.");
    expect(template).to.include(
      'class="group px-3 py-3 text-right xl:px-5" aria-sort="descending"> <button type="button" class="inline-flex cursor-pointer items-center gap-1 uppercase" data-utm-sort="views"> Views <span class="svg-icon block size-3',
    );
    expect(template.match(/group-aria-\[sort=ascending\]:rotate-180/g)).to.have.length(6);

    // Assert the charts rely on their own titles instead of outer labels.
    expect(template).not.to.include("Share of page views</div>");
    expect(template).not.to.include("Views by value");

    // Assert warnings reuse the shared dashboard warning macro.
    expect(template).to.include('{{ dashboard::permission_warning(message = "Traffic source attribution is unavailable');
    expect(template).to.include('{{ dashboard::permission_warning(message = "Shares of page views are unavailable');

    // Assert the UTM settings link is guarded against pending event changes.
    expect(template).to.include(
      '<a id="analytics-utm-settings-link" href="/dashboard/group?tab=settings" hx-get="/dashboard/group?tab=settings" hx-trigger="click, confirmed"',
    );
    expect(template).to.include("data-pending-changes-guard");
    expect(template).to.include("more combinations ·");
    expect(template).to.include(
      'data-utm-row data-source="{{ combination.utm_source.as_deref().unwrap_or("") }}"',
    );
  });

  it("renders paid sections, check-ins and the data handoff without revenue", async () => {
    // Load the event analytics partial.
    const template = normalizeWhitespace(await loadTemplate("dashboard/group/event_analytics.html"));

    // Assert tickets render for paid events with accessible progress bars.
    expect(template).to.include("{% if let Some(tickets) = stats.tickets -%}");
    expect(template).to.include('role="progressbar"');
    expect(template).to.include('aria-valuemin="0" aria-valuemax="{{ ticket_type.seats_total }}"');
    expect(template).to.include("No seats configured");

    // Assert check-ins render only after the event and the JSON marker loads the module.
    expect(template).to.include(
      "{% if has_ended -%} {# Check-ins -#} <section data-event-analytics-check-ins>",
    );
    expect(template).to.include(
      '<script type="application/json" data-event-analytics data-event-id="{{ event_id }}">',
    );
    expect(template).to.include(
      '<script type="module" src="/static/js/dashboard/group/event-analytics.js"></script>',
    );
    expect(template.toLowerCase()).to.not.include("revenue");
    expect(template).to.not.include("currency");
  });

  it("summarizes the surveys that are not drafts without links to the surveys tab", async () => {
    // Load the event analytics partial and the survey macros.
    const template = normalizeWhitespace(await loadTemplate("dashboard/group/event_analytics.html"));
    const macros = normalizeWhitespace(await loadTemplate("macros/surveys.html"));

    // Assert the section only renders when surveys are summarized.
    expect(template).to.include(
      "{% if !stats.surveys.surveys.is_empty() -%} {# Surveys -#} <section data-event-analytics-surveys>",
    );

    // Assert the weighted overall rate uses the shared stat card.
    expect(template).to.include(
      'stats_macro::stat_card(title = "Overall response rate", value = self.surveys_response_rate_label(), description = self.surveys_response_rate_description())',
    );

    // Assert each survey row shows its state, responses, rate and a decorative bar.
    expect(template).to.include(
      "{% for survey in stats.surveys.surveys -%} <li data-event-analytics-survey>",
    );
    expect(template).to.include("{{ surveys_macros::state_badge(state = survey.state) -}}");
    expect(template).to.include(
      "{{ self.survey_responses_summary(survey) }} · {{ self.survey_rate_label(survey) }}",
    );
    expect(template).to.include(
      '<div class="mt-2 h-2.5 w-full overflow-hidden rounded-full bg-stone-200" aria-hidden="true">',
    );
    expect(template).to.include('style="width: {{ self.survey_response_width(survey) }}%"');

    // Assert the notes explain the cache and the per survey counts.
    expect(template).to.include("Survey counts are cached for up to an hour.");
    expect(template).to.include("Counts are per survey");
    expect(template).to.not.match(/\/surveys(?!\.html)/);

    // Assert the shared state badge covers every survey state.
    ["Draft", "Scheduled", "Open", "Closed"].forEach((state) =>
      expect(macros).to.include(`{% when crate::types::event_survey::EventSurveyState::${state} -%}`),
    );
  });

  it("shares the stat card and chart slot macros with the group analytics page", async () => {
    // Load the stats macros and the group analytics page.
    const macros = normalizeWhitespace(await loadTemplate("macros/stats.html"));
    const groupAnalytics = normalizeWhitespace(await loadTemplate("dashboard/group/analytics.html"));

    // Assert the macro contracts.
    expect(macros).to.include(
      '{% macro analytics_chart(chart_id, data, class = "h-80", min_points = 0, wrapper_class = "", has_data = true, summary = "") -%}',
    );
    expect(macros).to.include("{% if has_data && data.len() > min_points + 0 -%}");
    expect(macros).to.include('<p class="sr-only">{{ summary }}</p>');
    expect(macros).to.include('{% macro stat_card(title, value, description, extra_class = "") -%}');

    // Assert the group analytics page uses the shared card and cache copy.
    expect(groupAnalytics).to.include(
      'stats_macro::stat_card(title = "Members", value = stats.members.total|num_fmt',
    );
    expect(groupAnalytics).to.include("Analytics are cached for up to an hour");
  });
});
