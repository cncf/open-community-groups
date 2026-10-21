import { expect } from "@open-wc/testing";

import { initializeUserSurveyModal } from "/static/js/dashboard/user/surveys.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { setLocationPath } from "/tests/unit/test-utils/dom.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";

/**
 * Renders the survey modal shell of the surveys list with an open survey form.
 * @param {object} options Fixture options.
 * @param {boolean} options.openOnLoad Whether the modal opens on load.
 * @returns {{modal: HTMLElement, content: HTMLElement}} Modal elements.
 */
const renderSurveyModal = ({ openOnLoad = false } = {}) => {
  document.body.innerHTML = `
    <button type="button" data-user-event-survey-open>Answer</button>
    <div id="user-event-survey-modal"
         data-user-event-survey-modal
         ${openOnLoad ? "data-open-on-load" : ""}
         role="dialog"
         aria-modal="true"
         class="hidden">
      <div data-user-event-survey-close class="modal-overlay"></div>
      <div id="user-event-survey-modal-content">
        <form data-user-event-survey-form>
          <textarea id="survey-answer" data-question-answer>Great talks</textarea>
          <input type="hidden" data-question-answers-input name="answers">
          <button type="button" data-user-event-survey-close>Cancel</button>
          <button type="submit">Submit answers</button>
        </form>
      </div>
    </div>
  `;

  return {
    content: document.getElementById("user-event-survey-modal-content"),
    modal: document.getElementById("user-event-survey-modal"),
  };
};

/**
 * Renders the survey modal shell with the read-only answers of a closed survey.
 * @returns {HTMLElement} Survey modal.
 */
const renderClosedSurveyModal = () => {
  document.body.innerHTML = `
    <div id="user-event-survey-modal"
         data-user-event-survey-modal
         data-open-on-load
         role="dialog"
         aria-modal="true"
         class="hidden">
      <div data-user-event-survey-close class="modal-overlay"></div>
      <div id="user-event-survey-modal-content">
        <div data-user-event-survey-answers>
          <p>Well organized</p>
        </div>
        <button type="button" data-user-event-survey-close>Close</button>
      </div>
    </div>
  `;

  return document.getElementById("user-event-survey-modal");
};

describe("dashboard user surveys", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/user?tab=surveys",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
  });

  it("asks before Cancel discards changed survey answers", async () => {
    // Render an open survey modal and change an answer.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserSurveyModal(document);
    modal.querySelector("#survey-answer").value = "Longer breaks";

    // Cancel the survey and keep answering.
    env.current.swal.setNextResult({ isConfirmed: false });
    modal.querySelector("button[data-user-event-survey-close]").click();
    await waitForMicrotask();

    // Verify the confirmation and the answers stay open.
    expect(env.current.swal.calls.at(-1)?.text).to.equal(
      "You have unsaved answers. If you close the survey, they will be lost.",
    );
    expect(modal.classList.contains("hidden")).to.equal(false);

    // Close from the overlay and discard the answers.
    env.current.swal.setNextResult({ isConfirmed: true });
    modal.querySelector(".modal-overlay").click();
    await waitForMicrotask();

    // Verify the modal closes.
    expect(env.current.swal.calls.length).to.equal(2);
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("asks before Escape discards changed survey answers", async () => {
    // Render an open survey modal and change an answer.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserSurveyModal(document);
    modal.querySelector("#survey-answer").value = "Longer breaks";

    // Press Escape twice while the confirmation shows and keep answering.
    env.current.swal.setNextResult({ isConfirmed: false });
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    await waitForMicrotask();

    // Verify a single confirmation and the modal stays open.
    expect(env.current.swal.calls.length).to.equal(1);
    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("closes the read-only answers of a closed survey without asking", () => {
    // Render the answers of a closed survey opened on load.
    const modal = renderClosedSurveyModal();
    initializeUserSurveyModal(document);
    expect(modal.classList.contains("hidden")).to.equal(false);

    // Close the answers.
    modal.querySelector("button[data-user-event-survey-close]").click();

    // Verify the modal closes without a discard confirmation.
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.length).to.equal(0);
  });

  it("closes the survey modal after saving the answers", () => {
    // Render an open survey modal.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserSurveyModal(document);
    const form = modal.querySelector("[data-user-event-survey-form]");

    // Save the answers successfully.
    dispatchHtmxAfterRequest(form, { status: 204 });

    // Verify the success alert and the closed modal.
    expect(env.current.swal.calls.at(-1)?.text).to.equal("Survey answers saved.");
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("closes the survey modal and forgets the requested survey", () => {
    // Render the survey modal opened from an opening email link.
    setLocationPath("/dashboard/user?tab=surveys&event_survey_id=00000000-0000-0000-0000-000000000001");
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserSurveyModal(document);

    // Cancel the survey.
    modal.querySelector("button[data-user-event-survey-close]").click();

    // Verify the modal closes and a reload will not open it again.
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(window.location.search).to.equal("?tab=surveys");
  });

  it("closes the survey modal on Escape", () => {
    // Render an open survey modal.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserSurveyModal(document);

    // Press Escape.
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    // Verify the modal closes.
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("ignores requests outside the survey form", () => {
    // Render an open survey modal and another form.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserSurveyModal(document);
    const other = document.createElement("form");
    document.body.append(other);

    // Complete a request of the other form.
    dispatchHtmxAfterRequest(other, { status: 204 });

    // Verify no survey feedback shows and the modal stays open.
    expect(env.current.swal.calls.length).to.equal(0);
    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("ignores swaps outside the survey modal", () => {
    // Render the closed survey modal.
    const { modal } = renderSurveyModal();
    const other = document.createElement("div");
    document.body.append(other);

    // Swap content into another region.
    dispatchHtmxAfterSwap(other, { target: other });

    // Verify the modal stays closed.
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("keeps Tab navigation inside the survey modal", () => {
    // Render an open survey modal and focus its last control.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserSurveyModal(document);
    const submit = modal.querySelector("button[type='submit']");
    submit.focus();

    // Press Tab on the last control.
    const event = new KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true });
    document.dispatchEvent(event);

    // Verify the focus wraps to the first control.
    expect(event.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(modal.querySelector("#survey-answer"));
  });

  it("keeps the survey modal open when saving the answers fails", () => {
    // Render an open survey modal.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserSurveyModal(document);
    const form = modal.querySelector("[data-user-event-survey-form]");

    // Fail to save answers given to an outdated survey revision.
    dispatchHtmxAfterRequest(form, {
      status: 422,
      responseText: "the survey changed; review and try again",
    });

    // Verify the answers stay available to review and resubmit.
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(env.current.swal.calls.length).to.equal(1);
  });

  it("opens the survey modal once its content is loaded", () => {
    // Render the closed survey modal and the row button that loads it.
    const { content, modal } = renderSurveyModal();
    const trigger = document.querySelector("[data-user-event-survey-open]");

    // Swap the survey content into the modal.
    dispatchHtmxAfterSwap(content, { requestConfig: { elt: trigger }, target: content });

    // Verify the modal is shown to the user.
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(modal.getAttribute("aria-hidden")).to.equal("false");
  });

  it("opens the survey requested by an opening email on load", () => {
    // Render the survey modal the server marks to open on load.
    const { modal } = renderSurveyModal({ openOnLoad: true });

    // Initialize the requested survey twice, as HTMX loads can repeat.
    initializeUserSurveyModal(document);
    initializeUserSurveyModal(document);

    // Verify the modal opens once and stays open.
    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("stops submissions missing required answers before HTMX sends them", () => {
    // Render an open survey form with a required unanswered question.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserSurveyModal(document);
    const form = modal.querySelector("[data-user-event-survey-form]");
    const answer = form.querySelector("#survey-answer");
    answer.value = "";
    answer.required = true;

    // Submit the form.
    const event = new SubmitEvent("submit", { bubbles: true, cancelable: true });
    form.dispatchEvent(event);

    // Verify the submission is blocked without serializing answers.
    expect(event.defaultPrevented).to.equal(true);
    expect(form.querySelector("[data-question-answers-input]").value).to.equal("");
  });
});
