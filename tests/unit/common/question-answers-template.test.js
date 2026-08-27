import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/question_answers.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("question answers macros", () => {
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
});
