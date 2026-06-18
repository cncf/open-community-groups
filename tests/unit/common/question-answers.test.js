import { expect } from "@open-wc/testing";

import { collectQuestionAnswers, setQuestionAnswersInputValue } from "/static/js/common/question-answers.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("question answer helpers", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("collects free-text and selected option answers", () => {
    // Render a form with every supported question answer type.
    document.body.innerHTML = `
      <form id="questions-form">
        <fieldset data-question-id="question-text" data-question-kind="free-text">
          <textarea data-answer>  Accessibility needs  </textarea>
        </fieldset>
        <fieldset data-question-id="question-radio" data-question-kind="single-select">
          <input type="radio" data-answer value="one">
          <input type="radio" data-answer value="two" checked>
        </fieldset>
        <fieldset data-question-id="question-checkbox" data-question-kind="multi-select">
          <input type="checkbox" data-answer value="alpha" checked>
          <input type="checkbox" data-answer value="beta" checked>
        </fieldset>
      </form>
    `;

    // Set up form.
    const form = document.getElementById("questions-form");
    const payload = collectQuestionAnswers(form, { answerSelector: "[data-answer]" });

    // Assert the emitted payload.
    expect(payload).to.deep.equal({
      answers: [
        { question_id: "question-text", value: "Accessibility needs" },
        { question_id: "question-radio", value: "two" },
        { question_id: "question-checkbox", value: ["alpha", "beta"] },
      ],
    });
  });

  it("validates required multi-select answers", () => {
    // Render a required multi-select question without a selected option.
    document.body.innerHTML = `
      <form id="questions-form">
        <fieldset data-question-id="question-checkbox"
                  data-question-kind="multi-select"
                  data-question-required="true">
          <input type="checkbox" data-answer value="alpha">
        </fieldset>
      </form>
    `;

    // Set up form.
    const form = document.getElementById("questions-form");
    const input = form.querySelector("[data-answer]");
    const payload = collectQuestionAnswers(form, { answerSelector: "[data-answer]" });

    // Verify validates required multi-select answers.
    expect(payload).to.equal(null);
    expect(input.validationMessage).to.equal("Select at least one option.");

    // Select the answer option.
    input.checked = true;
    input.dispatchEvent(new Event("change", { bubbles: true }));
    expect(input.validationMessage).to.equal("");

    // Collect the updated answers.
    const nextPayload = collectQuestionAnswers(form, { answerSelector: "[data-answer]" });

    // Assert the validation message.
    expect(input.validationMessage).to.equal("");
    expect(nextPayload).to.deep.equal({
      answers: [{ question_id: "question-checkbox", value: ["alpha"] }],
    });
  });

  it("validates required free-text answers after trimming whitespace", () => {
    // Render a required free-text question with a whitespace-only answer.
    document.body.innerHTML = `
      <form id="questions-form">
        <fieldset data-question-id="question-text"
                  data-question-kind="free-text"
                  data-question-required="true">
          <textarea data-answer required>   </textarea>
        </fieldset>
      </form>
    `;

    // Set up form.
    const form = document.getElementById("questions-form");
    const input = form.querySelector("[data-answer]");
    const payload = collectQuestionAnswers(form, { answerSelector: "[data-answer]" });

    // Verify validates required free-text answers after trimming whitespace.
    expect(payload).to.equal(null);
    expect(input.validationMessage).to.equal("Answer this question.");

    // Answer the required form question.
    input.value = "Accessibility needs";
    const nextPayload = collectQuestionAnswers(form, { answerSelector: "[data-answer]" });

    // Assert the validation message.
    expect(input.validationMessage).to.equal("");
    expect(nextPayload).to.deep.equal({
      answers: [{ question_id: "question-text", value: "Accessibility needs" }],
    });
  });

  it("serializes answer payloads into hidden inputs", () => {
    // Render a form with the hidden answers input.
    document.body.innerHTML = `
      <form id="questions-form">
        <input type="hidden" data-answers-input>
      </form>
    `;

    // Set up form.
    const form = document.getElementById("questions-form");
    const payload = { answers: [{ question_id: "question-text", value: "Yes" }] };

    // Assert that the flag is enabled.
    expect(setQuestionAnswersInputValue(form, "[data-answers-input]", payload)).to.equal(true);
    expect(form.querySelector("[data-answers-input]").value).to.equal(JSON.stringify(payload));
  });
});
