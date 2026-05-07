import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/attendees.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("dashboard group attendees", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/group/attendees",
    withScroll: true,
    withSwal: true,
  });

  let fetchMock;

  beforeEach(() => {
    fetchMock = mockFetch();
  });

  afterEach(() => {
    fetchMock.restore();
  });

  const initializeAttendeesUi = () => {
    dispatchHtmxLoad();
  };

  it("updates the attendee notification endpoint before opening the modal", () => {
    document.body.innerHTML = `
      <button
        id="open-attendee-notification-modal"
        type="button"
        data-event-id="event-42"
      >
        Notify attendees
      </button>
      <div id="attendee-notification-modal" class="hidden"></div>
      <button id="close-attendee-notification-modal" type="button">Close</button>
      <button id="cancel-attendee-notification" type="button">Cancel</button>
      <div id="overlay-attendee-notification-modal"></div>
      <form id="attendee-notification-form"></form>
    `;

    initializeAttendeesUi();

    const form = document.getElementById("attendee-notification-form");
    const modal = document.getElementById("attendee-notification-modal");
    document.getElementById("open-attendee-notification-modal")?.click();

    expect(form.getAttribute("hx-post")).to.equal("/dashboard/group/notifications/event-42");
    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("opens the refund review modal with attendee payment details", () => {
    const originalHtmx = window.htmx;
    const processCalls = [];
    window.htmx = {
      process: (element) => processCalls.push(element?.id),
    };

    document.body.innerHTML = `
      <button
        type="button"
        data-refund-review-trigger
        data-refund-attendee-name="Ana Lopez"
        data-refund-ticket-title="General"
        data-refund-amount="EUR 30.00"
        data-refund-status="pending"
        data-refund-approve-url="/dashboard/group/events/event-1/attendees/user-1/refund/approve"
        data-refund-reject-url="/dashboard/group/events/event-1/attendees/user-1/refund/reject"
      >
        Review
      </button>

      <div id="attendee-refund-modal" class="hidden">
        <button id="close-attendee-refund-modal" type="button">Close</button>
        <button id="cancel-attendee-refund-modal" type="button">Cancel</button>
        <div id="overlay-attendee-refund-modal"></div>
        <div id="attendee-refund-name"></div>
        <div id="attendee-refund-ticket"></div>
        <div id="attendee-refund-amount"></div>
        <button id="attendee-refund-approve" type="button" class="hidden"></button>
        <button id="attendee-refund-reject" type="button" class="hidden"></button>
      </div>
    `;

    initializeAttendeesUi();

    const modal = document.getElementById("attendee-refund-modal");
    const approveButton = document.getElementById("attendee-refund-approve");
    const rejectButton = document.getElementById("attendee-refund-reject");

    document.querySelector("[data-refund-review-trigger]")?.click();

    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("attendee-refund-name")?.textContent).to.equal("Ana Lopez");
    expect(document.getElementById("attendee-refund-ticket")?.textContent).to.equal("General");
    expect(document.getElementById("attendee-refund-amount")?.textContent).to.equal("EUR 30.00");
    expect(approveButton.classList.contains("hidden")).to.equal(false);
    expect(approveButton.getAttribute("hx-put")).to.equal(
      "/dashboard/group/events/event-1/attendees/user-1/refund/approve",
    );
    expect(rejectButton.classList.contains("hidden")).to.equal(false);
    expect(rejectButton.getAttribute("hx-put")).to.equal(
      "/dashboard/group/events/event-1/attendees/user-1/refund/reject",
    );
    expect(processCalls).to.deep.equal([
      "attendee-refund-approve",
      "attendee-refund-reject",
    ]);

    window.htmx = originalHtmx;
  });

  it("shows only the retry action for refund processing entries", () => {
    document.body.innerHTML = `
      <button
        type="button"
        data-refund-review-trigger
        data-refund-attendee-name="Ana Lopez"
        data-refund-ticket-title="General"
        data-refund-amount="EUR 30.00"
        data-refund-status="approving"
        data-refund-approve-url="/dashboard/group/events/event-1/attendees/user-1/refund/approve"
      >
        Review
      </button>

      <div id="attendee-refund-modal" class="hidden">
        <button id="close-attendee-refund-modal" type="button">Close</button>
        <button id="cancel-attendee-refund-modal" type="button">Cancel</button>
        <div id="overlay-attendee-refund-modal"></div>
        <div id="attendee-refund-name"></div>
        <div id="attendee-refund-ticket"></div>
        <div id="attendee-refund-amount"></div>
        <button id="attendee-refund-approve" type="button" class="hidden"></button>
        <button id="attendee-refund-reject" type="button" class="hidden"></button>
      </div>
    `;

    initializeAttendeesUi();

    const approveButton = document.getElementById("attendee-refund-approve");
    const rejectButton = document.getElementById("attendee-refund-reject");

    document.querySelector("[data-refund-review-trigger]")?.click();

    expect(approveButton.classList.contains("hidden")).to.equal(false);
    expect(approveButton.textContent).to.equal("Retry refund finalization");
    expect(rejectButton.classList.contains("hidden")).to.equal(true);
  });

  it("closes the refund review modal after a successful approve request", () => {
    document.body.innerHTML = `
      <button
        type="button"
        data-refund-review-trigger
        data-refund-attendee-name="Ana Lopez"
        data-refund-ticket-title="General"
        data-refund-amount="EUR 30.00"
        data-refund-status="pending"
        data-refund-approve-url="/dashboard/group/events/event-1/attendees/user-1/refund/approve"
        data-refund-reject-url="/dashboard/group/events/event-1/attendees/user-1/refund/reject"
      >
        Review
      </button>

      <div id="attendee-refund-modal" class="hidden">
        <button id="close-attendee-refund-modal" type="button">Close</button>
        <button id="cancel-attendee-refund-modal" type="button">Cancel</button>
        <div id="overlay-attendee-refund-modal"></div>
        <div id="attendee-refund-name"></div>
        <div id="attendee-refund-ticket"></div>
        <div id="attendee-refund-amount"></div>
        <button id="attendee-refund-approve" type="button" class="hidden"></button>
        <button id="attendee-refund-reject" type="button" class="hidden"></button>
      </div>
    `;

    initializeAttendeesUi();

    const modal = document.getElementById("attendee-refund-modal");
    const approveButton = document.getElementById("attendee-refund-approve");

    document.querySelector("[data-refund-review-trigger]")?.click();
    expect(modal.classList.contains("hidden")).to.equal(false);

    approveButton?.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 200,
          },
        },
      }),
    );

    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("keeps the refund review modal open after a failed reject request", () => {
    document.body.innerHTML = `
      <button
        type="button"
        data-refund-review-trigger
        data-refund-attendee-name="Ana Lopez"
        data-refund-ticket-title="General"
        data-refund-amount="EUR 30.00"
        data-refund-status="pending"
        data-refund-approve-url="/dashboard/group/events/event-1/attendees/user-1/refund/approve"
        data-refund-reject-url="/dashboard/group/events/event-1/attendees/user-1/refund/reject"
      >
        Review
      </button>

      <div id="attendee-refund-modal" class="hidden">
        <button id="close-attendee-refund-modal" type="button">Close</button>
        <button id="cancel-attendee-refund-modal" type="button">Cancel</button>
        <div id="overlay-attendee-refund-modal"></div>
        <div id="attendee-refund-name"></div>
        <div id="attendee-refund-ticket"></div>
        <div id="attendee-refund-amount"></div>
        <button id="attendee-refund-approve" type="button" class="hidden"></button>
        <button id="attendee-refund-reject" type="button" class="hidden"></button>
      </div>
    `;

    initializeAttendeesUi();

    const modal = document.getElementById("attendee-refund-modal");
    const rejectButton = document.getElementById("attendee-refund-reject");

    document.querySelector("[data-refund-review-trigger]")?.click();
    expect(modal.classList.contains("hidden")).to.equal(false);

    rejectButton?.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 500,
          },
        },
      }),
    );

    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("opens refund review for newly swapped attendee content after HTMX load", () => {
    document.body.innerHTML = `
      <button
        type="button"
        data-refund-review-trigger
        data-refund-attendee-name="Initial Attendee"
        data-refund-ticket-title="Initial Ticket"
        data-refund-amount="EUR 10.00"
        data-refund-status="pending"
        data-refund-approve-url="/dashboard/group/events/event-1/attendees/user-1/refund/approve"
        data-refund-reject-url="/dashboard/group/events/event-1/attendees/user-1/refund/reject"
      >
        Review
      </button>

      <div id="attendee-refund-modal" class="hidden">
        <button id="close-attendee-refund-modal" type="button">Close</button>
        <button id="cancel-attendee-refund-modal" type="button">Cancel</button>
        <div id="overlay-attendee-refund-modal"></div>
        <div id="attendee-refund-name"></div>
        <div id="attendee-refund-ticket"></div>
        <div id="attendee-refund-amount"></div>
        <button id="attendee-refund-approve" type="button" class="hidden"></button>
        <button id="attendee-refund-reject" type="button" class="hidden"></button>
      </div>
    `;

    initializeAttendeesUi();

    document.body.innerHTML = `
      <button
        type="button"
        data-refund-review-trigger
        data-refund-attendee-name="Swapped Attendee"
        data-refund-ticket-title="Swapped Ticket"
        data-refund-amount="EUR 25.00"
        data-refund-status="pending"
        data-refund-approve-url="/dashboard/group/events/event-2/attendees/user-2/refund/approve"
        data-refund-reject-url="/dashboard/group/events/event-2/attendees/user-2/refund/reject"
      >
        Review
      </button>

      <div id="attendee-refund-modal" class="hidden">
        <button id="close-attendee-refund-modal" type="button">Close</button>
        <button id="cancel-attendee-refund-modal" type="button">Cancel</button>
        <div id="overlay-attendee-refund-modal"></div>
        <div id="attendee-refund-name"></div>
        <div id="attendee-refund-ticket"></div>
        <div id="attendee-refund-amount"></div>
        <button id="attendee-refund-approve" type="button" class="hidden"></button>
        <button id="attendee-refund-reject" type="button" class="hidden"></button>
      </div>
    `;

    initializeAttendeesUi();

    const modal = document.getElementById("attendee-refund-modal");
    const approveButton = document.getElementById("attendee-refund-approve");
    const rejectButton = document.getElementById("attendee-refund-reject");

    document.querySelector("[data-refund-review-trigger]")?.click();

    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("attendee-refund-name")?.textContent).to.equal(
      "Swapped Attendee",
    );
    expect(document.getElementById("attendee-refund-ticket")?.textContent).to.equal(
      "Swapped Ticket",
    );
    expect(document.getElementById("attendee-refund-amount")?.textContent).to.equal("EUR 25.00");
    expect(approveButton.getAttribute("hx-put")).to.equal(
      "/dashboard/group/events/event-2/attendees/user-2/refund/approve",
    );
    expect(rejectButton.getAttribute("hx-put")).to.equal(
      "/dashboard/group/events/event-2/attendees/user-2/refund/reject",
    );
  });

  it("keeps the check-in toggle disabled after a successful check-in", async () => {
    document.body.innerHTML = `
      <label class="cursor-pointer">
        <input
          type="checkbox"
          class="check-in-toggle"
          data-url="/dashboard/group/attendees/check-in/7"
        />
      </label>
    `;

    initializeAttendeesUi();

    const checkbox = document.querySelector(".check-in-toggle");
    const label = checkbox.closest("label");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    expect(fetchMock.calls).to.have.length(1);
    const [url, options] = fetchMock.calls[0];
    expect(url).to.equal("/dashboard/group/attendees/check-in/7");
    expect(options.credentials).to.equal("same-origin");
    expect(options.headers.get("X-OCG-Fetch")).to.equal("true");
    expect(options.method).to.equal("POST");
    expect(checkbox.disabled).to.equal(true);
    expect(label.classList.contains("cursor-not-allowed")).to.equal(true);
    expect(label.classList.contains("cursor-pointer")).to.equal(false);
    expect(env.current.swal.calls).to.have.length(0);
  });

  it("reverts the check-in toggle and shows an error when the request fails", async () => {
    fetchMock.setImpl(async () => ({ ok: false, status: 500 }));

    document.body.innerHTML = `
      <label class="cursor-pointer">
        <input
          type="checkbox"
          class="check-in-toggle"
          data-url="/dashboard/group/attendees/check-in/8"
        />
      </label>
    `;

    initializeAttendeesUi();

    const checkbox = document.querySelector(".check-in-toggle");
    const label = checkbox.closest("label");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    expect(checkbox.checked).to.equal(false);
    expect(checkbox.disabled).to.equal(false);
    expect(label.classList.contains("cursor-pointer")).to.equal(true);
    expect(label.classList.contains("cursor-not-allowed")).to.equal(false);
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      text: "Failed to check in attendee. Please try again.",
      icon: "error",
    });
  });

  it("does not duplicate refund modal handling when the same attendees root reloads", () => {
    const originalHtmx = window.htmx;
    const processCalls = [];
    window.htmx = {
      process: (element) => processCalls.push(element?.id),
    };

    document.body.innerHTML = `
      <div id="attendees-content">
        <button
          type="button"
          data-refund-review-trigger
          data-refund-attendee-name="Ana Lopez"
          data-refund-ticket-title="General"
          data-refund-amount="EUR 30.00"
          data-refund-status="pending"
          data-refund-approve-url="/dashboard/group/events/event-1/attendees/user-1/refund/approve"
          data-refund-reject-url="/dashboard/group/events/event-1/attendees/user-1/refund/reject"
        >
          Review
        </button>

        <div id="attendee-refund-modal" class="hidden">
          <button id="close-attendee-refund-modal" type="button">Close</button>
          <button id="cancel-attendee-refund-modal" type="button">Cancel</button>
          <div id="overlay-attendee-refund-modal"></div>
          <div id="attendee-refund-name"></div>
          <div id="attendee-refund-ticket"></div>
          <div id="attendee-refund-amount"></div>
        <button id="attendee-refund-approve" type="button" class="hidden"></button>
        <button id="attendee-refund-reject" type="button" class="hidden"></button>
        </div>
      </div>
    `;

    const attendeesRoot = document.getElementById("attendees-content");
    dispatchHtmxLoad(attendeesRoot);
    dispatchHtmxLoad(attendeesRoot);

    document.querySelector("[data-refund-review-trigger]")?.click();

    expect(processCalls).to.deep.equal([
      "attendee-refund-approve",
      "attendee-refund-reject",
    ]);

    window.htmx = originalHtmx;
  });
});
