import { expect } from "@open-wc/testing";

const loadTemplate = async (path = "dashboard/user/surveys_list.html") => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user surveys list template", () => {
  it("loads each survey row into the survey modal", async () => {
    // Load the surveys list template before checking the row action.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the row action loads the survey without leaving the dashboard.
    expect(template).to.include('<tr data-user-event-survey="{{ survey.event_survey_id }}"');
    expect(template).to.include('hx-get="/dashboard/user/surveys/{{ survey.event_survey_id }}"');
    expect(template).to.include('hx-target="#user-event-survey-modal-content"');
    expect(template).to.include('hx-sync="closest tbody:replace"');
    expect(template).to.include("data-user-event-survey-open");
    expect(template).to.include(
      "{% let action_label = crate::templates::dashboard::user::surveys::survey_action_label(survey) -%}",
    );
    expect(template).to.include('aria-label="{{ action_label }}: {{ survey.title }}"');
    expect(template).to.include('class="btn-primary-outline btn-mini whitespace-nowrap">{{ action_label }}</button>');
    expect(template).not.to.include('<span class="sr-only">: {{ survey.title }}</span>');
  });

  it("reloads the dashboard layout after answers are saved", async () => {
    // Load the surveys list template before checking the refresh contract.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify saved answers refresh the list and the menu badge together.
    expect(template).to.include('hx-get="{{ refresh_url }}"');
    expect(template).to.include('hx-trigger="refresh-user-surveys from:body"');
    expect(template).to.include('hx-target="#dashboard-layout"');
    expect(template).to.include('hx-select="#dashboard-layout"');
    expect(template).to.include('hx-swap="outerHTML"');
  });

  it("renders the survey modal shell and opens the requested survey on load", async () => {
    // Load the surveys list template before checking the survey modal.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the closed dialog, its content target and the requested survey.
    expect(template).to.include('<div id="user-event-survey-modal" data-user-event-survey-modal');
    expect(template).to.include("{% if survey.is_some() %}data-open-on-load{% endif %}");
    expect(template).to.include('aria-labelledby="user-event-survey-title" aria-hidden="true"');
    expect(template).to.include('<div id="user-event-survey-modal-content" class="modal-card rounded-lg">');
    expect(template).to.include('{% include "dashboard/user/surveys_modal.html" -%}');
    expect(template).to.include("{{ dashboard::permission_warning(message = warning) -}}");
  });

  it("renders the survey answers form inside the survey modal", async () => {
    // Load the survey modal content.
    const template = normalizeWhitespace(await loadTemplate("dashboard/user/surveys_modal.html"));

    // Verify the form submits the answers to the revision the user saw.
    expect(template).to.include('title_id = "user-event-survey-title"');
    expect(template).to.include('hx-put="/dashboard/user/surveys/{{ survey.event_survey_id }}/response"');
    expect(template).to.include('<form data-user-event-survey-form="{{ survey.event_survey_id }}"');
    expect(template).to.include('<input type="hidden" data-question-answers-input name="answers">');
    expect(template).to.include('<input type="hidden" name="revision" value="{{ survey.revision }}">');
    expect(template).to.include(
      '<button data-user-event-survey-close type="button" class="btn-primary-outline">Cancel</button>',
    );
    expect(template).to.include("data-survey-privacy-notice");
  });

  it("renders closed survey answers read-only inside the survey modal", async () => {
    // Load the survey modal content.
    const template = normalizeWhitespace(await loadTemplate("dashboard/user/surveys_modal.html"));

    // Verify closed surveys review the answers with a single close action.
    expect(template).to.include("{% if survey.is_closed() -%}");
    expect(template).to.include("data-user-event-survey-answers");
    expect(template).to.include("question_answers::review_list(questions = survey.questions");
    expect(template).to.include(
      '<button data-user-event-survey-close type="button" class="btn-primary">Close</button>',
    );
  });
});
