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

    // Verify the row keeps two icon buttons and moves the other actions into a menu.
    expect(template).to.include('aria-label="Event surveys list"');
    expect(template).to.include(
      '<th scope="col" class="hidden px-3 py-3 xl:table-cell xl:px-5">Responses</th>',
    );
    expect(template).to.include('class="btn-tertiary p-2"');
    expect(template).to.include('<div class="svg-icon size-4 icon-charts" aria-hidden="true"></div>');
    expect(template).to.include('<div class="svg-icon size-4 icon-pencil" aria-hidden="true"></div>');
    expect(template).to.include('<details data-actions-menu class="group relative inline-flex justify-end">');
    expect(template).to.include('aria-label="Open survey actions for {{ survey.title }}"');
    expect(template).to.include(
      '<span class="svg-icon size-4 icon-csv shrink-0 bg-stone-600" aria-hidden="true"></span>',
    );
    expect(template).to.include(
      '<span class="svg-icon size-4 icon-{{ status.icon }} shrink-0 bg-stone-600" aria-hidden="true"></span>',
    );

    // Verify the header links the docs and shows the survey count.
    expect(template).to.include('docs_href = "/docs#/guides/event-operations?id=surveys"');
    expect(template).to.include("{{ surveys.len() }} of {{ crate::validation::MAX_EVENT_SURVEYS }} surveys");

    // Verify tab swaps scroll the page to its top.
    expect(template.match(/hx-swap="innerHTML show:window:top"/g)).to.have.length(4);

    // Verify the survey title opens the survey form.
    expect(template).to.include('aria-label="Open survey: {{ survey.title }}">{{ survey.title }}</button>');

    // Verify the status column reuses the shared state badge and explains it in a tooltip.
    expect(template).to.include("{{ surveys_macros::state_badge(state = survey.state) -}}");
    expect(template).to.include("{{ surveys_macros::state_badge_details(state = survey.state,");
    expect(template).to.include('title = "Cannot mark ready"');
    expect(template).to.include('title = "Opening"');

    // Verify status and delete actions use unique ids and the confirmation contract.
    expect(template).to.include('id="event-survey-status-{{ survey_id }}"');
    expect(template).to.include('hx-vals="{{ status.request_values }}"');
    expect(template).to.include('data-confirm-message="{{ status.confirm_message }}"');
    expect(template).to.include('id="delete-event-survey-{{ survey_id }}"');
    expect(template.match(/data-confirm-action/g)).to.have.length(2);
    expect(template.match(/hx-trigger="confirmed"/g)).to.have.length(2);
    expect(template).to.include('hx-disabled-elt="this"');
    expect(template).to.include(
      'data-confirm-message="Delete this survey and its {{ survey.responses_count }} response{{ survey.responses_count|pluralize }}? This cannot be undone."',
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
    expect(template.match(/hx-swap="innerHTML show:window:top"/g)).to.have.length(2);

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

  it("renders results in place with compact free-text previews", async () => {
    // Load the results template.
    const results = await loadTemplate("dashboard/group/surveys_results.html");

    // Verify the overview cards follow the results header.
    expect(results).to.include("data-event-survey-overview");
    expect(results).to.include("Eligible attendees who answered");
    expect(results).to.include("Shown in the event timezone");

    // Verify select questions use the shared breakdown in labelled sections.
    expect(results).to.include(
      'surveys::results_header(event_id = event.event_id, survey = survey, timezone = event.timezone, view = "summary")',
    );
    expect(results).to.include('"event-survey-question-{}-options"|format(question.question_id)');
    expect(results).to.include('<section aria-labelledby="{{ options_id }}-prompt"');
    expect(results).to.include("question_answers::breakdown(question = breakdown,");
    expect(results).to.include('<h3 id="{{ answers_id }}-prompt"');

    // Verify free-text previews are dense and clamp long answers.
    expect(results).to.include(
      'class="grid grid-cols-1 gap-2 p-3 md:grid-cols-2" data-event-survey-text-answers-preview',
    );
    expect(results).to.include('<li class="line-clamp-3 whitespace-pre-line break-words');
    expect(results).not.to.include("Show more");

    // Verify every answer opens in a modal and failures are reported.
    expect(results).to.include(
      'hx-get="{{ crate::templates::dashboard::group::surveys::text_answers_url(*event.event_id, *survey.event_survey_id, *question.question_id) }}"',
    );
    expect(results).to.include('hx-target="#event-survey-text-answers-modal-content"');
    expect(results).to.include('hx-sync="#event-survey-text-answers-modal:replace"');
    expect(results).to.include(
      'data-htmx-response data-error-message="Something went wrong loading these answers. Please try again later."',
    );
    expect(results).to.include(
      "{{ crate::templates::dashboard::group::surveys::view_all_answers_label(*text.total) }}",
    );
    expect(results).to.include(
      '<div id="event-survey-text-answers-modal" role="dialog" aria-modal="true" aria-labelledby="event-survey-text-answers-modal-title" aria-hidden="true"',
    );
  });

  it("searches and pages free-text answers inside their modal", async () => {
    // Load the free-text answers modal content.
    const textAnswers = await loadTemplate("dashboard/group/surveys_text_answers.html");

    // Verify the header names the question and closes the modal.
    expect(textAnswers).to.include('title_id = "event-survey-text-answers-modal-title"');
    expect(textAnswers).to.include("title = answers.prompt");
    expect(textAnswers).to.include('close_attrs = "data-event-survey-text-answers-close"');

    // Verify the search replaces the modal content and keeps a stable input id.
    expect(textAnswers).to.include(
      '<form id="event-survey-text-answers-search-form" hx-get="{{ answers_url }}"',
    );
    expect(textAnswers).to.include(
      'hx-trigger="change, submit" hx-target="#event-survey-text-answers-modal-content"',
    );
    expect(textAnswers).to.include('<input id="event-survey-text-answers-search" name="ts_query"');
    expect(textAnswers).to.include('aria-label="Clear answer search"');
    expect(textAnswers).to.include("No answers found matching your search.");

    // Verify the footer shows the range and pages through the answers.
    expect(textAnswers).to.include('label = "answer"');
    expect(textAnswers).to.include(
      '{% call surveys::results_modal_footer( modal_id = "event-survey-text-answers-modal", nav_attribute = "data-event-survey-text-answers-nav", close_attribute = "data-event-survey-text-answers-close",',
    );
    expect(textAnswers).to.include("previous_url = self.previous_url(), next_url = self.next_url() ) -%}");
    expect(textAnswers.match(/hx-target="#event-survey-text-answers-modal-content"/g)).to.have.length(2);
    expect(textAnswers.match(/hx-sync="#event-survey-text-answers-modal:replace"/g)).to.have.length(2);
  });

  it("switches between the Summary and Individual views", async () => {
    // Load the results header macro and the Individual view.
    const macros = await loadTemplate("macros/surveys.html");
    const responses = await loadTemplate("dashboard/group/surveys_responses.html");

    // Verify both views swap the whole surveys tab and anonymous surveys stay aggregated.
    expect(macros).to.include('<div class="inline-flex" role="group" aria-label="Results view">');
    expect(macros).to.include('hx-get="{{ survey_url }}/results"');
    expect(macros).to.include('hx-get="{{ survey_url }}/responses"');
    expect(macros).to.include('disabled aria-describedby="event-survey-individual-view-note"');
    expect(macros).to.include(
      '<p id="event-survey-individual-view-note" class="text-xs text-stone-500"> Anonymous surveys only show aggregated results. </p>',
    );
    expect(macros).to.include('id="event-survey-results-back"');
    expect(macros).to.include("few_anonymous_responses(survey)");
    expect(macros.match(/hx-swap="innerHTML show:window:top"/g)).to.have.length(3);
    expect(responses).to.include(
      'surveys::results_header(event_id = event.event_id, survey = survey.summary, timezone = event.timezone, view = "individual")',
    );
    expect(responses).to.include('view = "individual"');
    expect(responses).to.include('hx_target = "#surveys-content"');
    expect(responses).to.include('hx_swap = "innerHTML show:window:top"');
  });

  it("lists searchable respondents that open their responses in a modal", async () => {
    // Load the Individual view and the response modal content.
    const responses = await loadTemplate("dashboard/group/surveys_responses.html");
    const response = await loadTemplate("dashboard/group/surveys_response.html");

    // Verify the search swaps the whole view and keeps its query.
    expect(responses).to.include(
      '<form id="event-survey-respondents-search-form" hx-get="{{ responses_url }}"',
    );
    expect(responses).to.include('hx-trigger="change, submit" hx-target="#surveys-content"');
    expect(responses).to.include('name="ts_query"');
    expect(responses).to.include('aria-label="Clear respondent search"');
    expect(responses).to.include('label = "respondent"');

    // Verify keyboard accessible rows load their responses into the modal.
    expect(responses).to.include('aria-label="Survey respondents"');
    expect(responses).to.include('tabindex="0" hx-get="{{ self.response_url(response.user.user_id)? }}"');
    expect(responses).to.include(`hx-trigger="click, keydown[key=='Enter']"`);
    expect(responses).to.include('hx-target="#event-survey-response-modal-content"');
    expect(responses).to.include('hx-sync="#event-survey-response-modal:replace"');
    expect(responses).to.include("data-htmx-response");
    expect(responses).to.include(
      '<div id="event-survey-response-modal" role="dialog" aria-modal="true" aria-labelledby="event-survey-response-modal-title" aria-hidden="true"',
    );

    // Verify the modal reviews the answers and navigates between respondents.
    expect(response).to.include('title_id = "event-survey-response-modal-title"');
    expect(response).to.include('close_attrs = "data-event-survey-response-close"');
    expect(response).to.include("question_answers::review_list(questions = survey.questions,");
    expect(response).to.include(
      '{% call surveys::results_modal_footer( modal_id = "event-survey-response-modal", nav_attribute = "data-event-survey-response-nav", close_attribute = "data-event-survey-response-close",',
    );
    expect(response).to.include("previous_url = self.previous_url()?, next_url = self.next_url()? ) -%}");
    expect(response).to.include("Respondent {{ response.position }} of {{ response.total }}");
  });

  it("pages survey results modals through a shared footer", async () => {
    // Load the survey macros.
    const macros = await loadTemplate("macros/surveys.html");

    // Verify the footer loads each neighbor page into its modal once at a time.
    expect(macros).to.include(
      "{% macro results_modal_footer(modal_id, nav_attribute, close_attribute, error_message, previous_url, next_url) -%}",
    );
    expect(macros).to.include('hx-get="{{ previous_url }}"');
    expect(macros).to.include('hx-get="{{ next_url }}"');
    expect(macros.match(/hx-target="#{{ modal_id }}-content"/g)).to.have.length(2);
    expect(macros.match(/hx-sync="#{{ modal_id }}:replace"/g)).to.have.length(2);
    expect(macros.match(/data-error-message="{{ error_message }}"/g)).to.have.length(2);

    // Verify missing neighbors render disabled buttons and the footer closes the modal.
    expect(macros).to.include('disabled {{ nav_attribute }}="previous"');
    expect(macros).to.include('disabled {{ nav_attribute }}="next"');
    expect(macros).to.include(
      '<button type="button" {{ close_attribute }} class="btn-primary">Close</button>',
    );
  });
});
