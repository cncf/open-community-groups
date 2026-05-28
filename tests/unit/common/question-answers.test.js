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

    const form = document.getElementById("questions-form");
    const payload = collectQuestionAnswers(form, { answerSelector: "[data-answer]" });

    expect(payload).to.deep.equal({
      answers: [
        { question_id: "question-text", value: "Accessibility needs" },
        { question_id: "question-radio", value: "two" },
        { question_id: "question-checkbox", value: ["alpha", "beta"] },
      ],
    });
  });

  it("validates required multi-select answers", () => {
    document.body.innerHTML = `
      <form id="questions-form">
        <fieldset data-question-id="question-checkbox"
                  data-question-kind="multi-select"
                  data-question-required="true">
          <input type="checkbox" data-answer value="alpha">
        </fieldset>
      </form>
    `;

    const form = document.getElementById("questions-form");
    const input = form.querySelector("[data-answer]");
    const payload = collectQuestionAnswers(form, { answerSelector: "[data-answer]" });

    expect(payload).to.equal(null);
    expect(input.validationMessage).to.equal("Select at least one option.");

    input.checked = true;
    const nextPayload = collectQuestionAnswers(form, { answerSelector: "[data-answer]" });

    expect(input.validationMessage).to.equal("");
    expect(nextPayload).to.deep.equal({
      answers: [{ question_id: "question-checkbox", value: ["alpha"] }],
    });
  });

  it("serializes answer payloads into hidden inputs", () => {
    document.body.innerHTML = `
      <form id="questions-form">
        <input type="hidden" data-answers-input>
      </form>
    `;

    const form = document.getElementById("questions-form");
    const payload = { answers: [{ question_id: "question-text", value: "Yes" }] };

    expect(setQuestionAnswersInputValue(form, "[data-answers-input]", payload)).to.equal(true);
    expect(form.querySelector("[data-answers-input]").value).to.equal(JSON.stringify(payload));
  });
});
