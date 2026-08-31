import { expect } from "@open-wc/testing";

import "/static/js/dashboard/confirm-actions.js";
import "/static/js/dashboard/user/invitations.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";

const renderOfferDom = ({ isSimpleRsvp = false } = {}) => {
  document.body.innerHTML = `
    <div id="dashboard-content"></div>
    <button
      data-user-event-offer-open
      data-user-event-offer-modal="event-offer-modal"
      type="button"
    >
      Claim offer
    </button>
    <div id="event-offer-modal" data-user-event-offer-dialog class="hidden">
      <button data-user-event-offer-close type="button">Close</button>
      <form data-user-event-offer-form data-is-simple-rsvp="${isSimpleRsvp}">
        <fieldset
          data-question-id="question-1"
          data-question-kind="free-text"
          data-question-required="true"
        >
          <textarea data-question-answer required></textarea>
        </fieldset>
        <input data-user-event-offer-answers name="registration_answers" type="hidden" />
        <input name="event_ticket_type_id" type="hidden" value="ticket-1" />
        <input name="discount_code" value="  SAVE10  " />
        <button type="submit">Claim offer</button>
      </form>
    </div>
    <button
      data-confirm-action
      data-error-message="Something went wrong canceling checkout. Please try again later."
      data-user-event-offer-checkout-cancel
      type="button"
    >
      Cancel checkout
    </button>
  `;

  return {
    answersInput: document.querySelector("[data-user-event-offer-answers]"),
    cancelButton: document.querySelector("[data-user-event-offer-checkout-cancel]"),
    discountInput: document.querySelector('[name="discount_code"]'),
    form: document.querySelector("[data-user-event-offer-form]"),
    modal: document.querySelector("[data-user-event-offer-dialog]"),
    openButton: document.querySelector("[data-user-event-offer-open]"),
    questionAnswer: document.querySelector("[data-question-answer]"),
  };
};

describe("dashboard user invitations", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/user?tab=invitations",
    withHtmx: true,
    withSwal: true,
  });

  it("opens and closes an offer claim modal", () => {
    // Render the offer controls and open the modal.
    const { modal, openButton } = renderOfferDom();
    openButton.click();

    // The modal becomes visible and can be closed from its close action.
    expect(modal.classList.contains("hidden")).to.equal(false);
    modal.querySelector("[data-user-event-offer-close]").click();
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("restores focus to an unfocused offer trigger after closing with Escape", () => {
    // Keep focus elsewhere while opening through the claim action.
    const { modal, openButton } = renderOfferDom();
    const previousButton = document.createElement("button");
    document.body.prepend(previousButton);
    previousButton.focus();
    openButton.click();

    // Escape closes the modal and returns focus to the explicit trigger.
    document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.activeElement).to.equal(openButton);
  });

  it("wraps forward and reverse focus within an open offer modal", () => {
    // Open an offer modal and resolve its first and last keyboard targets.
    const { form, modal, openButton } = renderOfferDom();
    openButton.click();
    const closeButton = modal.querySelector("[data-user-event-offer-close]");
    const submitButton = form.querySelector('button[type="submit"]');

    // Tab from the final target wraps to the first modal control.
    submitButton.focus();
    const forwardEvent = new KeyboardEvent("keydown", {
      bubbles: true,
      cancelable: true,
      key: "Tab",
    });
    document.dispatchEvent(forwardEvent);
    expect(forwardEvent.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(closeButton);

    // Shift+Tab from the first target wraps to the final modal control.
    const backwardEvent = new KeyboardEvent("keydown", {
      bubbles: true,
      cancelable: true,
      key: "Tab",
      shiftKey: true,
    });
    document.dispatchEvent(backwardEvent);
    expect(backwardEvent.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(submitButton);
  });

  it("serializes claim-time answers and normalizes discount codes", () => {
    // Render and complete the ticket claim form.
    const { answersInput, discountInput, form, questionAnswer } = renderOfferDom();
    questionAnswer.value = "Vegetarian";
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    const parameters = { discount_code: discountInput.value };
    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters,
        unfilteredParameters: { ...parameters },
      },
    });
    form.dispatchEvent(configEvent);

    // The request payload contains normalized question answers and discount code.
    expect(JSON.parse(answersInput.value)).to.deep.equal({
      answers: [{ question_id: "question-1", value: "Vegetarian" }],
    });
    expect(discountInput.value).to.equal("SAVE10");
    expect(parameters.discount_code).to.equal("SAVE10");
    expect(configEvent.detail.unfilteredParameters.discount_code).to.equal("SAVE10");
  });

  it("omits an empty discount code from offer claims", () => {
    // Render a ticket claim with an optional blank discount.
    const { discountInput, form } = renderOfferDom();
    discountInput.value = "   ";
    const parameters = { discount_code: discountInput.value };

    // Configure the HTMX request for the blank optional field.
    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters,
        unfilteredParameters: { ...parameters },
      },
    });
    form.dispatchEvent(configEvent);

    // Both HTMX parameter collections omit the blank discount.
    expect(parameters).to.not.have.property("discount_code");
    expect(configEvent.detail.unfilteredParameters).to.not.have.property("discount_code");
  });

  for (const [claimKind, isSimpleRsvp, successMessage] of [
    ["free ticket", false, "Your ticket has been claimed."],
    ["simple RSVP", true, "Your RSVP has been confirmed."],
  ]) {
    it(`refreshes invitations after a ${claimKind} claim`, () => {
      // Render the open offer claim modal.
      const { form, modal, openButton, questionAnswer } = renderOfferDom({ isSimpleRsvp });
      openButton.click();
      questionAnswer.value = "Vegetarian";

      // Complete the claim without an external checkout redirect.
      dispatchHtmxAfterRequest(form, {
        responseText: JSON.stringify({ status: "attendee" }),
        status: 200,
      });

      // The modal closes, success feedback is shown, and the dashboard refreshes.
      expect(modal.classList.contains("hidden")).to.equal(true);
      expect(env.current.swal.calls.at(-1)).to.include({
        icon: "info",
        text: successMessage,
      });
      expect(env.current.htmx.triggerCalls).to.deep.equal([
        ["#dashboard-content", "refresh-user-dashboard-content"],
      ]);
    });
  }

  it("removes a stale offer after an expired claim", () => {
    // Open the claim modal for an offer that expires before submission.
    const { form, modal, openButton } = renderOfferDom();
    openButton.click();

    // Reject the stale claim with the typed offer conflict.
    dispatchHtmxAfterRequest(form, {
      responseText: JSON.stringify({ conflict: "admission-offer-unavailable" }),
      status: 409,
    });

    // The stale modal closes, the exact error is shown, and the list refreshes.
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      icon: "error",
      text: "Ticket offer expired or is no longer available.",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#dashboard-content", "refresh-user-dashboard-content"],
    ]);
  });

  for (const [conflict, message] of [
    [
      "admission-offer-price-locked",
      "This ticket offer is locked at its stored price. Clear the discount code to claim it.",
    ],
    [
      "payment-setup-unavailable",
      "Payment is temporarily unavailable for this ticket offer. Try again before the offer deadline.",
    ],
    [
      "payment-window-unavailable",
      "The confirmation window for this ticket offer is no longer available. Try again before the offer deadline.",
    ],
    [
      "ticket-type-price-unavailable",
      "This ticket offer does not have a current price. Try again before the offer deadline.",
    ],
  ]) {
    it(`keeps a retryable offer open for ${conflict}`, () => {
      // Open an offer that is temporarily blocked at claim time.
      const { form, modal, openButton } = renderOfferDom();
      openButton.click();

      // Return the typed retryable claim conflict.
      dispatchHtmxAfterRequest(form, {
        responseText: JSON.stringify({ conflict }),
        status: 409,
      });

      // The deadline-bound offer remains open with an actionable explanation.
      expect(modal.classList.contains("hidden")).to.equal(false);
      expect(env.current.swal.calls.at(-1)).to.include({
        icon: "error",
        text: message,
      });
      expect(env.current.htmx.triggerCalls).to.deep.equal([]);
    });
  }

  it("refreshes invitations after checkout cancellation", () => {
    // Render a checkout cancellation action.
    const { cancelButton } = renderOfferDom();

    // Complete checkout cancellation successfully.
    dispatchHtmxAfterRequest(cancelButton, {
      responseText: JSON.stringify({ status: "invitation-approved" }),
      status: 200,
    });

    // The offer becomes claimable again and the dashboard refreshes.
    expect(env.current.swal.calls.at(-1)).to.include({
      icon: "info",
      text: "Your checkout has been canceled. The offer is ready to claim again.",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#dashboard-content", "refresh-user-dashboard-content"],
    ]);
  });

  it("shows checkout cancellation errors once through the shared confirmation handler", () => {
    // Render a checkout cancellation action.
    const { cancelButton } = renderOfferDom();

    // Fail checkout cancellation.
    dispatchHtmxAfterRequest(cancelButton, {
      status: 500,
    });

    // This module does not duplicate shared error feedback or refresh stale data.
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      icon: "error",
      text: "Something went wrong canceling checkout. Please try again later.",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([]);
  });
});
