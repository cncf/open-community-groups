import { expect } from "@open-wc/testing";

/** Loads a survey template source and collapses its whitespace. */
const loadTemplate = async (path) => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return (await response.text()).replace(/\s+/g, " ").trim();
};

describe("dashboard group event survey templates", () => {
  it("renders survey rows with confirmed icon actions", async () => {
    // Load the survey list template.
    const template = await loadTemplate("dashboard/group/surveys_list.html");

    // Verify the row follows the sponsors table style with icon buttons.
    expect(template).to.include('aria-label="Event surveys list"');
    expect(template).to.include('<th scope="col" class="px-3 py-3 xl:px-5">Responses</th>');
    expect(template).to.include('class="btn-tertiary p-2"');
    expect(template).to.include('<div class="svg-icon size-4 icon-charts" aria-hidden="true"></div>');
    expect(template).to.include('<div class="svg-icon size-4 icon-csv" aria-hidden="true"></div>');
    expect(template).to.include('<div class="svg-icon size-4 icon-{{ status.icon }}" aria-hidden="true"></div>');

    // Verify the header links the docs and shows the survey count.
    expect(template).to.include('docs_href = "/docs#/guides/event-operations?id=surveys"');
    expect(template).to.include(
      "{{ surveys.len() }} of {{ crate::validation::MAX_EVENT_SURVEYS }} surveys",
    );

    // Verify tab swaps scroll the surveys tab to its top.
    expect(template.match(/hx-swap="innerHTML show:#surveys-content:top"/g)).to.have.length(3);

    // Verify the status column reuses the shared state badge.
    expect(template).to.include("{{ surveys_macros::state_badge(state = survey.state) -}}");

    // Verify status and delete actions use unique ids and the confirmation contract.
    expect(template).to.include('id="event-survey-status-{{ survey_id }}"');
    expect(template).to.include('hx-vals="{{ status.request_values }}"');
    expect(template).to.include('data-confirm-message="{{ status.confirm_message }}"');
    expect(template).to.include('id="delete-event-survey-{{ survey_id }}"');
    expect(template.match(/data-confirm-action/g)).to.have.length(2);
    expect(template.match(/hx-trigger="confirmed"/g)).to.have.length(2);
    expect(template).to.include('hx-disabled-elt="this"');
    expect(template).to.include(
      'data-confirm-message="Delete this survey and its {{ survey.responses_count }} responses? This cannot be undone."',
    );
  });

  it("disables mutation controls for read-only roles", async () => {
    // Load the survey list template.
    const template = await loadTemplate("dashboard/group/surveys_list.html");

    // Verify every role can open results, the CSV and the read-only form.
    expect(template).not.to.include("{% if can_manage_surveys -%} {% let status");
    expect(template).to.include("/results");
    expect(template).to.include("/responses.csv");
    expect(template).to.include("/update");

    // Verify add, status and delete are disabled with the role reason.
    expect(
      template.match(/disabled title="Your role cannot add, update or delete surveys."/g),
    ).to.have.length(3);
    expect(template).to.include(
      "Your role cannot manage surveys. You can still view results and download responses.",
    );
  });

  it("submits the survey form on its own outside the event forms", async () => {
    // Load the survey form template.
    const template = await loadTemplate("dashboard/group/surveys_form.html");

    // Verify the form has its own targets and never joins the event payload.
    expect(template).to.include('<form id="event-survey-form"');
    expect(template).to.include("data-event-survey-form");
    expect(template).not.to.include("data-event-form");
    expect(template).to.include('hx-swap="none"');
    expect(template).to.include('hx-disabled-elt="#event-survey-form-submit, #event-survey-form-cancel"');
    expect(template).to.include('hx-post="/dashboard/group/events/{{ event.event_id }}/surveys/add"');
    expect(template).to.include(
      'hx-put="/dashboard/group/events/{{ event.event_id }}/surveys/{{ survey.summary.event_survey_id }}/update"',
    );

    // Verify the Back link and Cancel button swap the surveys tab in place.
    expect(template).to.include('id="event-survey-form-back"');
    expect(template.match(/hx-target="#surveys-content"/g)).to.have.length(2);
    expect(template.match(/hx-swap="innerHTML show:#surveys-content:top"/g)).to.have.length(2);

    // Verify Cancel skips form validation and the submit label follows the mode.
    expect(template).to.include('data-skip-validation="true" class="btn-primary-outline">Cancel</button>');
    expect(template).to.include("{% if survey.is_some() -%} Save survey {% else -%} Add survey {% endif -%}");
  });

  it("disables locked fields and keeps their values in hidden inputs", async () => {
    // Load the survey form template.
    const template = await loadTemplate("dashboard/group/surveys_form.html");

    // Verify the amber banner and the disabled locked controls.
    expect(template).to.include("data-event-survey-locked-notice");
    expect(template).to.include("border-amber-200 bg-amber-50");
    expect(template).to.include('data-event-survey-toggle="event-survey-anonymous"');
    expect(template).to.include(
      '<input type="hidden" id="event-survey-anonymous" name="anonymous" value="{{ self.anonymous() }}">',
    );
    expect(template).to.include(
      '<fieldset class="col-span-full lg:col-span-5" {% if locked %}disabled{% endif %}>',
    );
    expect(template).to.include(
      '{% if locked -%} <input type="hidden" name="audience" value="{{ self.audience() }}"> {% endif -%}',
    );
    expect(template).to.include("{% if locked || read_only %}disabled{% endif %}></questions-editor>");
    expect(template).to.include('max-questions="{{ crate::validation::MAX_EVENT_SURVEY_QUESTIONS }}"');
  });

  it("renders results in place with paginated free-text answers", async () => {
    // Load the results and text answers templates.
    const results = await loadTemplate("dashboard/group/surveys_results.html");
    const textAnswers = await loadTemplate("dashboard/group/surveys_text_answers.html");

    // Verify the overview cards follow the results header.
    expect(results).to.include("data-event-survey-overview");
    expect(results).to.include("Eligible attendees who answered");
    expect(results).to.include("Shown in the event timezone");

    // Verify select questions use the shared breakdown in labelled sections.
    expect(results).to.include(
      'surveys::results_header(event_id = event.event_id, survey = survey, view = "summary")',
    );
    expect(results).to.include('"event-survey-question-{}-options"|format(question.question_id)');
    expect(results).to.include('<section aria-labelledby="{{ options_id }}-prompt"');
    expect(results).to.include("question_answers::breakdown(question = breakdown,");
    expect(results).to.include('<h3 id="{{ answers_id }}-prompt"');

    // Verify free-text answers load more answers in place and report failures.
    expect(results).to.include(
      "/results/questions/{{ question.question_id }}/answers?offset={{ text.answers.len() }}",
    );
    expect(results).to.include('hx-target="closest li" hx-swap="outerHTML"');
    expect(results).to.include(
      'data-htmx-response data-error-message="Something went wrong loading more answers. Please try again later."',
    );
    expect(results).to.include("Show more answers ({{ text.total - text.answers.len() }} left)");
    expect(textAnswers).to.include("answers?offset={{ next_offset }}&limit={{ limit }}");
    expect(textAnswers).to.include('hx-target="closest li" hx-swap="outerHTML"');
    expect(textAnswers).to.include("data-htmx-response");
    expect(textAnswers).to.include("Show more answers ({{ self.remaining() }} left)");
  });

  it("switches between the Summary and Individual views", async () => {
    // Load the results header macro and the Individual view.
    const macros = await loadTemplate("macros/surveys.html");
    const responses = await loadTemplate("dashboard/group/surveys_responses.html");

    // Verify both views swap the whole surveys tab and anonymous surveys stay aggregated.
    expect(macros).to.include('<div class="inline-flex" role="group" aria-label="Results view">');
    expect(macros).to.include('hx-get="{{ survey_url }}/results"');
    expect(macros).to.include('hx-get="{{ survey_url }}/responses"');
    expect(macros).to.include('disabled title="Anonymous surveys only show aggregated results."');
    expect(macros).to.include('id="event-survey-results-back"');
    expect(macros).to.include("few_anonymous_responses(survey)");
    expect(macros).to.include('<h2 class="text-xl leading-tight font-medium text-stone-900 lg:text-2xl">{{ survey.title }}</h2>');
    expect(macros.match(/hx-swap="innerHTML show:#surveys-content:top"/g)).to.have.length(3);
    expect(responses).to.include('view = "individual"');
    expect(responses).to.include('hx_target = "#surveys-content"');
    expect(responses).to.include('hx_swap = "innerHTML show:#surveys-content:top"');
  });
});
