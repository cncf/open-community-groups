import { expect } from "@open-wc/testing";

import "/static/js/event/attendance.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxBeforeRequest } from "/tests/unit/test-utils/htmx.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

// Initialize attendance dom for the test.
const initializeAttendanceDom = async () => {
  document.body.dataset.attendanceListenersReady = "true";
  await import(`/static/js/event/attendance.js?test=${Date.now()}`);
};

const renderPaidAttendanceDom = ({
  starts = "2099-05-10T10:00:00Z",
  attendeeApprovalRequired = "false",
  hasVisibleTicketTypes = "true",
  ticketPurchaseAvailable = "true",
  ticketIsFreeOnly = "false",
  disabledTicketStatusLabel = "Sold out",
  includeButtonPriceBadge = true,
  includeTicketOptions = true,
  isTicketed = "true",
  markButtonPriceBadge = true,
  availabilityUrl = "",
  includeRegistrationQuestions = false,
  registrationWindowOpen = "true",
  registrationWindowUnavailableTitle = "",
  waitlistEnabled = "false",
} = {}) => {
  document.body.innerHTML = `
    <div
      data-attendance-container
      data-starts="${starts}"
      data-attendee-approval-required="${attendeeApprovalRequired}"
      data-has-sold-out-ticket-types="true"
      data-has-visible-ticket-types="${hasVisibleTicketTypes}"
      data-is-ticketed="${isTicketed}"
      data-paid-capable="true"
      data-ticket-purchase-available="${ticketPurchaseAvailable}"
      data-ticket-is-free-only="${ticketIsFreeOnly}"
      ${availabilityUrl ? `data-availability-url="${availabilityUrl}"` : ""}
      data-registration-window-open="${registrationWindowOpen}"
      ${
        registrationWindowUnavailableTitle
          ? `data-registration-window-unavailable-title="${registrationWindowUnavailableTitle}"`
          : ""
      }
      data-path="/events/test-event"
      data-attendee-meeting-access-open="false"
      data-waitlist-enabled="${waitlistEnabled}"
    >
      <button
        data-attendance-role="attendance-checker"
        hx-get="/test-community/event/test-event/attendance"
      ></button>
      <button data-attendance-role="loading-btn" class="hidden">
        <span data-attendance-label>Checking...</span>
      </button>
      <button data-attendance-role="signin-btn" class="hidden" data-path="/events/test-event">
        ${
          includeButtonPriceBadge
            ? `
        <span class="ticket-price-badge absolute left-1/2"${markButtonPriceBadge ? ' data-attendance-role="control-price-badge"' : ""}>
          From EUR 50.00
        </span>`
            : ""
        }
        <span data-attendance-label>Get ticket</span>
      </button>
      <button
        data-attendance-role="attend-btn"
        class="hidden"
      >
        ${
          includeButtonPriceBadge
            ? `
        <span class="ticket-price-badge absolute left-1/2"${markButtonPriceBadge ? ' data-attendance-role="control-price-badge"' : ""}>
          From EUR 50.00
        </span>`
            : ""
        }
        <span data-attendance-label>Get ticket</span>
      </button>
      ${
        includeRegistrationQuestions
          ? `
      <div
        id="questions-modal"
        data-attendance-role="registration-modal"
        class="hidden"
      >
        <div data-attendance-role="registration-modal-overlay"></div>
        <button data-attendance-role="registration-modal-close" type="button">Close</button>
        <form data-attendance-role="registration-form">
          <fieldset
            data-question-id="question-1"
            data-question-kind="free-text"
            data-question-required="true"
          >
            <textarea data-question-answer required></textarea>
          </fieldset>
          <input
            data-attendance-role="registration-answers-input"
            name="registration_answers"
            type="hidden"
          />
          <button data-attendance-role="registration-modal-submit" type="submit">Continue</button>
        </form>
      </div>`
          : ""
      }
      <div
        id="ticket-modal"
        data-attendance-role="ticket-modal"
        class="hidden"
      >
        <div data-attendance-role="ticket-modal-overlay"></div>
        <button data-attendance-role="ticket-modal-close" type="button">Close</button>
        <button data-attendance-role="ticket-modal-cancel" type="button">Cancel</button>
        <form
          data-attendance-role="checkout-form"
          data-attend-url="/test-community/event/event-1/attend"
          data-checkout-url="/test-community/event/event-1/checkout"
        >
          <input
            data-attendance-role="checkout-registration-answers-input"
            name="registration_answers"
            type="hidden"
          />
          <div data-attendance-role="ticket-modal-form">
            <div data-attendance-role="ticket-type-list">
              ${
                includeTicketOptions
                  ? `
              <label data-attendance-role="ticket-type-card">
                <input
                  data-attendance-role="ticket-type-option"
                  data-ticket-purchasable="true"
                  data-ticket-price-minor="0"
                  data-ticket-sold-out="false"
                  type="radio"
                  name="event_ticket_type_id"
                  value="ticket-2"
                />
                <div
                  data-attendance-role="ticket-type-card-body"
                  class="bg-white cursor-pointer hover:border-primary-300 hover:shadow-sm"
                >
                  <span data-attendance-role="ticket-type-title">Community</span>
                  <div class="ticket-price-badge">
                    Free
                  </div>
                </div>
              </label>
              <label data-attendance-role="ticket-type-card">
                <input
                  data-attendance-role="ticket-type-option"
                  data-ticket-purchasable="true"
                  data-ticket-price-minor="5000"
                  data-ticket-sold-out="false"
                  type="radio"
                  name="event_ticket_type_id"
                  value="ticket-1"
                />
                <div
                  data-attendance-role="ticket-type-card-body"
                  class="bg-white cursor-pointer hover:border-primary-300 hover:shadow-sm"
                >
                  <span data-attendance-role="ticket-type-title">General</span>
                  <div class="ticket-price-badge">
                    EUR 50.00
                  </div>
                </div>
              </label>
              <label data-attendance-role="ticket-type-card">
                <input
                  data-attendance-role="ticket-type-option"
                  data-ticket-purchasable="false"
                  data-ticket-price-minor="2500"
                  data-ticket-sold-out="true"
                  type="radio"
                  name="event_ticket_type_id"
                  value="ticket-3"
                  disabled
                />
                <div
                  data-attendance-role="ticket-type-card-body"
                  class="bg-stone-50 cursor-not-allowed opacity-60"
                >
                  <div data-attendance-role="ticket-type-summary">
                    <span data-attendance-role="ticket-type-title">Staff</span>
                  </div>
                  <span data-attendance-role="ticket-type-status-dot"></span>
                  <span data-attendance-role="ticket-type-status-label">${disabledTicketStatusLabel}</span>
                </div>
              </label>
              `
                  : ""
              }
            </div>
            <input
              data-attendance-role="discount-code-input"
              name="discount_code"
              value=""
            />
          </div>
          <button data-attendance-role="checkout-btn" type="submit">
            <span data-attendance-role="checkout-btn-spinner" class="absolute inset-0 hidden items-center justify-center">
              Loading
            </span>
            <span data-attendance-role="checkout-btn-label">Continue to checkout</span>
          </button>
        </form>
      </div>
      <button
        data-attendance-role="leave-btn"
        class="hidden"
      >
        <span data-attendance-label>Cancel attendance</span>
      </button>
      <details data-attendance-role="actions-menu" data-event-actions-menu class="hidden">
        <button
          data-attendance-role="checkout-resume-btn"
          class="hidden"
        >
          <span data-attendance-label>Continue to checkout</span>
        </button>
        <button
          data-attendance-role="checkout-cancel-btn"
          class="hidden"
        >
          <span data-attendance-label>Cancel checkout</span>
        </button>
      </details>
      <button
        data-attendance-role="refund-btn"
        type="button"
        class="hidden"
      >
        <span data-attendance-label>Request refund</span>
      </button>
      <div
        id="refund-modal"
        data-attendance-role="refund-modal"
        role="dialog"
        aria-hidden="true"
        class="hidden"
      >
        <div data-attendance-role="refund-modal-overlay"></div>
        <button data-attendance-role="refund-modal-close" type="button">Close</button>
        <form data-attendance-role="refund-form">
          <textarea
            data-attendance-role="refund-reason-input"
            name="requested_reason"
            autofocus
          ></textarea>
          <button data-attendance-role="refund-modal-cancel" type="button">Cancel</button>
          <button data-attendance-role="refund-modal-submit" type="submit">
            <span data-attendance-role="refund-modal-submit-spinner" class="hidden">Loading</span>
            <span data-attendance-role="refund-modal-submit-label">Request refund</span>
          </button>
        </form>
      </div>
    </div>
  `;

  return {
    container: document.querySelector("[data-attendance-container]"),
    checker: document.querySelector('[data-attendance-role="attendance-checker"]'),
    signinButton: document.querySelector('[data-attendance-role="signin-btn"]'),
    attendButton: document.querySelector('[data-attendance-role="attend-btn"]'),
    actionsMenu: document.querySelector('[data-attendance-role="actions-menu"]'),
    checkoutCancelButton: document.querySelector('[data-attendance-role="checkout-cancel-btn"]'),
    checkoutResumeButton: document.querySelector('[data-attendance-role="checkout-resume-btn"]'),
    questionsModal: document.querySelector('[data-attendance-role="registration-modal"]'),
    questionsModalClose: document.querySelector('[data-attendance-role="registration-modal-close"]'),
    registrationForm: document.querySelector('[data-attendance-role="registration-form"]'),
    registrationAnswer: document.querySelector("[data-question-answer]"),
    registrationAnswersInput: document.querySelector('[data-attendance-role="registration-answers-input"]'),
    refundButton: document.querySelector('[data-attendance-role="refund-btn"]'),
    refundForm: document.querySelector('[data-attendance-role="refund-form"]'),
    refundModal: document.querySelector('[data-attendance-role="refund-modal"]'),
    refundModalCancel: document.querySelector('[data-attendance-role="refund-modal-cancel"]'),
    refundModalOverlay: document.querySelector('[data-attendance-role="refund-modal-overlay"]'),
    refundReasonInput: document.querySelector('[data-attendance-role="refund-reason-input"]'),
    refundSubmitButton: document.querySelector('[data-attendance-role="refund-modal-submit"]'),
    refundSubmitButtonLabel: document.querySelector('[data-attendance-role="refund-modal-submit-label"]'),
    refundSubmitButtonSpinner: document.querySelector('[data-attendance-role="refund-modal-submit-spinner"]'),
    ticketModal: document.querySelector('[data-attendance-role="ticket-modal"]'),
    checkoutForm: document.querySelector('[data-attendance-role="checkout-form"]'),
    checkoutRegistrationAnswersInput: document.querySelector(
      '[data-attendance-role="checkout-registration-answers-input"]',
    ),
    ticketModalForm: document.querySelector('[data-attendance-role="ticket-modal-form"]'),
    ticketTypeOptions: document.querySelectorAll('[data-attendance-role="ticket-type-option"]'),
    ticketTypeTitles: () =>
      Array.from(document.querySelectorAll('[data-attendance-role="ticket-type-title"]')).map(
        (node) => node.textContent,
      ),
    ticketStatusLabels: () =>
      Array.from(document.querySelectorAll('[data-attendance-role="ticket-type-status-label"]')).map(
        (node) => node.textContent,
      ),
    ticketCardBodies: document.querySelectorAll('[data-attendance-role="ticket-type-card-body"]'),
    checkoutButton: document.querySelector('[data-attendance-role="checkout-btn"]'),
    checkoutButtonSpinner: document.querySelector('[data-attendance-role="checkout-btn-spinner"]'),
    checkoutButtonLabel: document.querySelector('[data-attendance-role="checkout-btn-label"]'),
    ticketPriceBadge: Array.from(document.querySelectorAll(".ticket-price-badge")).find(
      (node) => node.textContent?.trim() === "EUR 50.00",
    ),
    ticketModalOverlay: document.querySelector('[data-attendance-role="ticket-modal-overlay"]'),
    ticketModalCancel: document.querySelector('[data-attendance-role="ticket-modal-cancel"]'),
  };
};

describe("event attendance paid modal", () => {
  const env = useDashboardTestEnv({
    path: "/events/test-event",
    withSwal: true,
    bodyDatasetKeysToClear: ["attendanceListenersReady"],
  });

  it("keeps the logged-out paid flow on the sign-in alert instead of opening the modal", async () => {
    // Render a paid event while the visitor is signed out.
    const { checker, signinButton, ticketModal } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Mark the attendance check as a guest response.
    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    // Verify the paid action stays on the signed-out button.
    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Get ticket");

    // Click the signed-out paid attendance button.
    signinButton.click();

    // Verify the ticket modal stays closed and the sign-in alert is shown.
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
    expect(env.current.swal.calls.at(-1)).to.include({
      icon: "info",
    });
    expect(env.current.swal.calls.at(-1)?.html).to.include("get a ticket for this event");
    expect(env.current.swal.calls.at(-1)?.html).to.include("/log-in?next_url=%2Fevents%2Ftest-event");
  });

  it("shows invitation-only ticketing as information while signed out", async () => {
    // Render a private ticketed event while the visitor is signed out.
    const { attendButton, checker, signinButton, ticketModal } = renderPaidAttendanceDom({
      hasVisibleTicketTypes: "false",
      ticketPurchaseAvailable: "false",
    });
    await initializeAttendanceDom();

    // Apply the signed-out attendance fallback.
    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    // Invitation-only ticketing remains informational rather than prompting sign-in.
    expect(signinButton.classList.contains("hidden")).to.equal(true);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Tickets are available by invitation only",
    );
    expect(attendButton.title).to.equal("Tickets for this event are available by invitation only.");
    attendButton.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls).to.deep.equal([]);
  });

  it("shows unavailable paid ticketing as information while signed out", async () => {
    // Render a paid event without an available checkout path.
    const { attendButton, checker, signinButton, ticketModal } = renderPaidAttendanceDom({
      ticketPurchaseAvailable: "false",
    });
    await initializeAttendanceDom();

    // Apply the signed-out attendance fallback.
    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    // Payment unavailability cannot be bypassed by signing in.
    expect(signinButton.classList.contains("hidden")).to.equal(true);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Paid tickets temporarily unavailable",
    );
    expect(attendButton.title).to.equal("Tickets are not currently available for this event.");
    attendButton.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls).to.deep.equal([]);
  });

  it("opens the paid ticket modal for guests and enables checkout after a ticket is selected", async () => {
    // Keep references to the fixture controls under assertion.
    const { checker, attendButton, ticketModal, ticketTypeOptions, checkoutButton } =
      renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify opens the paid ticket modal for guests and enables checkout.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Get ticket");
    expect(attendButton.querySelector(".ticket-price-badge")?.textContent?.trim()).to.equal("From EUR 50.00");
    expect(attendButton.querySelector(".ticket-price-badge")?.hidden).to.equal(false);
    expect(attendButton.querySelector(".ticket-price-badge")?.style.display).to.equal("");

    // Verify opens the paid ticket modal for guests.
    attendButton.click();

    // Verify opens the paid ticket modal for guests and enables checkout.
    expect(ticketModal.classList.contains("hidden")).to.equal(false);
    expect(checkoutButton.disabled).to.equal(true);
    expect(checkoutButton.title).to.equal("Choose a ticket to continue.");

    // Update the checkbox state before asserting the new state.
    ticketTypeOptions[0].checked = true;
    ticketTypeOptions[0].dispatchEvent(new Event("change", { bubbles: true }));

    // Verify opens the paid ticket modal for guests and enables checkout.
    expect(checkoutButton.disabled).to.equal(false);
    expect(checkoutButton.hasAttribute("title")).to.equal(false);
    expect(checkoutButton.querySelector("[data-attendance-role='checkout-btn-label']")?.textContent).to.equal(
      "Get free ticket",
    );
  });

  it("routes approval ticket selections through a ticket request", async () => {
    // Render an approval-based ticket event with no directly sellable tiers.
    const { attendButton, checker, checkoutButton, checkoutForm, ticketModal, ticketTypeOptions } =
      renderPaidAttendanceDom({
        attendeeApprovalRequired: "true",
        ticketPurchaseAvailable: "false",
      });
    await initializeAttendanceDom();

    // Apply the authenticated guest state and open ticket selection.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request ticket");
    attendButton.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(false);

    // Approval requests may select a sold-out public tier.
    ticketTypeOptions[2].checked = true;
    ticketTypeOptions[2].dispatchEvent(new Event("change", { bubbles: true }));
    expect(ticketTypeOptions[2].disabled).to.equal(false);
    expect(checkoutButton.querySelector("[data-attendance-role='checkout-btn-label']")?.textContent).to.equal(
      "Request ticket",
    );

    // The modal submits the selected tier to the attendance request endpoint.
    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters: {
          discount_code: "CODE",
          event_ticket_type_id: "ticket-3",
          registration_answers: '{"answers":[{"question_id":"question-1","value":"Vegetarian"}]}',
        },
        path: "/test-community/event/event-1/checkout",
        unfilteredParameters: {
          discount_code: "CODE",
          event_ticket_type_id: "ticket-3",
          registration_answers: '{"answers":[{"question_id":"question-1","value":"Vegetarian"}]}',
        },
      },
    });
    checkoutForm.dispatchEvent(configEvent);
    expect(configEvent.detail.path).to.equal("/test-community/event/event-1/attend");
    expect(configEvent.detail.parameters).to.not.have.property("discount_code");
    expect(configEvent.detail.parameters.registration_answers).to.equal(
      '{"answers":[{"question_id":"question-1","value":"Vegetarian"}]}',
    );
  });

  it("submits a generic request when approval tiers are invitation-only", async () => {
    // Render a fully private approval event with no public tier selector.
    const { attendButton, checker, ticketModal } = renderPaidAttendanceDom({
      attendeeApprovalRequired: "true",
      hasVisibleTicketTypes: "false",
      ticketPurchaseAvailable: "false",
    });
    await initializeAttendanceDom();

    // Apply the authenticated guest state.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request ticket");

    // The primary request remains on the attendance endpoint instead of opening an empty modal.
    const clickEvent = new MouseEvent("click", { bubbles: true, cancelable: true });
    attendButton.dispatchEvent(clickEvent);
    expect(clickEvent.defaultPrevented).to.equal(false);
    expect(ticketModal.classList.contains("hidden")).to.equal(true);

    // The matching HTMX request is still allowed for the generic request path.
    const beforeRequestEvent = dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true });
    expect(beforeRequestEvent.defaultPrevented).to.equal(false);
  });

  it("blocks ticketed attend HTMX requests while the ticket modal owns the click", async () => {
    // Render a ticketed event with visible public tiers.
    const { attendButton, checker, ticketModal } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Apply the authenticated guest state.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // The direct HTMX request is canceled because the click opens ticket selection.
    const beforeRequestEvent = dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true });
    expect(beforeRequestEvent.defaultPrevented).to.equal(true);
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
  });

  it("routes sold-out direct tiers through their waiting list", async () => {
    // Render a direct ticket event where sold-out tiers may join a waiting list.
    const { attendButton, checker, checkoutButton, checkoutForm, ticketTypeOptions } =
      renderPaidAttendanceDom({
        waitlistEnabled: "true",
      });
    await initializeAttendanceDom();

    // Open the tier selector and choose the sold-out tier.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });
    attendButton.click();
    ticketTypeOptions[2].checked = true;
    ticketTypeOptions[2].dispatchEvent(new Event("change", { bubbles: true }));

    // The selected tier exposes its own waiting-list action.
    expect(ticketTypeOptions[2].disabled).to.equal(false);
    expect(checkoutButton.querySelector("[data-attendance-role='checkout-btn-label']")?.textContent).to.equal(
      "Join waiting list",
    );

    // The ticket form submits the tier to the attendance endpoint without discounts.
    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters: {
          discount_code: "CODE",
          event_ticket_type_id: "ticket-3",
        },
        path: "/test-community/event/event-1/checkout",
        unfilteredParameters: {
          discount_code: "CODE",
          event_ticket_type_id: "ticket-3",
        },
      },
    });
    checkoutForm.dispatchEvent(configEvent);
    expect(configEvent.detail.path).to.equal("/test-community/event/event-1/attend");
    expect(configEvent.detail.parameters).to.not.have.property("discount_code");
  });

  it("uses free ticket wording when every public tier is free", async () => {
    // Render an intrinsically free ticket event.
    const { attendButton, checker } = renderPaidAttendanceDom({
      ticketIsFreeOnly: "true",
    });
    await initializeAttendanceDom();

    // Apply the authenticated guest state.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // The primary action describes the ticket as free without currency wording.
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Get free ticket");
  });

  it("collects registration questions after ticket selection without showing a checkout alert", async () => {
    // Render paid attendance controls with registration questions.
    const {
      checker,
      attendButton,
      checkoutForm,
      questionsModal,
      registrationForm,
      registrationAnswer,
      registrationAnswersInput,
      checkoutRegistrationAnswersInput,
      checkoutButtonLabel,
      checkoutButtonSpinner,
      ticketModal,
      ticketTypeOptions,
    } = renderPaidAttendanceDom({ includeRegistrationQuestions: true });
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Open ticket selection before deciding whether this action needs answers.
    attendButton.click();
    expect(questionsModal.classList.contains("hidden")).to.equal(true);
    expect(ticketModal.classList.contains("hidden")).to.equal(false);

    // Select the paid tier and begin checkout.
    ticketTypeOptions[1].checked = true;
    ticketTypeOptions[1].dispatchEvent(new Event("change", { bubbles: true }));
    const checkoutEvent = new CustomEvent("htmx:beforeRequest", {
      bubbles: true,
      cancelable: true,
    });
    checkoutForm.dispatchEvent(checkoutEvent);
    expect(checkoutEvent.defaultPrevented).to.equal(true);
    expect(questionsModal.classList.contains("hidden")).to.equal(false);
    expect(ticketModal.classList.contains("hidden")).to.equal(true);

    // Answer the required form question.
    checkoutForm.addEventListener("submit", (event) => event.preventDefault(), { once: true });
    registrationAnswer.value = "Vegetarian lunch";
    registrationForm.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));

    // Answers close the question modal and resume the selected checkout form.
    expect(questionsModal.classList.contains("hidden")).to.equal(true);
    expect(ticketModal.classList.contains("hidden")).to.equal(false);
    expect(env.current.swal.calls).to.have.length(0);
    expect(JSON.parse(registrationAnswersInput.value)).to.deep.equal({
      answers: [{ question_id: "question-1", value: "Vegetarian lunch" }],
    });
    expect(checkoutRegistrationAnswersInput.value).to.equal(registrationAnswersInput.value);

    // Recoverable validation keeps the resumed ticket controls and pending state visible.
    dispatchHtmxBeforeRequest(checkoutForm);
    expect(checkoutButtonSpinner.classList.contains("hidden")).to.equal(false);
    expect(checkoutButtonLabel.classList.contains("invisible")).to.equal(true);
    dispatchHtmxAfterRequest(checkoutForm, {
      status: 422,
      responseText: "discount code is not available",
    });
    expect(ticketModal.classList.contains("hidden")).to.equal(false);
    expect(checkoutButtonSpinner.classList.contains("hidden")).to.equal(true);
    expect(checkoutButtonLabel.classList.contains("invisible")).to.equal(false);
  });

  it("returns to the selected ticket when registration questions are dismissed", async () => {
    const {
      attendButton,
      checker,
      checkoutForm,
      questionsModal,
      questionsModalClose,
      ticketModal,
      ticketTypeOptions,
    } = renderPaidAttendanceDom({ includeRegistrationQuestions: true });
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });
    attendButton.click();
    ticketTypeOptions[1].checked = true;
    ticketTypeOptions[1].dispatchEvent(new Event("change", { bubbles: true }));

    dispatchHtmxBeforeRequest(checkoutForm);
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(questionsModal.classList.contains("hidden")).to.equal(false);

    questionsModalClose.click();
    expect(questionsModal.classList.contains("hidden")).to.equal(true);
    expect(ticketModal.classList.contains("hidden")).to.equal(false);
    expect(ticketTypeOptions[1].checked).to.equal(true);

    dispatchHtmxBeforeRequest(checkoutForm);
    document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    expect(questionsModal.classList.contains("hidden")).to.equal(true);
    expect(ticketModal.classList.contains("hidden")).to.equal(false);
    expect(ticketTypeOptions[1].checked).to.equal(true);
  });

  it("keeps the paid button flow working when button price badges are omitted", async () => {
    // Render the paid attendance fixture.
    const { checker, attendButton, ticketModal } = renderPaidAttendanceDom({
      includeButtonPriceBadge: false,
    });
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify keeps the paid button flow working when button price badges are omitted.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Get ticket");
    expect(attendButton.querySelector(".ticket-price-badge")).to.equal(null);

    // Verify keeps the paid button flow working.
    attendButton.click();

    // Verify keeps the paid button flow working when button price badges are omitted.
    expect(ticketModal.classList.contains("hidden")).to.equal(false);
  });

  it("hides the button price badge when tickets are unavailable", async () => {
    // Render the paid attendance fixture.
    const { checker, attendButton, ticketTypeOptions, ticketCardBodies } = renderPaidAttendanceDom({
      ticketPurchaseAvailable: "false",
    });
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify hides the button price badge when tickets are unavailable.
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Paid tickets temporarily unavailable",
    );
    expect(attendButton.querySelector(".ticket-price-badge")?.hidden).to.equal(true);
    expect(attendButton.querySelector(".ticket-price-badge")?.style.display).to.equal("none");
    expect(Array.from(ticketTypeOptions).every((option) => option.disabled)).to.equal(true);
    ticketCardBodies.forEach((cardBody) => {
      expect(cardBody.classList.contains("cursor-not-allowed")).to.equal(true);
      expect(cardBody.classList.contains("hover:border-primary-300")).to.equal(false);
      expect(cardBody.classList.contains("hover:shadow-sm")).to.equal(false);
    });
  });

  it("keeps sold-out ticket types visible but disabled in the modal", async () => {
    // Keep references to the fixture controls under assertion.
    const { checker, attendButton, ticketTypeOptions, checkoutButton } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Open ticket selection for a paid event with one sold-out ticket.
    attendButton.click();

    // Verify keeps sold-out ticket types visible but disabled in the modal.
    expect(ticketTypeOptions).to.have.length(3);
    expect(ticketTypeOptions[0].disabled).to.equal(false);
    expect(ticketTypeOptions[1].disabled).to.equal(false);
    expect(ticketTypeOptions[2].disabled).to.equal(true);
    expect(checkoutButton.disabled).to.equal(true);
  });

  it("keeps active not-on-sale ticket types visible and disabled in the modal", async () => {
    // Keep references to the fixture controls under assertion.
    const { checker, attendButton, ticketTypeOptions } = renderPaidAttendanceDom({
      disabledTicketStatusLabel: "Not on sale",
    });
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify keeps active not-on-sale ticket types.
    attendButton.click();

    // Prepare disabled ticket card for keeping active not-on-sale ticket types.
    const disabledTicketCard = ticketTypeOptions[2]?.closest('[data-attendance-role="ticket-type-card"]');
    expect(ticketTypeOptions).to.have.length(3);
    expect(ticketTypeOptions[2].disabled).to.equal(true);
    expect(disabledTicketCard?.textContent).to.include("Staff");
    expect(disabledTicketCard?.textContent).to.include("Not on sale");
    expect(disabledTicketCard?.textContent).to.not.include("Sold out");
  });

  it("updates a not-on-sale ticket label when availability makes it sellable", async () => {
    // Keep references to the fixture controls under assertion.
    const { ticketCardBodies, ticketTypeOptions, ticketStatusLabels } = renderPaidAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
      disabledTicketStatusLabel: "Not on sale",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          canceled: false,
          capacity: 10,
          has_sellable_ticket_types: true,
          is_past: false,
          is_ticketed: true,
          remaining_capacity: 5,
          ticket_types: [
            {
              current_price_label: "EUR 25.00",
              event_ticket_type_id: "ticket-3",
              is_sellable_now: true,
              sold_out: false,
            },
          ],
          waitlist_enabled: false,
        }),
      },
    });

    // Verify updates a not-on-sale ticket label when availability.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Verify updates a not-on-sale ticket label when availability makes it.
      expect(ticketTypeOptions[2].disabled).to.equal(false);
      expect(ticketCardBodies[2].classList.contains("bg-white")).to.equal(true);
      expect(ticketCardBodies[2].classList.contains("cursor-pointer")).to.equal(true);
      expect(ticketCardBodies[2].classList.contains("bg-stone-50")).to.equal(false);
      expect(ticketCardBodies[2].classList.contains("cursor-not-allowed")).to.equal(false);
      expect(ticketCardBodies[2].classList.contains("opacity-60")).to.equal(false);
      expect(ticketStatusLabels()).to.deep.equal(["Available now"]);
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps an inactive approval tier disabled when opening the refreshed modal", async () => {
    // Render an approval event whose cached sold-out tier is no longer active.
    const { attendButton, checker, ticketTypeOptions } = renderPaidAttendanceDom({
      attendeeApprovalRequired: "true",
      availabilityUrl: "/events/test-event/availability",
      ticketPurchaseAvailable: "false",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: true,
          canceled: false,
          has_sellable_ticket_types: false,
          has_visible_ticket_types: true,
          is_past: false,
          is_ticketed: true,
          registration_window_open: true,
          ticket_types: [
            {
              active: true,
              current_price_label: "Free",
              event_ticket_type_id: "ticket-2",
              is_sellable_now: true,
              sold_out: false,
              title: "Community",
            },
            {
              active: false,
              current_price_label: "EUR 25.00",
              event_ticket_type_id: "ticket-3",
              is_sellable_now: false,
              sold_out: true,
              title: "Staff",
            },
          ],
          waitlist_enabled: false,
        }),
      },
    });

    try {
      await initializeAttendanceDom();
      await waitForMicrotask();
      expect(ticketTypeOptions[2].disabled).to.equal(true);

      // Opening the modal must not widen the tier's refreshed eligibility.
      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({ status: "guest" }),
      });
      attendButton.click();
      expect(ticketTypeOptions[2].disabled).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps an inactive waitlist tier disabled when opening the refreshed modal", async () => {
    // Render a waitlist event whose cached sold-out tier is no longer active.
    const { attendButton, checker, ticketTypeOptions } = renderPaidAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
      waitlistEnabled: "true",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          canceled: false,
          has_sellable_ticket_types: true,
          has_visible_ticket_types: true,
          is_past: false,
          is_ticketed: true,
          registration_window_open: true,
          ticket_types: [
            {
              active: true,
              current_price_label: "Free",
              event_ticket_type_id: "ticket-2",
              is_sellable_now: true,
              sold_out: false,
              title: "Community",
            },
            {
              active: false,
              current_price_label: "EUR 25.00",
              event_ticket_type_id: "ticket-3",
              is_sellable_now: false,
              sold_out: true,
              title: "Staff",
            },
          ],
          waitlist_enabled: true,
        }),
      },
    });

    try {
      await initializeAttendanceDom();
      await waitForMicrotask();
      expect(ticketTypeOptions[2].disabled).to.equal(true);

      // Opening the modal must not widen the tier's refreshed eligibility.
      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({ status: "guest" }),
      });
      attendButton.click();
      expect(ticketTypeOptions[2].disabled).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("hydrates a cached non-ticketed shell when a ticket becomes sellable", async () => {
    // Render the stable modal shell from a cached non-ticketed event.
    const { attendButton, checker, checkoutButton, ticketModal } = renderPaidAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
      hasVisibleTicketTypes: "false",
      includeTicketOptions: false,
      isTicketed: "false",
      ticketPurchaseAvailable: "false",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          canceled: false,
          capacity: 10,
          has_sellable_ticket_types: true,
          has_sold_out_ticket_types: false,
          has_visible_ticket_types: true,
          has_only_free_ticket_types: false,
          is_past: false,
          is_ticketed: true,
          paid_capable: true,
          registration_window_open: true,
          remaining_capacity: 5,
          ticket_types: [
            {
              active: true,
              current_price_label: "EUR 75.00",
              event_ticket_type_id: "ticket-4",
              is_sellable_now: true,
              sold_out: false,
              title: "Late release",
            },
          ],
          waitlist_enabled: false,
        }),
      },
    });

    // Verify fresh ticketing data can populate and activate the cached shell.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({ status: "guest" }),
      });
      attendButton.click();

      // Read ticket choices after refreshed availability arrives.
      const newTicketOption = document.querySelector(
        '[data-attendance-role="ticket-type-option"][value="ticket-4"]',
      );
      const newTicketCard = newTicketOption?.closest('[data-attendance-role="ticket-type-card"]');

      // Verify the new tier is available in an operable modal.
      expect(ticketModal.classList.contains("hidden")).to.equal(false);
      expect(newTicketOption).to.not.equal(null);
      expect(newTicketOption.disabled).to.equal(false);
      expect(newTicketOption.dataset.ticketPurchasable).to.equal("true");
      expect(newTicketCard?.textContent).to.include("Late release");
      expect(newTicketCard?.textContent).to.include("EUR 75.00");

      // Update the checkbox state before asserting the new state.
      newTicketOption.checked = true;
      newTicketOption.dispatchEvent(new Event("change", { bubbles: true }));

      // Verify the hydrated selection can continue to checkout.
      expect(checkoutButton.disabled).to.equal(false);
      expect(checkoutButton.hasAttribute("title")).to.equal(false);
    } finally {
      fetchMock.restore();
    }
  });

  it("removes a cached ticket type missing from refreshed availability", async () => {
    // Render the paid attendance fixture.
    const { ticketTypeOptions } = renderPaidAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    ticketTypeOptions[1].checked = true;
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          canceled: false,
          capacity: 10,
          has_sellable_ticket_types: true,
          is_past: false,
          is_ticketed: true,
          remaining_capacity: 5,
          ticket_types: [
            {
              current_price_label: "Free",
              event_ticket_type_id: "ticket-2",
              is_sellable_now: true,
              sold_out: false,
            },
          ],
          waitlist_enabled: false,
        }),
      },
    });

    // Verify removes a cached ticket type missing from refreshed availability.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Verify the stale cached option and its containing card are no longer visible.
      expect(ticketTypeOptions[1].isConnected).to.equal(false);
      expect(
        document.querySelector(
          '[data-attendance-role="ticket-type-option"][value="ticket-1"]',
        ),
      ).to.equal(null);
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps ticket price badges in the modal as plain text", async () => {
    // Render the paid attendance fixture.
    const { checker, ticketPriceBadge } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify keeps ticket price badges in the modal as plain text.
    expect(ticketPriceBadge?.textContent?.trim()).to.equal("EUR 50.00");
  });

  it("keeps modal ticket cards in visible ticket order", async () => {
    // Render the paid attendance fixture.
    const { checker, ticketTypeTitles } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify keeps modal ticket cards in visible ticket order.
    expect(ticketTypeTitles()).to.deep.equal(["Community", "General", "Staff"]);
  });

  it("omits an empty discount code from checkout params and trims a filled one", async () => {
    // Keep references to the fixture controls under assertion.
    const { checker, attendButton, ticketTypeOptions, checkoutForm, ticketModalForm } =
      renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Empty discount codes are omitted from checkout params.
    attendButton.click();
    ticketTypeOptions[0].checked = true;
    ticketTypeOptions[0].dispatchEvent(new Event("change", { bubbles: true }));

    // Read the discount field before checkout.
    const discountCodeInput = ticketModalForm.querySelector('[data-attendance-role="discount-code-input"]');
    const blankEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters: {
          discount_code: "",
          event_ticket_type_id: "ticket-1",
        },
        unfilteredParameters: {
          discount_code: "",
          event_ticket_type_id: "ticket-1",
        },
      },
    });

    // Dispatch the blank discount code through HTMX request configuration.
    checkoutForm.dispatchEvent(blankEvent);

    // Confirm blank discount codes are removed from submitted parameters.
    expect(blankEvent.detail.parameters).to.not.have.property("discount_code");
    expect(blankEvent.detail.unfilteredParameters).to.not.have.property("discount_code");

    // Update the input before asserting it omits an empty discount code from checkout.
    ticketTypeOptions[1].checked = true;
    ticketTypeOptions[1].dispatchEvent(new Event("change", { bubbles: true }));
    discountCodeInput.value = "  SPRING25  ";

    // Prepare filled event for omitting an empty discount code from checkout params.
    const filledEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters: {
          discount_code: "  SPRING25  ",
          event_ticket_type_id: "ticket-1",
        },
        unfilteredParameters: {
          discount_code: "  SPRING25  ",
          event_ticket_type_id: "ticket-1",
        },
      },
    });

    // Dispatch the filled discount code through HTMX request configuration.
    checkoutForm.dispatchEvent(filledEvent);

    // Confirm filled discount codes are trimmed before submission.
    expect(discountCodeInput.value).to.equal("SPRING25");
    expect(filledEvent.detail.parameters.discount_code).to.equal("SPRING25");
    expect(filledEvent.detail.unfilteredParameters.discount_code).to.equal("SPRING25");
  });

  it("opens and closes the refund modal with focus and keyboard support", async () => {
    const { checker, refundButton, refundModal, refundModalCancel, refundModalOverlay, refundReasonInput } =
      renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        can_request_refund: true,
        purchase_amount_minor: 5000,
        status: "attendee",
      }),
    });

    refundButton.click();
    expect(refundModal.classList.contains("hidden")).to.equal(false);
    expect(refundModal.getAttribute("aria-hidden")).to.equal("false");
    expect(document.activeElement).to.equal(refundReasonInput);
    expect(document.body.style.overflow).to.equal("hidden");

    document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    expect(refundModal.classList.contains("hidden")).to.equal(true);
    expect(document.activeElement).to.equal(refundButton);

    refundButton.click();
    refundModalOverlay.click();
    expect(refundModal.classList.contains("hidden")).to.equal(true);

    refundButton.click();
    refundModalCancel.click();
    expect(refundModal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
  });

  it("omits a blank refund reason and trims a provided reason", async () => {
    const { checker, refundButton, refundForm, refundReasonInput } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        can_request_refund: true,
        purchase_amount_minor: 5000,
        status: "attendee",
      }),
    });
    refundButton.click();

    refundReasonInput.value = "   ";
    const blankEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters: { requested_reason: "   " },
        unfilteredParameters: { requested_reason: "   " },
      },
    });
    refundForm.dispatchEvent(blankEvent);

    expect(blankEvent.detail.parameters).to.not.have.property("requested_reason");
    expect(blankEvent.detail.unfilteredParameters).to.not.have.property("requested_reason");

    refundReasonInput.value = "  Unable to attend  ";
    const filledEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters: { requested_reason: "  Unable to attend  " },
        unfilteredParameters: { requested_reason: "  Unable to attend  " },
      },
    });
    refundForm.dispatchEvent(filledEvent);

    expect(refundReasonInput.value).to.equal("Unable to attend");
    expect(filledEvent.detail.parameters.requested_reason).to.equal("Unable to attend");
    expect(filledEvent.detail.unfilteredParameters.requested_reason).to.equal("Unable to attend");
  });

  it("preserves the refund reason on failure and closes the modal on success", async () => {
    const {
      checker,
      refundButton,
      refundForm,
      refundModal,
      refundReasonInput,
      refundSubmitButton,
      refundSubmitButtonLabel,
      refundSubmitButtonSpinner,
    } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        can_request_refund: true,
        purchase_amount_minor: 5000,
        status: "attendee",
      }),
    });
    refundButton.click();
    refundReasonInput.value = "Unable to attend";

    dispatchHtmxBeforeRequest(refundForm);
    expect(refundSubmitButton.disabled).to.equal(true);
    expect(refundSubmitButtonSpinner.classList.contains("hidden")).to.equal(false);
    expect(refundSubmitButtonLabel.classList.contains("invisible")).to.equal(true);

    dispatchHtmxAfterRequest(refundForm, {
      responseText: "refund failed",
      status: 500,
    });
    expect(refundModal.classList.contains("hidden")).to.equal(false);
    expect(refundReasonInput.value).to.equal("Unable to attend");
    expect(refundSubmitButton.disabled).to.equal(false);
    expect(refundSubmitButtonSpinner.classList.contains("hidden")).to.equal(true);

    dispatchHtmxBeforeRequest(refundForm);
    dispatchHtmxAfterRequest(refundForm, {
      responseText: JSON.stringify({ status: "refund-requested" }),
    });
    expect(refundModal.classList.contains("hidden")).to.equal(true);
    expect(refundReasonInput.value).to.equal("");
    expect(env.current.swal.calls.at(-1)).to.include({
      icon: "info",
      text: "Your refund request has been sent to the organizers.",
    });
  });

  it("keeps pending-payment on the main button instead of opening the ticket modal", async () => {
    // Read controls for the pending-payment main-button flow.
    const {
      actionsMenu,
      checker,
      signinButton,
      attendButton,
      checkoutCancelButton,
      checkoutResumeButton,
      ticketModal,
    } = renderPaidAttendanceDom({
      markButtonPriceBadge: false,
    });
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        status: "pending-payment",
        resume_checkout_url: "https://example.test/checkout/resume",
      }),
    });

    // Verify keeps pending-payment on the main button instead of opening the ticket.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Continue to checkout",
    );
    expect(attendButton.dataset.resumeUrl).to.equal("https://example.test/checkout/resume");
    expect(checkoutResumeButton.classList.contains("hidden")).to.equal(true);
    expect(attendButton.querySelector(".ticket-price-badge")?.hidden).to.equal(true);
    expect(attendButton.querySelector(".ticket-price-badge")?.classList.contains("hidden")).to.equal(true);
    expect(attendButton.querySelector(".ticket-price-badge")?.style.display).to.equal("none");
    expect(signinButton.querySelector(".ticket-price-badge")?.hidden).to.equal(true);
    expect(actionsMenu.classList.contains("hidden")).to.equal(false);
    expect(checkoutCancelButton.classList.contains("hidden")).to.equal(false);
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true }).defaultPrevented).to.equal(
      true,
    );
  });

  it("keeps pending-payment available after the registration window closes", async () => {
    // Render an active pending payment after public registration has closed.
    const { checker, attendButton, checkoutCancelButton } = renderPaidAttendanceDom({
      registrationWindowOpen: "false",
      registrationWindowUnavailableTitle: "Registration closed May 1, 2099.",
    });
    await initializeAttendanceDom();

    // Dispatch the pending-payment attendance state.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        status: "pending-payment",
        resume_checkout_url: "https://example.test/checkout/resume",
      }),
    });

    // Existing active holds can still resume payment after public registration closes.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(false);
    expect(attendButton.hasAttribute("title")).to.equal(false);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Continue to checkout",
    );
    expect(attendButton.dataset.resumeUrl).to.equal("https://example.test/checkout/resume");
    expect(checkoutCancelButton.classList.contains("hidden")).to.equal(false);
  });

  it("renders pending payment when attendance status returns before availability", async () => {
    // Hold the availability response while attendance status arrives first.
    let resolveAvailability;
    const availabilityResponse = new Promise((resolve) => {
      resolveAvailability = resolve;
    });
    const fetchMock = mockFetch({
      impl: async () => availabilityResponse,
    });
    const { actionsMenu, checker, checkoutCancelButton, checkoutResumeButton, container, attendButton } =
      renderPaidAttendanceDom({
        availabilityUrl: "/events/test-event/availability",
      });

    // Restore the page state after the check.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Verify pending payment can render before availability loads.
      expect(container.dataset.availabilityHydrated).to.equal("false");

      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({
          status: "pending-payment",
          resume_checkout_url: "https://example.test/checkout/resume",
        }),
      });

      // Assert which view is visible.
      expect(checkoutResumeButton.classList.contains("hidden")).to.equal(true);

      resolveAvailability({
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          capacity: 10,
          canceled: false,
          has_sellable_ticket_types: true,
          is_live: false,
          is_past: false,
          is_ticketed: true,
          remaining_capacity: 5,
          ticket_types: [],
          waitlist_count: 0,
          waitlist_enabled: false,
        }),
      });
      await waitForMicrotask();

      // Assert that availability hydration finished.
      expect(container.dataset.availabilityHydrated).to.equal("true");
      expect(attendButton.classList.contains("hidden")).to.equal(false);
      expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
        "Continue to checkout",
      );
      expect(attendButton.dataset.resumeUrl).to.equal("https://example.test/checkout/resume");
      expect(actionsMenu.classList.contains("hidden")).to.equal(false);
      expect(checkoutResumeButton.classList.contains("hidden")).to.equal(true);
      expect(checkoutCancelButton.classList.contains("hidden")).to.equal(false);
    } finally {
      fetchMock.restore();
    }
  });

  it("closes the event actions menu when clicking outside", async () => {
    // Render the paid attendance fixture.
    const { actionsMenu, checker } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        status: "pending-payment",
        resume_checkout_url: "https://example.test/checkout/resume",
      }),
    });

    // Verify closes the event actions menu when clicking outside.
    actionsMenu.open = true;
    document.body.click();

    // Assert the actions menu state.
    expect(actionsMenu.open).to.equal(false);
  });

  it("waits for refreshed availability before rechecking after checkout cancel", async () => {
    // Render the paid attendance fixture.
    const { checkoutCancelButton, container } = renderPaidAttendanceDom();
    await initializeAttendanceDom();
    container.dataset.availabilityUrl = "/events/test-event/availability";
    let changedEvents = 0;
    let resolveAvailability;
    const availabilityResponse = new Promise((resolve) => {
      resolveAvailability = resolve;
    });
    const fetchMock = mockFetch({
      impl: async () => availabilityResponse,
    });
    document.body.addEventListener("attendance-changed", () => {
      changedEvents += 1;
    });

    // Verify waits for refreshed availability before rechecking.
    try {
      dispatchHtmxAfterRequest(checkoutCancelButton, {
        responseText: JSON.stringify({ status: "guest" }),
      });

      // Verify waits for refreshed availability before rechecking after checkout.
      expect(changedEvents).to.equal(0);

      // Verify waits for refreshed availability before rechecking.
      resolveAvailability({
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          canceled: false,
          capacity: 10,
          has_sellable_ticket_types: true,
          is_past: false,
          is_ticketed: true,
          remaining_capacity: 1,
          ticket_types: [],
          waitlist_count: 0,
          waitlist_enabled: false,
        }),
      });
      await waitForMicrotask();

      // Verify waits for refreshed availability before rechecking after checkout.
      expect(changedEvents).to.equal(1);
      expect(container.dataset.remainingCapacity).to.equal("1");
    } finally {
      fetchMock.restore();
    }
  });

  it("shows modal checkout loading, closes on success, and emits attendance changes", async () => {
    // Keep references to the fixture controls under assertion.
    const {
      checker,
      attendButton,
      ticketModal,
      ticketTypeOptions,
      checkoutForm,
      checkoutButton,
      checkoutButtonSpinner,
      checkoutButtonLabel,
    } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Prepare changed events for showing modal checkout loading, closes on success.
    let changedEvents = 0;
    document.body.addEventListener("attendance-changed", () => {
      changedEvents += 1;
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify shows modal checkout loading, closes.
    attendButton.click();
    ticketTypeOptions[0].checked = true;
    ticketTypeOptions[0].dispatchEvent(new Event("change", { bubbles: true }));

    // Dispatch the HTMX before-request event.
    dispatchHtmxBeforeRequest(checkoutForm);

    // Verify shows modal checkout loading, closes on success, and emits attendance.
    expect(checkoutButton.disabled).to.equal(true);
    expect(checkoutButtonSpinner.classList.contains("hidden")).to.equal(false);
    expect(checkoutButtonSpinner.classList.contains("flex")).to.equal(true);
    expect(checkoutButtonLabel.classList.contains("invisible")).to.equal(true);

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checkoutForm, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    // Verify shows modal checkout loading, closes on success, and emits attendance.
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have successfully registered for this event.",
      icon: "info",
    });
  });

  it("does not show a checkout alert when payment remains pending", async () => {
    // Render paid attendance controls before submitting checkout.
    const { checker, attendButton, ticketModal, ticketTypeOptions, checkoutForm } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Click the attend button.
    attendButton.click();
    ticketTypeOptions[0].checked = true;
    ticketTypeOptions[0].dispatchEvent(new Event("change", { bubbles: true }));

    dispatchHtmxAfterRequest(checkoutForm, {
      responseText: JSON.stringify({ status: "pending-payment" }),
    });

    // Assert which view is visible.
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls).to.have.length(0);
  });

  it("closes the ticket modal when checkout fails", async () => {
    // Render paid attendance controls before simulating checkout failure.
    const {
      checker,
      attendButton,
      ticketModal,
      ticketTypeOptions,
      checkoutForm,
      checkoutButtonSpinner,
      checkoutButtonLabel,
    } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Click the attend button.
    attendButton.click();
    ticketTypeOptions[0].checked = true;
    ticketTypeOptions[0].dispatchEvent(new Event("change", { bubbles: true }));

    dispatchHtmxBeforeRequest(checkoutForm);
    dispatchHtmxAfterRequest(checkoutForm, {
      status: 500,
      responseText: "checkout failed",
    });

    // Verify closes the ticket modal when checkout fails.
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(checkoutButtonSpinner.classList.contains("hidden")).to.equal(true);
    expect(checkoutButtonLabel.classList.contains("invisible")).to.equal(false);
  });

  it("reports approval request failures without checkout language", async () => {
    // Render approval ticket controls before simulating a request failure.
    const { checker, attendButton, ticketTypeOptions, checkoutForm } = renderPaidAttendanceDom({
      attendeeApprovalRequired: "true",
      ticketPurchaseAvailable: "false",
    });
    await initializeAttendanceDom();
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Submit a selected request and return an action-specific failure.
    attendButton.click();
    ticketTypeOptions[0].checked = true;
    dispatchHtmxAfterRequest(checkoutForm, { status: 500 });

    expect(env.current.swal.calls.at(-1)).to.include({
      icon: "error",
      text: "Something went wrong requesting this ticket. Please try again later.",
    });
  });

  it("reports ticket waitlist failures without checkout language", async () => {
    // Render ticket waitlist controls before simulating a join failure.
    const { checker, attendButton, ticketTypeOptions, checkoutForm } = renderPaidAttendanceDom({
      ticketPurchaseAvailable: "false",
      waitlistEnabled: "true",
    });
    await initializeAttendanceDom();
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Submit the sold-out tier and return an action-specific failure.
    attendButton.click();
    ticketTypeOptions[2].checked = true;
    dispatchHtmxAfterRequest(checkoutForm, { status: 500 });

    expect(env.current.swal.calls.at(-1)).to.include({
      icon: "error",
      text: "Something went wrong joining the ticket waiting list. Please try again later.",
    });
  });

  it("keeps the ticket modal open when checkout validation fails", async () => {
    // Render paid attendance controls before simulating validation failure.
    const {
      checker,
      attendButton,
      ticketModal,
      ticketTypeOptions,
      checkoutForm,
      checkoutButtonSpinner,
      checkoutButtonLabel,
    } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Click the attend button.
    attendButton.click();
    ticketTypeOptions[0].checked = true;
    ticketTypeOptions[0].dispatchEvent(new Event("change", { bubbles: true }));

    dispatchHtmxBeforeRequest(checkoutForm);
    dispatchHtmxAfterRequest(checkoutForm, {
      status: 422,
      responseText: "discount code is not available",
    });

    // Verify keeps the ticket modal open when checkout validation fails.
    expect(ticketModal.classList.contains("hidden")).to.equal(false);
    expect(checkoutButtonSpinner.classList.contains("hidden")).to.equal(true);
    expect(checkoutButtonLabel.classList.contains("invisible")).to.equal(false);
  });

  it("closes the ticket modal from the overlay and cancel button", async () => {
    // Keep references to the fixture controls under assertion.
    const { checker, attendButton, ticketModal, ticketModalOverlay, ticketModalCancel } =
      renderPaidAttendanceDom();
    await initializeAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Click the attend button.
    attendButton.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(false);

    // Click the ticket modal overlay.
    ticketModalOverlay.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");

    // Click the attend button.
    attendButton.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(false);

    // Click the ticket modal cancel.
    ticketModalCancel.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
  });

  it("shows a fallback message when the success return cannot be reconciled", async () => {
    // Render the paid attendance fixture.
    renderPaidAttendanceDom();
    history.replaceState({}, "", "/events/test-event?payment=success");

    // Prepare fetch mock for showing a fallback message when the success return.
    const fetchMock = mockFetch({
      impl: async () => {
        throw new Error("network error");
      },
    });

    // Verify shows a fallback message when the success return.
    try {
      await import(`/static/js/event/attendance.js?test=${Date.now()}`);
      await waitForMicrotask();

      // Verify shows a fallback message when the success return cannot be reconciled.
      expect(env.current.swal.calls.at(-1)).to.include({
        icon: "info",
        text: "Your payment was submitted. If the page still shows Continue to checkout, wait a few seconds and refresh.",
      });
      expect(window.location.search).to.equal("");
    } finally {
      fetchMock.restore();
    }
  });
});
