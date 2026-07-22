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

  // Initialize attendees ui for the test.
  const initializeAttendeesUi = () => {
    dispatchHtmxLoad();
  };

  const attendeeRefundRejectMarkup = () => `
    <div id="attendees-content">
      <details data-actions-menu open>
        <summary>Attendee actions</summary>
        <button
          type="button"
          data-attendee-refund-reject-open
          data-refund-reject-url="/dashboard/group/refunds/purchase-1/reject"
          data-refund-attendee-name="Ana Lopez"
          data-refund-event-name="Community meetup"
        >
          Reject refund
        </button>
      </details>
      <div id="attendee-refund-reject-modal" class="hidden" aria-hidden="true">
        <button id="close-attendee-refund-reject-modal" type="button">Close</button>
        <div id="overlay-attendee-refund-reject-modal"></div>
        <form id="attendee-refund-reject-form">
          <div id="attendee-refund-reject-name"></div>
          <div id="attendee-refund-reject-event"></div>
          <textarea id="attendee-refund-review-note" name="review_note" autofocus></textarea>
          <button id="cancel-attendee-refund-reject-modal" type="button">Cancel</button>
          <button type="submit">Reject refund</button>
        </form>
      </div>
    </div>
  `;

  const attendeeRefundApproveMarkup = () => `
    <div id="attendees-content">
      <details data-actions-menu open>
        <summary>Attendee actions</summary>
        <button
          type="button"
          data-attendee-refund-approve-open
          data-refund-approve-url="/dashboard/group/refunds/purchase-1/approve"
          data-refund-attendee-name="Ana Lopez"
          data-refund-event-name="Community meetup"
        >
          Approve refund
        </button>
      </details>
      <div id="attendee-refund-approve-modal" class="hidden" aria-hidden="true">
        <button id="close-attendee-refund-approve-modal" type="button">Close</button>
        <div id="overlay-attendee-refund-approve-modal"></div>
        <form id="attendee-refund-approve-form">
          <div id="attendee-refund-approve-name"></div>
          <div id="attendee-refund-approve-event"></div>
          <textarea
            id="attendee-refund-approve-review-note"
            name="review_note"
            autofocus
          ></textarea>
          <button id="cancel-attendee-refund-approve-modal" type="button">Cancel</button>
          <button type="submit">Approve refund</button>
        </form>
      </div>
    </div>
  `;

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

  const attendeeNotificationMarkup = (triggerMarkup) => `
    <div id="attendees-content">
      ${triggerMarkup}
      <div id="attendee-notification-modal" class="hidden"></div>
      <button id="close-attendee-notification-modal" type="button">Close</button>
      <button id="cancel-attendee-notification" type="button">Cancel</button>
      <div id="overlay-attendee-notification-modal"></div>
      <form id="attendee-notification-form">
        <p id="attendee-notification-recipient-summary" data-all-recipient-total="3"></p>
        <input id="attendee-notification-recipient-scope" type="hidden" name="recipient_scope" value="all" />
        <div id="attendee-notification-selected-fields"></div>
        <button id="submit-attendee-notification" type="submit">Send email</button>
      </form>
    </div>
  `;

  const attendeeSelectionMarkup = ({ eventId = "event-42", recipients = [] } = {}) => `
    <div id="attendees-content">
      <button id="attendee-email-actions-button" type="button">Send email</button>
      <div id="attendee-email-actions-menu" data-attendee-email-actions-dropdown class="hidden">
        <button type="button" data-attendee-email-selection-start data-event-id="${eventId}">
          Choose attendees
        </button>
      </div>
      <div data-attendee-email-selection-bar class="hidden">
        <span data-attendee-email-selection-count>0</span>
        <span data-attendee-email-selection-label>attendees selected</span>
        <button type="button" data-attendee-email-selection-clear>Clear</button>
        <button type="button" data-attendee-email-selection-cancel>Cancel</button>
        <button type="button" data-attendee-email-selection-send disabled>Continue</button>
      </div>
      <table>
        <thead>
          <tr>
            <th data-attendee-email-selection-column class="hidden">Select</th>
          </tr>
        </thead>
        <tbody>
          ${recipients
            .map(
              (recipient) => `
                <tr>
                  <td data-attendee-email-selection-column class="hidden">
                    <input
                      type="checkbox"
                      data-attendee-email-selection-checkbox
                      data-recipient-id="${recipient.id}"
                      data-recipient-name="${recipient.name}"
                      data-recipient-username="${recipient.username}"
                      data-recipient-email="${recipient.email}"
                      value="${recipient.id}"
                    />
                  </td>
                </tr>
              `,
            )
            .join("")}
        </tbody>
      </table>
      <div id="attendee-notification-modal" class="hidden"></div>
      <button id="close-attendee-notification-modal" type="button">Close</button>
      <button id="cancel-attendee-notification" type="button">Cancel</button>
      <div id="overlay-attendee-notification-modal"></div>
      <form id="attendee-notification-form">
        <p id="attendee-notification-recipient-summary" data-all-recipient-total="3"></p>
        <input id="attendee-notification-recipient-scope" type="hidden" name="recipient_scope" value="all" />
        <div id="attendee-notification-selected-fields"></div>
        <button id="submit-attendee-notification" type="submit">Send email</button>
      </form>
    </div>
  `;

  const attendeeSelectionInnerMarkup = (options = {}) => {
    const template = document.createElement("template");
    template.innerHTML = attendeeSelectionMarkup(options).trim();
    return template.content.firstElementChild?.innerHTML || "";
  };

  it("toggles and closes the attendee actions menu", () => {
    // Render the DOM fixture for toggling and closes the attendee actions menu.
    document.body.innerHTML = `
      <div id="attendees-content">
        <button id="attendee-actions-button" type="button">
          More
        </button>
        <div id="attendee-actions-menu" data-attendee-actions-dropdown class="hidden">
          <button type="button">Show check-in QR code</button>
          <a href="/dashboard/group/events/event-42/attendees.csv" download>Download CSV</a>
        </div>
      </div>
    `;

    // Verify toggles and closes the attendee actions menu.
    initializeAttendeesUi();

    // Keep a reference to the attendee actions button element.
    const button = document.getElementById("attendee-actions-button");
    const dropdown = document.getElementById("attendee-actions-menu");

    // Click the control.
    button.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    // Click the dropdown.
    dropdown.querySelector("a")?.click();
    expect(dropdown.classList.contains("hidden")).to.equal(true);

    // Click the next control.
    button.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    // Click a dropdown button.
    dropdown.querySelector("button")?.click();
    expect(dropdown.classList.contains("hidden")).to.equal(true);

    // Click the next control.
    button.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    // Click the body.
    document.body.click();
    expect(dropdown.classList.contains("hidden")).to.equal(true);
  });

  it("binds attendee outside click cleanup once across swapped roots", () => {
    // Track document click listener bindings while attendees roots are swapped.
    const originalAddEventListener = document.addEventListener;
    let documentClickListeners = 0;
    document.addEventListener = function (type, listener, options) {
      if (type === "click") {
        documentClickListeners += 1;
      }

      return originalAddEventListener.call(this, type, listener, options);
    };
    delete document.documentElement.dataset.attendeeOutsideClickReady;

    try {
      // Initialize the first attendee root.
      document.body.innerHTML = `
        <div id="attendees-content">
          <button id="attendee-actions-button" type="button">More</button>
          <div id="attendee-actions-menu" data-attendee-actions-dropdown class="hidden"></div>
        </div>
      `;
      dispatchHtmxLoad(document.getElementById("attendees-content"));

      // Swap in a new attendee root and initialize again.
      document.body.innerHTML = `
        <div id="attendees-content">
          <button id="attendee-actions-button" type="button">More</button>
          <div id="attendee-actions-menu" data-attendee-actions-dropdown class="hidden"></div>
        </div>
      `;
      dispatchHtmxLoad(document.getElementById("attendees-content"));

      // Only one document listener owns outside-click cleanup for attendees.
      expect(documentClickListeners).to.equal(1);
    } finally {
      document.addEventListener = originalAddEventListener;
    }
  });

  it("toggles attendee row action menus for pending invitations", () => {
    // Render an attendees row with pending invitation actions.
    document.body.innerHTML = `
      <div id="attendees-content">
        <details data-actions-menu>
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

    // Set up menu.
    const menu = document.querySelector("[data-actions-menu]");
    const trigger = menu.querySelector("summary");
    const cancelButton = document.getElementById("cancel-invitation-user-1");

    // Click the trigger.
    trigger.click();

    // Verify toggles attendee row action menus for pending invitations.
    expect(menu.open).to.equal(true);
    expect(cancelButton.getAttribute("hx-put")).to.equal(
      "/dashboard/group/events/event-42/attendees/user-1/invitation/cancel",
    );

    // Click the cancel button.
    cancelButton.click();
    expect(menu.open).to.equal(false);

    // Click the trigger.
    trigger.click();
    expect(menu.open).to.equal(true);

    // Click outside the open menu.
    document.body.click();
    expect(menu.open).to.equal(false);
  });

  it("updates the attendee notification endpoint before opening the modal", () => {
    // Render the DOM fixture for updating the attendee notification endpoint.
    document.body.innerHTML = `
      <div id="attendees-content">
        <button
          id="open-attendee-notification-modal"
          type="button"
          data-attendee-notification-open
          data-event-id="event-42"
          data-notification-scope="all"
        >
          Notify attendees
        </button>
        <div id="attendee-notification-modal" class="hidden"></div>
        <button id="close-attendee-notification-modal" type="button">Close</button>
        <button id="cancel-attendee-notification" type="button">Cancel</button>
        <div id="overlay-attendee-notification-modal"></div>
        <form id="attendee-notification-form"></form>
      </div>
    `;

    // Verify updates the attendee notification endpoint.
    initializeAttendeesUi();

    // Read the notification form that receives the attendee endpoint.
    const form = document.getElementById("attendee-notification-form");
    const modal = document.getElementById("attendee-notification-modal");
    document.getElementById("open-attendee-notification-modal")?.click();

    // Verify updates the attendee notification endpoint before opening the modal.
    expect(form.getAttribute("hx-post")).to.equal("/dashboard/group/notifications/event-42");
    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("opens the attendee notification modal after the dashboard body is swapped", () => {
    // Prepare replacement body for opening the attendee notification modal.
    const replacementBody = document.createElement("body");
    replacementBody.innerHTML = `
      <div id="attendees-content">
        <button
          id="open-attendee-notification-modal"
          type="button"
          data-attendee-notification-open
          data-event-id="event-99"
          data-notification-scope="all"
        >
          Notify attendees
        </button>
        <div id="attendee-notification-modal" class="hidden"></div>
        <button id="close-attendee-notification-modal" type="button">Close</button>
        <button id="cancel-attendee-notification" type="button">Cancel</button>
        <div id="overlay-attendee-notification-modal"></div>
        <form id="attendee-notification-form"></form>
      </div>
    `;
    document.documentElement.replaceChild(replacementBody, document.body);

    // Verify opens the attendee notification modal.
    initializeAttendeesUi();
    document.getElementById("open-attendee-notification-modal")?.click();

    // Verify opens the attendee notification modal after the dashboard body.
    expect(document.getElementById("attendee-notification-form")?.getAttribute("hx-post")).to.equal(
      "/dashboard/group/notifications/event-99",
    );
    expect(document.getElementById("attendee-notification-modal")?.classList.contains("hidden")).to.equal(
      false,
    );
  });

  it("opens attendee notification with a row recipient preselected", async () => {
    // Render a confirmed attendee row action and the notification modal.
    document.body.innerHTML = attendeeNotificationMarkup(`
      <button
        type="button"
        data-attendee-notification-open
        data-event-id="event-42"
        data-notification-scope="selected"
        data-recipient-id="user-1"
        data-recipient-name="Ana Lopez"
        data-recipient-username="alopez"
        data-recipient-email="ana@example.test"
      >
        Send email
      </button>
    `);

    // Open the selected-recipient modal.
    initializeAttendeesUi();
    document.querySelector("[data-attendee-notification-open]")?.click();
    await waitForMicrotask();

    // Verify the row recipient is selected and submitted as a hidden field.
    expect(document.getElementById("attendee-notification-modal")?.classList.contains("hidden")).to.equal(
      false,
    );
    expect(document.getElementById("attendee-notification-recipient-scope")?.value).to.equal("selected");
    expect(document.getElementById("attendee-notification-recipient-summary")?.textContent).to.equal(
      "This email will be sent to 1 selected attendee.",
    );
    expect(
      document.querySelector('#attendee-notification-selected-fields input[name="recipient_user_ids[0]"]')
        ?.value,
    ).to.equal("user-1");
    expect(document.getElementById("submit-attendee-notification")?.disabled).to.equal(false);
    expect(fetchMock.calls).to.have.length(0);
  });

  it("opens the attendee email actions dropdown and starts table selection", () => {
    // Render attendees table selection controls.
    document.body.innerHTML = attendeeSelectionMarkup({
      eventId: "event-43",
      recipients: [
        {
          email: "ana@example.test",
          id: "user-1",
          name: "Ana Lopez",
          username: "alopez",
        },
      ],
    });

    // Start attendee selection from the email actions dropdown.
    initializeAttendeesUi();
    document.getElementById("attendee-email-actions-button")?.click();

    const dropdown = document.querySelector("[data-attendee-email-actions-dropdown]");
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    document.querySelector("[data-attendee-email-selection-start]")?.click();

    const bar = document.querySelector("[data-attendee-email-selection-bar]");
    const column = document.querySelector("[data-attendee-email-selection-column]");
    const checkbox = document.querySelector("[data-attendee-email-selection-checkbox]");
    const headerSend = document.getElementById("attendee-email-actions-button");
    expect(dropdown.classList.contains("hidden")).to.equal(true);
    expect(bar.classList.contains("hidden")).to.equal(false);
    expect(column.classList.contains("hidden")).to.equal(false);
    expect(document.activeElement).to.equal(checkbox);
    expect(headerSend?.textContent).to.equal("Send email");
    expect(headerSend?.disabled).to.equal(true);
    expect(document.querySelector("[data-attendee-email-selection-send]")?.disabled).to.equal(true);
  });

  it("opens attendee notification from selected table attendees", () => {
    // Render selectable attendee rows and the notification modal.
    document.body.innerHTML = attendeeSelectionMarkup({
      eventId: "event-44",
      recipients: [
        {
          email: "ana@example.test",
          id: "user-1",
          name: "Ana Lopez",
          username: "alopez",
        },
        {
          email: "bo@example.test",
          id: "user-2",
          name: "Bo Chen",
          username: "bchen",
        },
      ],
    });

    // Select both attendees and open the notification modal from the bar.
    initializeAttendeesUi();
    document.querySelector("[data-attendee-email-selection-start]")?.click();
    document.querySelectorAll("[data-attendee-email-selection-checkbox]").forEach((checkbox) => {
      checkbox.checked = true;
      checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    });

    expect(document.querySelector("[data-attendee-email-selection-count]")?.textContent).to.equal("2");
    expect(document.querySelector("[data-attendee-email-selection-send]")?.disabled).to.equal(false);

    document.querySelector("[data-attendee-email-selection-send]")?.click();

    // Verify selected attendees are submitted as hidden fields.
    expect(document.getElementById("attendee-notification-modal")?.classList.contains("hidden")).to.equal(
      false,
    );
    expect(document.getElementById("attendee-notification-form")?.getAttribute("hx-post")).to.equal(
      "/dashboard/group/notifications/event-44",
    );
    expect(document.getElementById("attendee-notification-recipient-scope")?.value).to.equal("selected");
    expect(document.getElementById("attendee-notification-recipient-summary")?.textContent).to.equal(
      "This email will be sent to 2 selected attendees.",
    );
    expect(
      [...document.querySelectorAll("#attendee-notification-selected-fields input")].map(
        (input) => input.value,
      ),
    ).to.deep.equal(["user-1", "user-2"]);
  });

  it("keeps selected attendees across table refreshes for the same event", () => {
    // Render the first attendee table page and select one attendee.
    document.body.innerHTML = attendeeSelectionMarkup({
      eventId: "event-45",
      recipients: [
        {
          email: "ana@example.test",
          id: "user-1",
          name: "Ana Lopez",
          username: "alopez",
        },
      ],
    });

    initializeAttendeesUi();
    document.querySelector("[data-attendee-email-selection-start]")?.click();
    const initialCheckbox = document.querySelector("[data-attendee-email-selection-checkbox]");
    initialCheckbox.checked = true;
    initialCheckbox.dispatchEvent(new Event("change", { bubbles: true }));
    expect(document.querySelector("[data-attendee-email-selection-count]")?.textContent).to.equal("1");
    expect(document.querySelector("[data-attendee-email-selection-label]")?.textContent).to.equal(
      "attendee selected",
    );

    // Swap in a refreshed table page for the same event.
    const attendeesRoot = document.getElementById("attendees-content");
    attendeesRoot.innerHTML = attendeeSelectionInnerMarkup({
      eventId: "event-45",
      recipients: [
        {
          email: "ana@example.test",
          id: "user-1",
          name: "Ana Lopez",
          username: "alopez",
        },
        {
          email: "bo@example.test",
          id: "user-2",
          name: "Bo Chen",
          username: "bchen",
        },
      ],
    });
    dispatchHtmxLoad(attendeesRoot);

    const refreshedCheckboxes = document.querySelectorAll("[data-attendee-email-selection-checkbox]");
    expect(
      document.querySelector("[data-attendee-email-selection-bar]")?.classList.contains("hidden"),
    ).to.equal(false);
    expect(refreshedCheckboxes[0].checked).to.equal(true);
    expect(refreshedCheckboxes[1].checked).to.equal(false);
    expect(document.querySelector("[data-attendee-email-selection-count]")?.textContent).to.equal("1");
  });

  it("clears selected attendees when the refreshed table belongs to another event", () => {
    // Render a selectable attendees table for the original event.
    document.body.innerHTML = attendeeSelectionMarkup({
      eventId: "event-42",
      recipients: [
        {
          email: "ana@example.test",
          id: "user-1",
          name: "Ana Lopez",
          username: "alopez",
        },
      ],
    });

    initializeAttendeesUi();
    document.querySelector("[data-attendee-email-selection-start]")?.click();
    const initialCheckbox = document.querySelector("[data-attendee-email-selection-checkbox]");
    initialCheckbox.checked = true;
    initialCheckbox.dispatchEvent(new Event("change", { bubbles: true }));

    // Swap to a different event and verify selection mode resets.
    const attendeesRoot = document.getElementById("attendees-content");
    attendeesRoot.innerHTML = attendeeSelectionInnerMarkup({
      eventId: "event-99",
      recipients: [
        {
          email: "cyd@example.test",
          id: "user-3",
          name: "Cyd Diaz",
          username: "cdiaz",
        },
      ],
    });
    dispatchHtmxLoad(attendeesRoot);

    expect(
      document.querySelector("[data-attendee-email-selection-bar]")?.classList.contains("hidden"),
    ).to.equal(true);
    expect(document.querySelector("[data-attendee-email-selection-checkbox]")?.checked).to.equal(false);
    expect(document.querySelector("[data-attendee-email-selection-count]")?.textContent).to.equal("0");
    expect(document.querySelector("[data-attendee-email-selection-label]")?.textContent).to.equal(
      "attendees selected",
    );
  });

  it("clears and cancels attendee email selection", () => {
    // Render attendee selection controls.
    document.body.innerHTML = attendeeSelectionMarkup({
      eventId: "event-77",
      recipients: [
        {
          email: "ana@example.test",
          id: "user-1",
          name: "Ana Lopez",
          username: "alopez",
        },
      ],
    });

    // Clear keeps selection mode open, while cancel exits it.
    initializeAttendeesUi();
    document.querySelector("[data-attendee-email-selection-start]")?.click();
    const checkbox = document.querySelector("[data-attendee-email-selection-checkbox]");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));

    document.querySelector("[data-attendee-email-selection-clear]")?.click();
    expect(
      document.querySelector("[data-attendee-email-selection-bar]")?.classList.contains("hidden"),
    ).to.equal(false);
    expect(checkbox.checked).to.equal(false);
    expect(document.querySelector("[data-attendee-email-selection-count]")?.textContent).to.equal("0");
    expect(document.querySelector("[data-attendee-email-selection-send]")?.disabled).to.equal(true);

    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    document.querySelector("[data-attendee-email-selection-cancel]")?.click();

    expect(
      document.querySelector("[data-attendee-email-selection-bar]")?.classList.contains("hidden"),
    ).to.equal(true);
    expect(checkbox.checked).to.equal(false);
    expect(document.getElementById("attendee-email-actions-button")?.disabled).to.equal(false);
    expect(document.activeElement).to.equal(document.getElementById("attendee-email-actions-button"));
  });

  it("resets attendee email selection after a successful selected-recipient send", () => {
    // Render selected attendee notification controls.
    document.body.innerHTML = attendeeSelectionMarkup({
      eventId: "event-88",
      recipients: [
        {
          email: "ana@example.test",
          id: "user-1",
          name: "Ana Lopez",
          username: "alopez",
        },
      ],
    });

    // Send to a selected attendee and dispatch a successful response.
    initializeAttendeesUi();
    document.querySelector("[data-attendee-email-selection-start]")?.click();
    const checkbox = document.querySelector("[data-attendee-email-selection-checkbox]");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    document.querySelector("[data-attendee-email-selection-send]")?.click();

    const form = document.getElementById("attendee-notification-form");
    dispatchHtmxAfterRequest(form, { status: 200 });

    expect(env.current.swal.calls[0]).to.include({
      text: "Email sent successfully to selected attendees!",
      icon: "success",
    });
    expect(document.getElementById("attendee-notification-modal")?.classList.contains("hidden")).to.equal(
      true,
    );
    expect(
      document.querySelector("[data-attendee-email-selection-bar]")?.classList.contains("hidden"),
    ).to.equal(true);
    expect(checkbox.checked).to.equal(false);
    expect(document.getElementById("attendee-notification-recipient-scope")?.value).to.equal("all");
    expect(document.querySelectorAll("#attendee-notification-selected-fields input")).to.have.length(0);
  });

  it("leaves attendee email selection active after a failed selected-recipient send", () => {
    // Render selected attendee notification controls.
    document.body.innerHTML = attendeeSelectionMarkup({
      eventId: "event-89",
      recipients: [
        {
          email: "ana@example.test",
          id: "user-1",
          name: "Ana Lopez",
          username: "alopez",
        },
      ],
    });

    // Send to a selected attendee and dispatch a failed response.
    initializeAttendeesUi();
    document.querySelector("[data-attendee-email-selection-start]")?.click();
    const checkbox = document.querySelector("[data-attendee-email-selection-checkbox]");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    document.querySelector("[data-attendee-email-selection-send]")?.click();

    const form = document.getElementById("attendee-notification-form");
    dispatchHtmxAfterRequest(form, { status: 500, responseText: "Nope" });

    expect(env.current.swal.calls[0]).to.include({
      text: "Nope",
      icon: "error",
    });
    expect(document.getElementById("attendee-notification-modal")?.classList.contains("hidden")).to.equal(
      false,
    );
    expect(
      document.querySelector("[data-attendee-email-selection-bar]")?.classList.contains("hidden"),
    ).to.equal(false);
    expect(checkbox.checked).to.equal(true);
    document.querySelector("[data-attendee-email-selection-cancel]")?.click();
  });

  it("opens attendee notification for all eligible attendees", () => {
    // Render the all-recipient notification trigger.
    document.body.innerHTML = attendeeNotificationMarkup(`
      <button
        type="button"
        data-attendee-notification-open
        data-event-id="event-42"
        data-notification-scope="all"
        data-notification-recipient-total="3"
      >
        Send email
      </button>
    `);

    initializeAttendeesUi();
    document.querySelector("[data-attendee-notification-open]")?.click();

    expect(document.getElementById("attendee-notification-modal")?.classList.contains("hidden")).to.equal(
      false,
    );
    expect(document.getElementById("attendee-notification-recipient-scope")?.value).to.equal("all");
    expect(document.getElementById("attendee-notification-recipient-summary")?.textContent).to.equal(
      "This email will be sent to 3 eligible attendees.",
    );
    expect(document.querySelectorAll("#attendee-notification-selected-fields input")).to.have.length(0);
    expect(document.getElementById("submit-attendee-notification")?.disabled).to.equal(false);
  });

  it("opens the attendee answers modal with copied answers", () => {
    // Render the attendee answers trigger and modal.
    document.body.innerHTML = `
      <div id="attendees-content">
        <button
          type="button"
          data-attendee-answers-open
          data-attendee-answers-source="attendee-answers-user-1"
          data-attendee-name="Ana Lopez"
        >
          View answers
        </button>
        <div id="attendee-answers-user-1" hidden>
          <ol>
            <li>
              <h4>Tell us about your experience</h4>
              <div>Free text</div>
              <div>Very positive.</div>
            </li>
          </ol>
        </div>
        <div id="attendee-answers-modal" class="hidden">
          <button id="close-attendee-answers-modal" type="button">Close</button>
          <button id="cancel-attendee-answers-modal" type="button">Cancel</button>
          <div id="overlay-attendee-answers-modal"></div>
          <div id="attendee-answers-name"></div>
          <div id="attendee-answers-content"></div>
        </div>
      </div>
    `;

    initializeAttendeesUi();
    document.querySelector("[data-attendee-answers-open]")?.click();

    // Set up modal.
    const modal = document.getElementById("attendee-answers-modal");
    const content = document.getElementById("attendee-answers-content");

    // Verify opens the attendee answers modal with copied answers.
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("attendee-answers-name")?.textContent).to.equal("Ana Lopez");
    expect(content.textContent).to.include("Tell us about your experience");
    expect(content.textContent).to.include("Very positive.");

    // Click the cancel attendee answers modal button.
    document.getElementById("cancel-attendee-answers-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("opens refund rejection with the selected attendee context", () => {
    // Mock HTMX processing before rendering the rejection modal.
    const originalHtmx = window.htmx;
    const processCalls = [];
    window.htmx = {
      process: (element) => processCalls.push(element?.id),
    };
    document.body.innerHTML = attendeeRefundRejectMarkup();
    initializeAttendeesUi();
    document.getElementById("attendee-refund-review-note").value = "stale";

    try {
      // Open the refund rejection from the attendee actions menu.
      document.querySelector("[data-attendee-refund-reject-open]")?.click();

      // Verify the endpoint, context, reset state, and focus contract.
      const form = document.getElementById("attendee-refund-reject-form");
      expect(document.getElementById("attendee-refund-reject-modal")?.classList.contains("hidden")).to.equal(
        false,
      );
      expect(form?.getAttribute("hx-put")).to.equal("/dashboard/group/refunds/purchase-1/reject");
      expect(document.getElementById("attendee-refund-reject-name")?.textContent).to.equal("Ana Lopez");
      expect(document.getElementById("attendee-refund-reject-event")?.textContent).to.equal(
        "Community meetup",
      );
      expect(document.getElementById("attendee-refund-review-note")?.value).to.equal("");
      expect(document.activeElement).to.equal(document.getElementById("attendee-refund-review-note"));
      expect(processCalls).to.deep.equal(["attendee-refund-reject-form"]);
    } finally {
      window.htmx = originalHtmx;
    }
  });

  it("normalizes and preserves the attendee refund approval note", () => {
    // Render and open the attendee refund approval modal.
    const originalHtmx = window.htmx;
    const processCalls = [];
    window.htmx = { process: (element) => processCalls.push(element?.id) };
    document.body.innerHTML = attendeeRefundApproveMarkup();
    initializeAttendeesUi();
    document.querySelector("[data-attendee-refund-approve-open]")?.click();
    const form = document.getElementById("attendee-refund-approve-form");
    const modal = document.getElementById("attendee-refund-approve-modal");
    const reviewNote = document.getElementById("attendee-refund-approve-review-note");

    try {
      // Verify the endpoint, context, and focus contract.
      expect(modal?.classList.contains("hidden")).to.equal(false);
      expect(form?.getAttribute("hx-put")).to.equal("/dashboard/group/refunds/purchase-1/approve");
      expect(document.getElementById("attendee-refund-approve-name")?.textContent).to.equal("Ana Lopez");
      expect(document.getElementById("attendee-refund-approve-event")?.textContent).to.equal(
        "Community meetup",
      );
      expect(document.activeElement).to.equal(reviewNote);
      expect(processCalls).to.deep.equal(["attendee-refund-approve-form"]);

      // Trim the note and preserve it after a failed request.
      reviewNote.value = "  Approved by organizer  ";
      const configRequestEvent = new CustomEvent("htmx:configRequest", {
        bubbles: true,
        detail: {
          parameters: { review_note: "  Approved by organizer  " },
          unfilteredParameters: { review_note: "  Approved by organizer  " },
        },
      });
      form.dispatchEvent(configRequestEvent);
      expect(configRequestEvent.detail.parameters.review_note).to.equal("Approved by organizer");
      dispatchHtmxAfterRequest(form, { status: 422 });
      expect(modal?.classList.contains("hidden")).to.equal(false);
      expect(reviewNote.value).to.equal("Approved by organizer");

      // Close after success and restore focus to the row menu.
      dispatchHtmxAfterRequest(form, { status: 204 });
      expect(modal?.classList.contains("hidden")).to.equal(true);
      expect(document.activeElement).to.equal(document.querySelector("[data-actions-menu] summary"));
    } finally {
      window.htmx = originalHtmx;
    }
  });

  it("does not duplicate active refund handling when the same root reloads", () => {
    // Render one active approval flow and initialize its root twice.
    const originalHtmx = window.htmx;
    const processCalls = [];
    window.htmx = { process: (element) => processCalls.push(element?.id) };
    document.body.innerHTML = attendeeRefundApproveMarkup();
    const attendeesRoot = document.getElementById("attendees-content");

    try {
      dispatchHtmxLoad(attendeesRoot);
      dispatchHtmxLoad(attendeesRoot);
      document.querySelector("[data-attendee-refund-approve-open]")?.click();

      // Verify one listener processes the active approval form once.
      expect(processCalls).to.deep.equal(["attendee-refund-approve-form"]);
    } finally {
      window.htmx = originalHtmx;
    }
  });

  it("normalizes and preserves the attendee refund rejection note", () => {
    // Render and open the attendee refund rejection modal.
    const originalHtmx = window.htmx;
    window.htmx = { process: () => {} };
    document.body.innerHTML = attendeeRefundRejectMarkup();
    initializeAttendeesUi();
    document.querySelector("[data-attendee-refund-reject-open]")?.click();
    const form = document.getElementById("attendee-refund-reject-form");
    const modal = document.getElementById("attendee-refund-reject-modal");
    const reviewNote = document.getElementById("attendee-refund-review-note");

    try {
      // Omit a whitespace-only optional note.
      reviewNote.value = "   ";
      const blankConfigRequestEvent = new CustomEvent("htmx:configRequest", {
        bubbles: true,
        detail: {
          parameters: { review_note: "   " },
          unfilteredParameters: { review_note: "   " },
        },
      });
      form.dispatchEvent(blankConfigRequestEvent);
      expect(blankConfigRequestEvent.detail.parameters).not.to.have.property("review_note");
      expect(blankConfigRequestEvent.detail.unfilteredParameters).not.to.have.property("review_note");

      // Trim a provided review note before submission.
      reviewNote.value = "  Outside the refund policy window  ";
      const configRequestEvent = new CustomEvent("htmx:configRequest", {
        bubbles: true,
        detail: {
          parameters: { review_note: "  Outside the refund policy window  " },
          unfilteredParameters: { review_note: "  Outside the refund policy window  " },
        },
      });
      form.dispatchEvent(configRequestEvent);
      expect(reviewNote.value).to.equal("Outside the refund policy window");
      expect(configRequestEvent.detail.parameters.review_note).to.equal("Outside the refund policy window");
      expect(configRequestEvent.detail.unfilteredParameters.review_note).to.equal(
        "Outside the refund policy window",
      );

      // Preserve the note after failure and close the modal after success.
      dispatchHtmxAfterRequest(form, { status: 422 });
      expect(modal?.classList.contains("hidden")).to.equal(false);
      expect(reviewNote.value).to.equal("Outside the refund policy window");
      dispatchHtmxAfterRequest(form, { status: 204 });
      expect(modal?.classList.contains("hidden")).to.equal(true);
      expect(document.activeElement).to.equal(document.querySelector("[data-actions-menu] summary"));
    } finally {
      window.htmx = originalHtmx;
    }
  });

  it("handles invitation modal controls after attendee content refreshes", () => {
    // Render invitation controls inside refreshed attendees content.
    document.body.innerHTML = `
      <div id="attendees-content">
        ${attendeeInvitationMarkup()}
      </div>
    `;

    // Set up attendees root.
    const attendeesRoot = document.getElementById("attendees-content");
    dispatchHtmxLoad(attendeesRoot);

    // Click the open attendee invitation modal button.
    document.getElementById("open-attendee-invitation-modal")?.click();

    // Set up initial submit.
    const initialSubmit = document.getElementById("submit-attendee-invitation");
    const initialSearchField = document.querySelector("[data-attendee-invitation-search]");
    const initialEmailInput = document.getElementById("attendee-invitation-email");
    initialSearchField.dispatchEvent(
      new CustomEvent("user-search-query-changed", {
        bubbles: true,
        detail: { query: "first" },
      }),
    );

    // Verify handles invitation modal controls after attendee content refreshes.
    expect(initialSubmit.disabled).to.equal(true);

    // Dispatch the form event.
    initialSearchField.dispatchEvent(
      new CustomEvent("user-search-query-changed", {
        bubbles: true,
        detail: { query: "first@example.com" },
      }),
    );
    expect(initialEmailInput.value).to.equal("first@example.com");
    expect(initialSubmit.disabled).to.equal(false);

    // Re-render refreshed attendee invitation markup.
    attendeesRoot.innerHTML = attendeeInvitationMarkup();
    dispatchHtmxLoad(attendeesRoot);

    // Click the open attendee invitation modal button.
    document.getElementById("open-attendee-invitation-modal")?.click();

    // Set up refreshed modal.
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

    // Assert the saved field value.
    expect(refreshedEmailInput.value).to.equal("second@example.com");
    expect(refreshedSubmit.disabled).to.equal(false);

    dispatchHtmxAfterRequest(document.getElementById("attendee-invitation-form"), { status: 201 });

    // Assert the confirmation dialog options.
    expect(env.current.swal.calls[0]).to.include({
      text: "Invitation sent.",
      icon: "success",
    });
    expect(refreshedModal.classList.contains("hidden")).to.equal(true);
  });

  it("enables attendee invitation for a typed email when no user matches", async () => {
    // Mock an empty user search result for the typed email flow.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [];
      },
    }));

    // Mount the DOM fixture.
    document.body.innerHTML = `
      <div id="attendees-content">
        ${attendeeInvitationMarkup()}
      </div>
    `;

    // Set up attendees root.
    const attendeesRoot = document.getElementById("attendees-content");
    dispatchHtmxLoad(attendeesRoot);

    // Click the open attendee invitation modal button.
    document.getElementById("open-attendee-invitation-modal")?.click();

    // Set up search field.
    const searchField = document.querySelector("[data-attendee-invitation-search]");
    await searchField.updateComplete;
    searchField.searchDelay = 0;

    // Set up search input.
    const searchInput = searchField.querySelector("[data-user-search-input]");
    const userInput = document.getElementById("attendee-invitation-user-id");
    const emailInput = document.getElementById("attendee-invitation-email");
    const submitButton = document.getElementById("submit-attendee-invitation");

    // Answer the required form question.
    searchInput.value = "invitee+test3@example.com";
    searchInput.dispatchEvent(new Event("input", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    await searchField.updateComplete;

    // Verify enables attendee invitation for a typed email when no user matches.
    expect(emailInput.value).to.equal("invitee+test3@example.com");
    expect(userInput.disabled).to.equal(true);
    expect(emailInput.disabled).to.equal(false);
    expect(searchField.textContent).to.contain("invitee+test3@example.com");
    expect(searchField.textContent).to.contain("Invite by email");
    expect(searchField.textContent).not.to.contain("No users found");
    expect(submitButton.disabled).to.equal(false);

    // Click Invite by email invitee+test3@example.com.
    searchField.querySelector("button[aria-label='Invite by email invitee+test3@example.com']")?.click();
    await waitForMicrotask();

    // Set up selected user.
    const selectedUser = document.getElementById("attendee-invitation-selected-user");

    // Assert the saved field value.
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
    // Render invitation controls before dispatching a user selection.
    document.body.innerHTML = `
      <div id="attendees-content">
        ${attendeeInvitationMarkup()}
      </div>
    `;

    // Set up attendees root.
    const attendeesRoot = document.getElementById("attendees-content");
    dispatchHtmxLoad(attendeesRoot);

    // Dispatch the form event.
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

    // Set up selected user.
    const selectedUser = document.getElementById("attendee-invitation-selected-user");
    const userInput = document.getElementById("attendee-invitation-user-id");
    const emailInput = document.getElementById("attendee-invitation-email");
    const submitButton = document.getElementById("submit-attendee-invitation");
    const pill = selectedUser.querySelector(".inline-flex.rounded-full");

    // Verify renders selected invitation users with the shared user pill style.
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

    // Click the pill.
    pill.querySelector("[data-attendee-invitation-clear-user]")?.click();

    // Assert the saved field value.
    expect(userInput.value).to.equal("");
    expect(userInput.disabled).to.equal(true);
    expect(emailInput.disabled).to.equal(true);
    expect(selectedUser.children).to.have.length(0);
    expect(submitButton.disabled).to.equal(true);
  });

  it("keeps the check-in toggle disabled after a successful check-in", async () => {
    // Render the DOM fixture for keeping the check-in toggle disabled.
    document.body.innerHTML = `
      <label class="cursor-pointer">
        <input
          type="checkbox"
          class="check-in-toggle"
          data-url="/dashboard/group/attendees/check-in/7"
        />
      </label>
    `;

    // Verify keeps the check-in toggle disabled.
    initializeAttendeesUi();

    // Keep a reference to the check in toggle element.
    const checkbox = document.querySelector(".check-in-toggle");
    const label = checkbox.closest("label");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    // Verify keeps the check-in toggle disabled after a successful check-in.
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
    // Configure browser state before testing the failed check-in path.
    fetchMock.setImpl(async () => ({ ok: false, status: 500 }));

    // Render the DOM fixture for reverts the check-in toggle and shows an error.
    document.body.innerHTML = `
      <label class="cursor-pointer">
        <input
          type="checkbox"
          class="check-in-toggle"
          data-url="/dashboard/group/attendees/check-in/8"
        />
      </label>
    `;

    // Failed check-in reverts the toggle and shows an error.
    initializeAttendeesUi();

    // Keep a reference to the check in toggle element.
    const checkbox = document.querySelector(".check-in-toggle");
    const label = checkbox.closest("label");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    // A failed request reverts the check-in toggle and shows an error.
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

});
