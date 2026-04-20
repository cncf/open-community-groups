import { expect } from "@open-wc/testing";

import "/static/js/event/attendance.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxBeforeRequest } from "/tests/unit/test-utils/htmx.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

const initializeAttendanceDom = async () => {
  document.body.dataset.attendanceListenersReady = "true";
  await import(`/static/js/event/attendance.js?test=${Date.now()}`);
};

const renderPaidAttendanceDom = ({
  starts = "2099-05-10T10:00:00Z",
  ticketPurchaseAvailable = "true",
  disabledTicketStatusLabel = "Sold out",
  includeButtonPriceBadge = true,
} = {}) => {
  document.body.innerHTML = `
    <div
      data-attendance-container
      data-starts="${starts}"
      data-is-ticketed="true"
      data-ticket-purchase-available="${ticketPurchaseAvailable}"
      data-path="/events/test-event"
      data-is-live="false"
      data-waitlist-enabled="false"
    >
      <button
        data-attendance-role="attendance-checker"
        hx-get="/test-community/event/test-event/attendance"
      ></button>
      <button data-attendance-role="loading-btn" class="hidden">
        <span data-attendance-label>Checking...</span>
      </button>
      <button data-attendance-role="signin-btn" class="hidden" data-path="/events/test-event">
        ${includeButtonPriceBadge
          ? `
        <span
          data-attendance-role="ticket-price-badge"
          data-price-label="From EUR 50.00"
          data-price-badge-style="button"
        >
          From EUR 50.00
        </span>`
          : ""}
        <span data-attendance-label>Buy ticket</span>
      </button>
      <button
        data-attendance-role="attend-btn"
        class="hidden"
        data-attend-label="Buy ticket"
        data-complete-label="Complete payment"
        data-unavailable-label="Tickets unavailable"
      >
        ${includeButtonPriceBadge
          ? `
        <span
          data-attendance-role="ticket-price-badge"
          data-price-label="From EUR 50.00"
          data-price-badge-style="button"
        >
          From EUR 50.00
        </span>`
          : ""}
        <span data-attendance-label>Buy ticket</span>
      </button>
      <div
        id="ticket-modal"
        data-attendance-role="ticket-modal"
        class="hidden"
      >
        <div data-attendance-role="ticket-modal-overlay"></div>
        <button data-attendance-role="ticket-modal-close" type="button">Close</button>
        <button data-attendance-role="ticket-modal-cancel" type="button">Cancel</button>
        <form data-attendance-role="checkout-form">
          <div data-attendance-role="ticket-modal-form">
            <div data-attendance-role="ticket-type-list">
              <label data-attendance-role="ticket-type-card">
                <input
                  data-attendance-role="ticket-type-option"
                  data-ticket-purchasable="true"
                  type="radio"
                  name="event_ticket_type_id"
                  value="ticket-1"
                />
                <span data-attendance-role="ticket-type-title">General</span>
                <div
                  data-attendance-role="ticket-price-badge"
                  data-price-label="EUR 50.00"
                >
                  EUR 50.00
                </div>
              </label>
              <label data-attendance-role="ticket-type-card">
                <input
                  data-attendance-role="ticket-type-option"
                  data-ticket-purchasable="true"
                  type="radio"
                  name="event_ticket_type_id"
                  value="ticket-2"
                />
                <span data-attendance-role="ticket-type-title">Community</span>
                <div
                  data-attendance-role="ticket-price-badge"
                  data-price-label="Free"
                >
                  Free
                </div>
              </label>
              <label data-attendance-role="ticket-type-card">
                <input
                  data-attendance-role="ticket-type-option"
                  data-ticket-purchasable="false"
                  type="radio"
                  name="event_ticket_type_id"
                  value="ticket-3"
                  disabled
                />
                <span data-attendance-role="ticket-type-title">Staff</span>
                <span>${disabledTicketStatusLabel}</span>
              </label>
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
            <span data-attendance-role="checkout-btn-label">Continue to payment</span>
          </button>
        </form>
      </div>
      <button
        data-attendance-role="leave-btn"
        class="hidden"
        data-attendee-label="Cancel attendance"
        data-waitlist-label="Leave waiting list"
      >
        <span data-attendance-label>Cancel attendance</span>
      </button>
      <button
        data-attendance-role="refund-btn"
        class="hidden"
        data-approving-label="Refund processing"
        data-rejected-label="Refund unavailable"
        data-refund-label="Request refund"
        data-pending-label="Refund requested"
      >
        <span data-attendance-label>Request refund</span>
      </button>
    </div>
  `;

  return {
    checker: document.querySelector('[data-attendance-role="attendance-checker"]'),
    signinButton: document.querySelector('[data-attendance-role="signin-btn"]'),
    attendButton: document.querySelector('[data-attendance-role="attend-btn"]'),
    ticketModal: document.querySelector('[data-attendance-role="ticket-modal"]'),
    checkoutForm: document.querySelector('[data-attendance-role="checkout-form"]'),
    ticketModalForm: document.querySelector('[data-attendance-role="ticket-modal-form"]'),
    ticketTypeOptions: document.querySelectorAll('[data-attendance-role="ticket-type-option"]'),
    ticketTypeTitles: () =>
      Array.from(document.querySelectorAll('[data-attendance-role="ticket-type-title"]')).map(
        (node) => node.textContent,
      ),
    checkoutButton: document.querySelector('[data-attendance-role="checkout-btn"]'),
    checkoutButtonSpinner: document.querySelector('[data-attendance-role="checkout-btn-spinner"]'),
    checkoutButtonLabel: document.querySelector('[data-attendance-role="checkout-btn-label"]'),
    ticketPriceBadge: document.querySelector(
      '[data-attendance-role="ticket-type-list"] [data-attendance-role="ticket-price-badge"]',
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
    const { checker, signinButton, ticketModal } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Buy ticket");

    signinButton.click();

    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
    expect(env.current.swal.calls.at(-1)).to.include({
      icon: "info",
    });
    expect(env.current.swal.calls.at(-1)?.html).to.include("buy a ticket for this event");
    expect(env.current.swal.calls.at(-1)?.html).to.include("/log-in?next_url=/events/test-event");
  });

  it("opens the paid ticket modal for guests and enables checkout after a ticket is selected", async () => {
    const { checker, attendButton, ticketModal, ticketTypeOptions, checkoutButton } =
      renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Buy ticket");
    expect(
      attendButton
        .querySelector('[data-attendance-role="ticket-price-badge"]')
        ?.textContent?.trim(),
    ).to.equal("FromEUR50.00");
    expect(
      attendButton
        .querySelector('[data-attendance-role="ticket-price-badge"] .font-semibold')
        ?.classList.contains("text-stone-800"),
    ).to.equal(true);
    expect(
      attendButton.querySelector('[data-attendance-role="ticket-price-badge"] .uppercase'),
    ).to.equal(null);

    attendButton.click();

    expect(ticketModal.classList.contains("hidden")).to.equal(false);
    expect(checkoutButton.disabled).to.equal(true);
    expect(checkoutButton.title).to.equal("Choose a ticket to continue.");

    ticketTypeOptions[0].checked = true;
    ticketTypeOptions[0].dispatchEvent(new Event("change", { bubbles: true }));

    expect(checkoutButton.disabled).to.equal(false);
    expect(checkoutButton.hasAttribute("title")).to.equal(false);
  });

  it("keeps the paid button flow working when button price badges are omitted", async () => {
    const { checker, attendButton, ticketModal } = renderPaidAttendanceDom({
      includeButtonPriceBadge: false,
    });
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Buy ticket");
    expect(attendButton.querySelector('[data-attendance-role="ticket-price-badge"]')).to.equal(null);

    attendButton.click();

    expect(ticketModal.classList.contains("hidden")).to.equal(false);
  });

  it("keeps sold-out ticket types visible but disabled in the modal", async () => {
    const { checker, attendButton, ticketTypeOptions, checkoutButton } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    attendButton.click();

    expect(ticketTypeOptions).to.have.length(3);
    expect(ticketTypeOptions[0].disabled).to.equal(false);
    expect(ticketTypeOptions[1].disabled).to.equal(false);
    expect(ticketTypeOptions[2].disabled).to.equal(true);
    expect(checkoutButton.disabled).to.equal(true);
  });

  it("keeps active not-on-sale ticket types visible and disabled in the modal", async () => {
    const { checker, attendButton, ticketTypeOptions } = renderPaidAttendanceDom({
      disabledTicketStatusLabel: "Not on sale",
    });
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    attendButton.click();

    const disabledTicketCard = ticketTypeOptions[2]?.closest('[data-attendance-role="ticket-type-card"]');
    expect(ticketTypeOptions).to.have.length(3);
    expect(ticketTypeOptions[2].disabled).to.equal(true);
    expect(disabledTicketCard?.textContent).to.include("Staff");
    expect(disabledTicketCard?.textContent).to.include("Not on sale");
    expect(disabledTicketCard?.textContent).to.not.include("Sold out");
  });

  it("renders compact ticket price badges in the modal", async () => {
    const { checker, ticketPriceBadge } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    const currencyNode = ticketPriceBadge?.querySelector(".text-xs.font-medium");
    const amountNode = ticketPriceBadge?.querySelector(".text-xs.font-semibold");
    expect(ticketPriceBadge?.textContent?.trim()).to.equal("EUR50.00");
    expect(currencyNode?.textContent).to.equal("EUR");
    expect(amountNode?.textContent).to.equal("50.00");
    expect(ticketPriceBadge?.querySelector(".text-sm")).to.equal(null);
  });

  it("keeps modal ticket cards in their original rendered order", async () => {
    const { checker, ticketTypeTitles } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    expect(ticketTypeTitles()).to.deep.equal(["General", "Community", "Staff"]);
  });

  it("omits an empty discount code from checkout params and trims a filled one", async () => {
    const { checker, attendButton, ticketTypeOptions, checkoutForm, ticketModalForm } =
      renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    attendButton.click();
    ticketTypeOptions[0].checked = true;
    ticketTypeOptions[0].dispatchEvent(new Event("change", { bubbles: true }));

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

    checkoutForm.dispatchEvent(blankEvent);

    expect(blankEvent.detail.parameters).to.not.have.property("discount_code");
    expect(blankEvent.detail.unfilteredParameters).to.not.have.property("discount_code");

    discountCodeInput.value = "  SPRING25  ";

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

    checkoutForm.dispatchEvent(filledEvent);

    expect(discountCodeInput.value).to.equal("SPRING25");
    expect(filledEvent.detail.parameters.discount_code).to.equal("SPRING25");
    expect(filledEvent.detail.unfilteredParameters.discount_code).to.equal("SPRING25");
  });

  it("keeps pending-payment on the main button instead of opening the ticket modal", async () => {
    const { checker, attendButton, ticketModal } = renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        status: "pending-payment",
        resume_checkout_url: "https://example.test/checkout/resume",
      }),
    });

    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Complete payment",
    );
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
  });

  it("shows modal checkout loading, closes on success, and emits attendance changes", async () => {
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

    let changedEvents = 0;
    document.body.addEventListener("attendance-changed", () => {
      changedEvents += 1;
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    attendButton.click();
    ticketTypeOptions[0].checked = true;
    ticketTypeOptions[0].dispatchEvent(new Event("change", { bubbles: true }));

    dispatchHtmxBeforeRequest(checkoutForm);

    expect(checkoutButton.disabled).to.equal(true);
    expect(checkoutButtonSpinner.classList.contains("hidden")).to.equal(false);
    expect(checkoutButtonSpinner.classList.contains("flex")).to.equal(true);
    expect(checkoutButtonLabel.classList.contains("invisible")).to.equal(true);

    dispatchHtmxAfterRequest(checkoutForm, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have successfully registered for this event.",
      icon: "info",
    });
  });

  it("closes the ticket modal from the overlay and cancel button", async () => {
    const { checker, attendButton, ticketModal, ticketModalOverlay, ticketModalCancel } =
      renderPaidAttendanceDom();
    await initializeAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    attendButton.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(false);

    ticketModalOverlay.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");

    attendButton.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(false);

    ticketModalCancel.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
  });

  it("shows a fallback message when the success return cannot be reconciled", async () => {
    renderPaidAttendanceDom();
    history.replaceState({}, "", "/events/test-event?payment=success");

    const fetchMock = mockFetch({
      impl: async () => {
        throw new Error("network error");
      },
    });

    try {
      await import(`/static/js/event/attendance.js?test=${Date.now()}`);
      await waitForMicrotask();

      expect(env.current.swal.calls.at(-1)).to.include({
        icon: "info",
        text: "Your payment was submitted. If the page still shows Complete payment, wait a few seconds and refresh.",
      });
      expect(window.location.search).to.equal("");
    } finally {
      fetchMock.restore();
    }
  });
});
