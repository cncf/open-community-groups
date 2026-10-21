import { expect } from "@open-wc/testing";

import {
  initializeUserEventRefundActions,
  initializeUserEventSurveyModal,
} from "/static/js/dashboard/user/events.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { setLocationPath } from "/tests/unit/test-utils/dom.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

/**
 * Renders the survey modal shell of the events list with its content.
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

describe("dashboard user events", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/user?tab=events",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
  });

  it("closes the open actions dropdown when another row action menu opens", () => {
    // Render two user event action dropdowns.
    document.body.innerHTML = `
      <details data-actions-menu>
        <summary>First actions</summary>
        <button type="button">First action</button>
      </details>
      <details data-actions-menu>
        <summary>Second actions</summary>
        <button type="button">Second action</button>
      </details>
    `;

    // Set up dropdowns.
    const dropdowns = document.querySelectorAll("[data-actions-menu]");

    dropdowns[0].open = true;
    dropdowns[1].querySelector("summary").click();

    // Assert that the flag is disabled.
    expect(dropdowns[0].open).to.equal(false);
    expect(dropdowns[1].open).to.equal(true);
  });

  it("closes open action dropdowns when clicking outside", () => {
    // Render an open user event action dropdown.
    document.body.innerHTML = `
      <details data-actions-menu open>
        <summary>Actions</summary>
        <button type="button">Action</button>
      </details>
      <button type="button" id="outside-button">Outside</button>
    `;

    // Set up dropdown.
    const dropdown = document.querySelector("[data-actions-menu]");

    // Click the outside button button.
    document.getElementById("outside-button").click();

    // Assert that the flag is disabled.
    expect(dropdown.open).to.equal(false);
  });
  it("refreshes My Events after checkout cancellation", () => {
    // Render an active checkout cancellation action.
    document.body.innerHTML = `
      <div id="dashboard-content"></div>
      <button data-user-event-checkout-cancel type="button">Cancel checkout</button>
    `;
    const cancelButton = document.querySelector("[data-user-event-checkout-cancel]");

    // Complete checkout cancellation successfully.
    dispatchHtmxAfterRequest(cancelButton, { status: 200 });

    // The active checkout row is refreshed away.
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#dashboard-content", "refresh-user-dashboard-content"],
    ]);
  });

  it("keeps My Events unchanged after failed checkout cancellation", () => {
    // Render an active checkout cancellation action.
    document.body.innerHTML = `
      <div id="dashboard-content"></div>
      <button data-user-event-checkout-cancel type="button">Cancel checkout</button>
    `;
    const cancelButton = document.querySelector("[data-user-event-checkout-cancel]");

    // Fail checkout cancellation.
    dispatchHtmxAfterRequest(cancelButton, { status: 500 });

    // The current row remains available for retry.
    expect(env.current.htmx.triggerCalls).to.deep.equal([]);
  });

  it("shows refund actions only when the enrollment endpoint confirms eligibility", async () => {
    // Render the hidden paid-row action before loading exact eligibility.
    document.body.innerHTML = `
      <li class="hidden" data-user-event-refund-action data-enrollment-url="/community/event/1/enrollment">
        <a href="/event#refund-btn-main">Request refund</a>
      </li>
    `;
    const fetchMock = mockFetch({
      response: new Response(JSON.stringify({ can_request_refund: true }), {
        headers: { "Content-Type": "application/json" },
        status: 200,
      }),
    });

    try {
      initializeUserEventRefundActions(document);
      await waitForMicrotask();
      await waitForMicrotask();

      const refundAction = document.querySelector("[data-user-event-refund-action]");
      expect(fetchMock.calls[0]?.[0]).to.equal("/community/event/1/enrollment");
      expect(refundAction.classList.contains("hidden")).to.equal(false);
    } finally {
      fetchMock.restore();
    }
  });

  it("opens the survey modal once its content is loaded", () => {
    // Render the closed survey modal and the panel button that loads it.
    const { content, modal } = renderSurveyModal();
    const trigger = document.querySelector("[data-user-event-survey-open]");

    // Swap the survey content into the modal.
    dispatchHtmxAfterSwap(content, { requestConfig: { elt: trigger }, target: content });

    // Verify the modal is shown to the user.
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(modal.getAttribute("aria-hidden")).to.equal("false");
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

  it("opens the survey requested by an opening email on load", () => {
    // Render the survey modal the server marks to open on load.
    const { modal } = renderSurveyModal({ openOnLoad: true });

    // Initialize the requested survey twice, as HTMX loads can repeat.
    initializeUserEventSurveyModal(document);
    initializeUserEventSurveyModal(document);

    // Verify the modal opens once and stays open.
    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("closes the survey modal and forgets the requested survey", () => {
    // Render the survey modal opened from an opening email link.
    setLocationPath("/dashboard/user?tab=events&event_survey_id=00000000-0000-0000-0000-000000000001");
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserEventSurveyModal(document);

    // Cancel the survey.
    modal.querySelector("button[data-user-event-survey-close]").click();

    // Verify the modal closes and a reload will not open it again.
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(window.location.search).to.equal("?tab=events");
  });

  it("closes the survey modal on Escape", () => {
    // Render an open survey modal.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserEventSurveyModal(document);

    // Press Escape.
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    // Verify the modal closes.
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("asks before Cancel discards changed survey answers", async () => {
    // Render an open survey modal and change an answer.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserEventSurveyModal(document);
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
    initializeUserEventSurveyModal(document);
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

  it("keeps Tab navigation inside the survey modal", () => {
    // Render an open survey modal and focus its last control.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserEventSurveyModal(document);
    const submit = modal.querySelector("button[type='submit']");
    submit.focus();

    // Press Tab on the last control.
    const event = new KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true });
    document.dispatchEvent(event);

    // Verify the focus wraps to the first control.
    expect(event.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(modal.querySelector("#survey-answer"));
  });

  it("closes the survey modal after saving the answers", () => {
    // Render an open survey modal.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserEventSurveyModal(document);
    const form = modal.querySelector("[data-user-event-survey-form]");

    // Save the answers successfully.
    dispatchHtmxAfterRequest(form, { status: 204 });

    // Verify the success alert and the closed modal.
    expect(env.current.swal.calls.at(-1)?.text).to.equal("Survey answers saved.");
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("keeps the survey modal open when saving the answers fails", () => {
    // Render an open survey modal.
    const { modal } = renderSurveyModal({ openOnLoad: true });
    initializeUserEventSurveyModal(document);
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
});
