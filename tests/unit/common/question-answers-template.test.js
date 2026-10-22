import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/question_answers.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("question answers macros", () => {
  it("labels and bounds free-text answer fields", async () => {
    // Load the shared question-answer macros before checking answer fields.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify each legend has an id that labels its free-text answer.
    expect(template).to.include(
      '{% let prompt_id = "{}-{}-prompt"|format(radio_name_prefix, question.id) -%} <legend id="{{ prompt_id }}" class="form-label">',
    );
    expect(template).to.include(
      '<textarea class="input-primary min-h-24 text-stone-500" aria-labelledby="{{ prompt_id }}" maxlength="{{ crate::validation::MAX_LEN_QUESTIONNAIRE_ANSWER }}"',
    );
  });

  it("renders a shared review list for submitted answers", async () => {
    // Load the shared question-answer macros before checking review markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify review list markup is shared by attendee and invitation request views.
    expect(template).to.include("{% macro review_list(questions, answers) -%}");
    expect(template).to.include('<ol class="space-y-3">');
    expect(template).to.include('<li class="rounded-md border border-stone-200 bg-white p-4">');
    expect(template).to.include("{{ loop.index }}");
    expect(template).to.include("No answer provided");
    expect(template).to.include("text-sm italic text-stone-500");
    expect(template).to.include(
      '<div class="mt-3 py-3 text-sm italic leading-6 text-stone-500">No answer provided</div>',
    );
    expect(template).to.include(
      '<div class="mt-3 border border-transparent py-1 text-sm italic text-stone-500">No answer provided</div>',
    );
    expect(template).to.include("question.format_answer(*answers)");
    expect(template).to.include("question.is_option_selected(*answers, option.id)");
  });

  it("renders a shared review modal shell", async () => {
    // Load the shared question-answer macros before checking modal markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify attendee and invitation request views share one review modal shell.
    expect(template).to.include("{% macro review_modal(id_prefix) -%}");
    expect(template).to.include('id="{{ id_prefix }}-modal"');
    expect(template).to.include('id="{{ id_prefix }}-content"');
    expect(template).to.include('id="{{ id_prefix }}-name"');
    expect(template).to.include('id="cancel-{{ id_prefix }}-modal"');
    expect(template).to.include("Registration answers");
  });

  it("renders a shared select question breakdown with an options toggle", async () => {
    // Load the shared question-answer macros before checking breakdown markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify prompts wrap in full and options render as decorative bars.
    expect(template).to.include('{% macro breakdown(question, options_id, empty_message, number = "") -%}');
    expect(template).to.include(
      '<h3 id="{{ options_id }}-prompt" class="flex items-start gap-2 break-words text-sm font-semibold text-stone-700">',
    );
    expect(template).to.include('<span class="min-w-0">{{ question.prompt }}</span>');
    expect(template).to.include('<ul id="{{ options_id }}" class="space-y-4">');
    expect(template).to.include(
      "{% for option in crate::templates::questionnaire::option_shares(question) -%}",
    );
    expect(template).to.include("{% if option.hidden %}hidden data-question-option-hidden{% endif %}");
    expect(template).to.include("{{ option.count|num_fmt }} · {{ option.share_label }}");

    // Verify the toggle controls the caller's options list and starts collapsed.
    expect(template).to.include(
      'aria-controls="{{ options_id }}" aria-expanded="false" data-question-options-toggle',
    );
    expect(template).to.include(
      "<span data-question-options-label>Show {{ hidden_options_count }} more options</span>",
    );
    expect(template).to.include(
      "icon-caret-down-filled bg-current transition-transform group-aria-expanded:rotate-180",
    );

    // Verify the multi-select note and the caller's empty message.
    expect(template).to.include("{% if crate::templates::questionnaire::is_multi_select(question) -%}");
    expect(template).to.include("percentages of respondents can add up to more than 100%");
    expect(template).to.include('<p class="text-sm text-stone-500">{{ empty_message }}</p>');
  });
});
