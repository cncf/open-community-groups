import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/attendees.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
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

  const attendeeInvitationMarkup = () => `
    <button id="open-attendee-invitation-modal" type="button">Invite</button>
    <div id="attendee-invitation-modal" class="hidden">
      <button id="close-attendee-invitation-modal" type="button">Close</button>
      <button id="cancel-attendee-invitation" type="button">Cancel</button>
      <div id="overlay-attendee-invitation-modal"></div>
      <form id="attendee-invitation-form">
        <label for="attendee-invitation-search-input">Search by name, username, or email</label>
        <user-search-field
          input-id="attendee-invitation-search-input"
          email-action-enabled
          email-action-text="Invite by email"
          persist-query-on-outside
          data-attendee-invitation-search
        ></user-search-field>
        <input type="hidden" name="user_id" id="attendee-invitation-user-id" disabled />
        <input type="hidden" name="email" id="attendee-invitation-email" disabled />
        <div id="attendee-invitation-selected-user"></div>
        <button id="submit-attendee-invitation" type="submit" disabled>Send invitation</button>
      </form>
    </div>
  `;

  it("toggles and closes the attendee actions menu", () => {
    document.body.innerHTML = `
      <div id="attendees-content">
        <button id="attendee-actions-button" type="button">
          More
        </button>
        <div id="attendee-actions-menu" data-attendee-actions-dropdown class="hidden">
          <a href="/dashboard/group/events/event-42/attendees.csv" download>Download CSV</a>
        </div>
      </div>
    `;

    initializeAttendeesUi();

    const button = document.getElementById("attendee-actions-button");
    const dropdown = document.getElementById("attendee-actions-menu");

    button.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    dropdown.querySelector("a")?.click();
    expect(dropdown.classList.contains("hidden")).to.equal(true);

    button.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    document.body.click();
    expect(dropdown.classList.contains("hidden")).to.equal(true);
  });

  it("toggles attendee row action menus for pending invitations", () => {
    document.body.innerHTML = `
      <div id="attendees-content">
        <details data-attendee-row-actions-menu>
          <summary>
            More
          </summary>
          <div>
            <button
              id="cancel-invitation-user-1"
              type="button"
              hx-put="/dashboard/group/events/event-42/attendees/user-1/invitation/cancel"
              data-confirm-action
            >
              Cancel invitation
            </button>
          </div>
        </details>
      </div>
    `;

    initializeAttendeesUi();

    const menu = document.querySelector("[data-attendee-row-actions-menu]");
    const trigger = menu.querySelector("summary");
    const cancelButton = document.getElementById("cancel-invitation-user-1");

    trigger.click();
    expect(menu.open).to.equal(true);
    expect(cancelButton.getAttribute("hx-put")).to.equal(
      "/dashboard/group/events/event-42/attendees/user-1/invitation/cancel",
    );

    cancelButton.click();
    expect(menu.open).to.equal(false);

    trigger.click();
    expect(menu.open).to.equal(true);

    document.body.click();
    expect(menu.open).to.equal(false);
  });

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

  it("opens the attendee notification modal after the dashboard body is swapped", () => {
    const replacementBody = document.createElement("body");
    replacementBody.innerHTML = `
      <button
        id="open-attendee-notification-modal"
        type="button"
        data-event-id="event-99"
      >
        Notify attendees
      </button>
      <div id="attendee-notification-modal" class="hidden"></div>
      <button id="close-attendee-notification-modal" type="button">Close</button>
      <button id="cancel-attendee-notification" type="button">Cancel</button>
      <div id="overlay-attendee-notification-modal"></div>
      <form id="attendee-notification-form"></form>
    `;
    document.documentElement.replaceChild(replacementBody, document.body);

    initializeAttendeesUi();
    document.getElementById("open-attendee-notification-modal")?.click();

    expect(document.getElementById("attendee-notification-form")?.getAttribute("hx-post")).to.equal(
      "/dashboard/group/notifications/event-99",
    );
    expect(document.getElementById("attendee-notification-modal")?.classList.contains("hidden")).to.equal(
      false,
    );
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
    expect(processCalls).to.deep.equal(["attendee-refund-approve", "attendee-refund-reject"]);

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
    expect(document.getElementById("attendee-refund-name")?.textContent).to.equal("Swapped Attendee");
    expect(document.getElementById("attendee-refund-ticket")?.textContent).to.equal("Swapped Ticket");
    expect(document.getElementById("attendee-refund-amount")?.textContent).to.equal("EUR 25.00");
    expect(approveButton.getAttribute("hx-put")).to.equal(
      "/dashboard/group/events/event-2/attendees/user-2/refund/approve",
    );
    expect(rejectButton.getAttribute("hx-put")).to.equal(
      "/dashboard/group/events/event-2/attendees/user-2/refund/reject",
    );
  });

  it("handles invitation modal controls after attendee content refreshes", () => {
    document.body.innerHTML = `
      <div id="attendees-content">
        ${attendeeInvitationMarkup()}
      </div>
    `;

    const attendeesRoot = document.getElementById("attendees-content");
    dispatchHtmxLoad(attendeesRoot);

    document.getElementById("open-attendee-invitation-modal")?.click();

    const initialSubmit = document.getElementById("submit-attendee-invitation");
    const initialSearchField = document.querySelector("[data-attendee-invitation-search]");
    const initialEmailInput = document.getElementById("attendee-invitation-email");
    initialSearchField.dispatchEvent(
      new CustomEvent("user-search-query-changed", {
        bubbles: true,
        detail: { query: "first" },
      }),
    );
    expect(initialSubmit.disabled).to.equal(true);

    initialSearchField.dispatchEvent(
      new CustomEvent("user-search-query-changed", {
        bubbles: true,
        detail: { query: "first@example.com" },
      }),
    );
    expect(initialEmailInput.value).to.equal("first@example.com");
    expect(initialSubmit.disabled).to.equal(false);

    attendeesRoot.innerHTML = attendeeInvitationMarkup();
    dispatchHtmxLoad(attendeesRoot);

    document.getElementById("open-attendee-invitation-modal")?.click();

    const refreshedModal = document.getElementById("attendee-invitation-modal");
    const refreshedSubmit = document.getElementById("submit-attendee-invitation");
    const refreshedSearchField = document.querySelector("[data-attendee-invitation-search]");
    const refreshedEmailInput = document.getElementById("attendee-invitation-email");
    refreshedSearchField.dispatchEvent(
      new CustomEvent("user-search-query-changed", {
        bubbles: true,
        detail: { query: "second@example.com" },
      }),
    );

    expect(refreshedEmailInput.value).to.equal("second@example.com");
    expect(refreshedSubmit.disabled).to.equal(false);

    dispatchHtmxAfterRequest(document.getElementById("attendee-invitation-form"), { status: 201 });

    expect(env.current.swal.calls[0]).to.include({
      text: "Invitation sent.",
      icon: "success",
    });
    expect(refreshedModal.classList.contains("hidden")).to.equal(true);
  });

  it("enables attendee invitation for a typed email when no user matches", async () => {
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [];
      },
    }));

    document.body.innerHTML = `
      <div id="attendees-content">
        ${attendeeInvitationMarkup()}
      </div>
    `;

    const attendeesRoot = document.getElementById("attendees-content");
    dispatchHtmxLoad(attendeesRoot);

    document.getElementById("open-attendee-invitation-modal")?.click();

    const searchField = document.querySelector("[data-attendee-invitation-search]");
    await searchField.updateComplete;
    searchField.searchDelay = 0;

    const searchInput = searchField.querySelector("[data-user-search-input]");
    const userInput = document.getElementById("attendee-invitation-user-id");
    const emailInput = document.getElementById("attendee-invitation-email");
    const submitButton = document.getElementById("submit-attendee-invitation");

    searchInput.value = "invitee+test3@example.com";
    searchInput.dispatchEvent(new Event("input", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    await searchField.updateComplete;

    expect(emailInput.value).to.equal("invitee+test3@example.com");
    expect(userInput.disabled).to.equal(true);
    expect(emailInput.disabled).to.equal(false);
    expect(searchField.textContent).to.contain("invitee+test3@example.com");
    expect(searchField.textContent).to.contain("Invite by email");
    expect(searchField.textContent).not.to.contain("No users found");
    expect(submitButton.disabled).to.equal(false);

    searchField.querySelector("button[aria-label='Invite by email invitee+test3@example.com']")?.click();
    await waitForMicrotask();

    const selectedUser = document.getElementById("attendee-invitation-selected-user");

    expect(emailInput.value).to.equal("invitee+test3@example.com");
    expect(userInput.disabled).to.equal(true);
    expect(emailInput.disabled).to.equal(false);
    expect(new FormData(document.getElementById("attendee-invitation-form")).has("user_id")).to.equal(false);
    expect(new FormData(document.getElementById("attendee-invitation-form")).get("email")).to.equal(
      "invitee+test3@example.com",
    );
    expect(searchField.textContent).not.to.contain("Invite by email");
    expect(selectedUser.textContent).to.contain("invitee+test3@example.com");
    expect(selectedUser.querySelector(".icon-email")).to.exist;
    expect(selectedUser.querySelector(".size-\\[24px\\].rounded-full .icon-email")).to.exist;
    expect(submitButton.disabled).to.equal(false);
  });

  it("renders selected invitation users with the shared user pill style", () => {
    document.body.innerHTML = `
      <div id="attendees-content">
        ${attendeeInvitationMarkup()}
      </div>
    `;

    const attendeesRoot = document.getElementById("attendees-content");
    dispatchHtmxLoad(attendeesRoot);

    attendeesRoot.dispatchEvent(
      new CustomEvent("user-selected", {
        bubbles: true,
        detail: {
          user: {
            user_id: "user-1",
            username: "e2e-admin-one",
            name: "E2E Admin One",
            photo_url: "/static/images/e2e/admin.png",
          },
        },
      }),
    );

    const selectedUser = document.getElementById("attendee-invitation-selected-user");
    const userInput = document.getElementById("attendee-invitation-user-id");
    const emailInput = document.getElementById("attendee-invitation-email");
    const submitButton = document.getElementById("submit-attendee-invitation");
    const pill = selectedUser.querySelector(".inline-flex.rounded-full");

    expect(userInput.value).to.equal("user-1");
    expect(userInput.disabled).to.equal(false);
    expect(emailInput.disabled).to.equal(true);
    expect(new FormData(document.getElementById("attendee-invitation-form")).get("user_id")).to.equal(
      "user-1",
    );
    expect(new FormData(document.getElementById("attendee-invitation-form")).has("email")).to.equal(false);
    expect(pill).to.exist;
    expect(selectedUser.textContent).to.contain("E2E Admin One");
    expect(selectedUser.textContent).not.to.contain("Selected:");
    expect(pill.querySelector("logo-image")).to.exist;
    expect(pill.querySelector("[data-attendee-invitation-clear-user]")).to.exist;
    expect(submitButton.disabled).to.equal(false);

    pill.querySelector("[data-attendee-invitation-clear-user]")?.click();

    expect(userInput.value).to.equal("");
    expect(userInput.disabled).to.equal(true);
    expect(emailInput.disabled).to.equal(true);
    expect(selectedUser.children).to.have.length(0);
    expect(submitButton.disabled).to.equal(true);
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

    expect(processCalls).to.deep.equal(["attendee-refund-approve", "attendee-refund-reject"]);

    window.htmx = originalHtmx;
  });
});
