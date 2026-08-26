import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/attendees.js";
import { initializeEventsListPage } from "/static/js/dashboard/group/events-list.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

// Prepare the module under test.
const scopedActionMarkup = ({ hasRelatedEvents = false } = {}) => `
  <button
    id="publish-event-123"
    data-event-scoped-action
    data-action-url="/dashboard/group/events/123/publish"
    data-has-related-events="${String(hasRelatedEvents)}"
    data-current-scope-text="Only this event"
    data-series-scope-text="All in series"
    data-confirm-text="Yes"
    data-cancel-text="No"
    data-series-message="Publish this series?"
    data-single-message="Publish this event?"
    data-success-message="Published event"
    data-series-success-message="Published events"
    data-series-error-message="Publish series failed"
    data-error-message="Publish failed">
    Publish
  </button>
`;

// Mount events list for the test.
const mountEventsList = ({ hasRelatedEvents = false } = {}) => {
  document.body.innerHTML = `
    <div id="events-list-root">
      <button
        class="btn-actions"
        data-event-id="123"
        aria-controls="dropdown-actions-123"
        aria-expanded="false"
      >
        Actions
      </button>
      <div id="dropdown-actions-123" data-event-actions-dropdown class="dropdown hidden">
        ${scopedActionMarkup({ hasRelatedEvents })}
      </div>
    </div>
  `;
  return document.getElementById("events-list-root");
};

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/events_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("events list page", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/group?tab=events",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
  });

  it("warns admins about cancellation refunds and unpublish retention", async () => {
    // Load the events list template before checking destructive action copy.
    const template = await loadTemplate();

    // Verify warnings and action labels make each destructive choice explicit.
    expect(template).to.include(
      "Unpublish this event? Existing attendees and ticket purchases will be retained.",
    );
    expect(template).to.include(
      "All attendee registrations will be canceled immediately. Full refunds for eligible paid purchases will be queued and may take time to process.",
    );
    expect(template).to.include(
      'data-confirm-text="{% if action == "cancel" %}Cancel event{% else %}Yes{% endif %}"',
    );
    expect(template).to.include(
      'data-cancel-text="{% if action == "cancel" %}Keep event{% else %}No{% endif %}"',
    );
    expect(template).to.include('data-series-scope-text="Non-completed events in series"');
  });

  it("disables deletion when the event is not eligible", async () => {
    // Load the events list template before checking disabled delete actions.
    const template = await loadTemplate();

    // Verify unavailable delete actions expose their reason in the title.
    expect(template).to.include('action == "delete" && !event.can_delete()');
    expect(template).to.include("event.delete_unavailable_title()");
    expect(template).to.include('title="{{ delete_title }}"');
  });

  it("renders event action buttons as accessible disclosures", async () => {
    // Load production event actions before checking their disclosure contract.
    const template = await loadTemplate();

    // Both upcoming and past actions expose their label, target, and collapsed state.
    expect(template.match(/aria-label="Open actions for \{\{ event\.name \}\}"/g)).to.have.length(2);
    expect(template.match(/aria-controls="dropdown-actions-\{\{ event\.event_id \}\}"/g)).to.have.length(2);
    expect(template.match(/aria-expanded="false"/g)).to.have.length(2);
    expect(template).to.not.include("dropdownDefaultButton");
  });

  it("toggles event action dropdowns with delegated handlers", () => {
    // Prepare root for toggling event action dropdowns with delegated handlers.
    const root = mountEventsList();
    initializeEventsListPage(root);

    // Keep a reference to the button actions element.
    const actionsButton = root.querySelector(".btn-actions");
    const dropdown = root.querySelector(".dropdown");

    // Verify toggles event action dropdowns.
    actionsButton.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);
    expect(actionsButton.getAttribute("aria-expanded")).to.equal("true");

    // Click outside the dropdown to close it.
    root.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(true);
    expect(actionsButton.getAttribute("aria-expanded")).to.equal("false");

    // Reopen and click outside the events list root.
    actionsButton.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);
    document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(true);
    expect(actionsButton.getAttribute("aria-expanded")).to.equal("false");
  });

  it("toggles event action dropdowns added after initialization", () => {
    // Prepare an empty root before inserting a newly rendered event row.
    document.body.innerHTML = '<div id="events-list-root"></div>';
    const root = document.getElementById("events-list-root");
    initializeEventsListPage(root);

    // Insert the controls the dashboard receives after an event list refresh.
    root.insertAdjacentHTML(
      "beforeend",
      `
        <button type="button" class="btn-actions" data-event-id="event.123">Actions</button>
        <div id="dropdown-actions-event.123" data-event-actions-dropdown class="dropdown hidden">
          ${scopedActionMarkup()}
        </div>
      `,
    );

    // Verify delegated handlers and id lookup work for the added row.
    const clickEvent = new MouseEvent("click", {
      bubbles: true,
      cancelable: true,
    });
    root.querySelector(".btn-actions").dispatchEvent(clickEvent);

    expect(clickEvent.defaultPrevented).to.equal(true);
    expect(root.querySelector(".dropdown").classList.contains("hidden")).to.equal(false);
  });

  it("restores disclosure focus when Escape closes an actions dropdown", () => {
    // Open an actions dropdown and move focus into its controls.
    const root = mountEventsList();
    initializeEventsListPage(root);
    const actionsButton = root.querySelector(".btn-actions");
    const dropdown = root.querySelector("[data-event-actions-dropdown]");
    actionsButton.click();
    dropdown.querySelector("button").focus();

    // Escape closes the dropdown, synchronizes state, and restores focus.
    document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    expect(dropdown.classList.contains("hidden")).to.equal(true);
    expect(actionsButton.getAttribute("aria-expanded")).to.equal("false");
    expect(document.activeElement).to.equal(actionsButton);
  });

  it("disables invitation request assignment without an eligible ticket tier", () => {
    // Build production-shaped invitation request controls without an assignable option.
    document.body.innerHTML = `
      <div id="events-list-root">
        <form>
          <select data-invitation-request-ticket-type>
            <option value="">Select ticket type</option>
          </select>
          <p data-invitation-request-ticket-empty class="hidden">No tickets available.</p>
          <button data-invitation-request-ticket-submit type="submit">Accept</button>
        </form>
      </div>
    `;
    const root = document.getElementById("events-list-root");

    // Initialize the invitation request ticket guard.
    initializeEventsListPage(root);

    // Check the unavailable controls and recovery guidance are synchronized.
    expect(root.querySelector("select").disabled).to.equal(true);
    expect(root.querySelector("button").disabled).to.equal(true);
    expect(root.querySelector("p").classList.contains("hidden")).to.equal(false);
  });

  it("keeps invitation request accept disabled when registration is closed", () => {
    // Build invitation request assignment with an eligible ticket after registration closed.
    document.body.innerHTML = `
      <div id="events-list-root">
        <form>
          <select data-invitation-request-ticket-type>
            <option value="">Select ticket type</option>
            <option value="ticket-1">Private admission</option>
          </select>
          <p data-invitation-request-ticket-empty class="hidden">No tickets available.</p>
          <button
            data-invitation-request-ticket-submit
            data-invitation-request-accept-blocked
            type="submit"
            disabled
          >
            Accept
          </button>
        </form>
      </div>
    `;
    const root = document.getElementById("events-list-root");

    // Initialize the invitation request ticket guard.
    initializeEventsListPage(root);

    // Check accept stays blocked even when a ticket type can be assigned.
    expect(root.querySelector("select").disabled).to.equal(false);
    expect(root.querySelector("button").disabled).to.equal(true);
    expect(root.querySelector("p").classList.contains("hidden")).to.equal(true);
  });

  it("keeps invitation request accept disabled when the template already disabled it", () => {
    // Build invitation request assignment with an eligible ticket and a template-disabled accept.
    document.body.innerHTML = `
      <div id="events-list-root">
        <form>
          <select data-invitation-request-ticket-type>
            <option value="">Select ticket type</option>
            <option value="ticket-1">Private admission</option>
          </select>
          <p data-invitation-request-ticket-empty class="hidden">No tickets available.</p>
          <button
            data-invitation-request-ticket-submit
            type="submit"
            disabled
            title="Your role cannot manage invitation requests."
          >
            Accept
          </button>
        </form>
      </div>
    `;
    const root = document.getElementById("events-list-root");

    // Initialize the invitation request ticket guard.
    initializeEventsListPage(root);

    // Check accept stays disabled for template reasons other than registration close.
    expect(root.querySelector("select").disabled).to.equal(false);
    expect(root.querySelector("button").disabled).to.equal(true);
    expect(root.querySelector("p").classList.contains("hidden")).to.equal(true);
  });

  it("does not bind answers modal controls without a review modal", () => {
    // Initialize an events-list root that does not include a review modal.
    document.body.innerHTML = `<div id="events-list-root"></div>`;
    const root = document.getElementById("events-list-root");

    initializeEventsListPage(root);

    // Check the shared answers modal is not initialized on unrelated pages.
    expect(root.dataset.invitationRequestAnswersModalReady).to.equal(undefined);
  });

  it("opens invitation request answers from the shared review modal", () => {
    // Render an invitation request answers trigger and modal.
    document.body.innerHTML = `
      <div id="events-list-root">
        <button
          type="button"
          data-answers-open
          data-answers-source="invitation-request-answers-user-1"
          data-answers-name="Requesting User"
        >
          View answers
        </button>
        <div id="invitation-request-answers-user-1" hidden>
          <ol>
            <li>
              <h4>Dietary restrictions?</h4>
              <div>Vegetarian</div>
            </li>
          </ol>
        </div>
        <div id="invitation-request-answers-modal" class="hidden">
          <button id="close-invitation-request-answers-modal" type="button">Close</button>
          <button id="cancel-invitation-request-answers-modal" type="button">Cancel</button>
          <div id="overlay-invitation-request-answers-modal"></div>
          <div id="invitation-request-answers-name"></div>
          <div id="invitation-request-answers-content"></div>
        </div>
      </div>
    `;
    const root = document.getElementById("events-list-root");

    // Initialize the invitation request answers modal.
    initializeEventsListPage(root);
    root.querySelector("[data-answers-open]")?.click();

    // Verify opens the invitation request answers modal with copied answers.
    const modal = document.getElementById("invitation-request-answers-modal");
    const content = document.getElementById("invitation-request-answers-content");
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("invitation-request-answers-name")?.textContent).to.equal(
      "Requesting User",
    );
    expect(content.textContent).to.include("Dietary restrictions?");
    expect(content.textContent).to.include("Vegetarian");

    // Close the invitation request answers modal.
    document.getElementById("cancel-invitation-request-answers-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("opens invitation request answers when attendees features initialize first", () => {
    // Render a Requests tab fragment the way HTMX adds it beside the Attendees tab scripts.
    document.body.innerHTML = `
      <div id="invitation-requests-refresh" data-events-list-page>
        <button
          type="button"
          data-answers-open
          data-answers-source="invitation-request-answers-user-1"
          data-answers-name="Requesting User"
        >
          View answers
        </button>
        <div id="invitation-request-answers-user-1" hidden>
          <ol>
            <li>
              <h4>Dietary restrictions?</h4>
              <div>Vegetarian</div>
            </li>
          </ol>
        </div>
        <div id="invitation-request-answers-modal" class="hidden">
          <button id="close-invitation-request-answers-modal" type="button">Close</button>
          <button id="cancel-invitation-request-answers-modal" type="button">Cancel</button>
          <div id="overlay-invitation-request-answers-modal"></div>
          <div id="invitation-request-answers-name"></div>
          <div id="invitation-request-answers-content"></div>
        </div>
      </div>
    `;
    const root = document.getElementById("invitation-requests-refresh");

    // Initialize both page modules against the swapped Requests fragment.
    dispatchHtmxLoad(root);
    root.querySelector("[data-answers-open]")?.click();

    // Verify the invitation request modal opens instead of targeting attendee modal ids.
    const modal = document.getElementById("invitation-request-answers-modal");
    expect(root.dataset.attendeeAnswersModalReady).to.equal(undefined);
    expect(root.dataset.invitationRequestAnswersModalReady).to.equal("true");
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("invitation-request-answers-name")?.textContent).to.equal(
      "Requesting User",
    );
    expect(document.getElementById("invitation-request-answers-content")?.textContent).to.include(
      "Vegetarian",
    );
  });

  it("confirms a single-event action and rewrites the HTMX request path", async () => {
    // Render a single-event action and confirm it through the shared dialog.
    const root = mountEventsList();
    initializeEventsListPage(root);

    // Keep a reference to the event scoped action element.
    const button = root.querySelector("[data-event-scoped-action]");
    button.click();
    await waitForMicrotask();

    // Verify the dialog copy and confirmation event use the single-event scope.
    expect(env.current.swal.calls[0].text).to.equal("Publish this event?");
    expect(env.current.swal.calls[0].cancelButtonText).to.equal("No");
    expect(env.current.htmx.triggerCalls).to.deep.equal([[button, "confirmed"]]);
    expect(button.dataset.requestScope).to.equal("this");

    // Apply the selected scope to the outgoing HTMX request.
    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: { path: "/original" },
    });
    button.dispatchEvent(configEvent);

    // Verify the request targets only the selected event.
    expect(configEvent.detail.path).to.equal("/dashboard/group/events/123/publish");
  });

  it("confirms a series action and reports the scoped response message", async () => {
    // Prepare root for confirming a series action and reports the scoped response.
    const root = mountEventsList({ hasRelatedEvents: true });
    initializeEventsListPage(root);
    env.current.swal.setNextResult({ isConfirmed: false, isDenied: true });

    // Keep a reference to the event scoped action element.
    const button = root.querySelector("[data-event-scoped-action]");
    button.click();
    await waitForMicrotask();

    // Verify confirms a series action and reports the scoped response message.
    expect(env.current.swal.calls[0].text).to.equal("Publish this series?");
    expect(env.current.htmx.triggerCalls).to.deep.equal([[button, "confirmed"]]);

    // Prepare config event for confirming a series action and reports the scoped.
    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: { path: "/original" },
    });
    button.dispatchEvent(configEvent);

    // Verify confirms a series action and reports the scoped response message.
    expect(configEvent.detail.path).to.equal("/dashboard/group/events/123/publish?scope=series");

    // Dispatch the successful series action response.
    button.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: { xhr: { status: 204 } },
      }),
    );

    // Verify confirms a series action and reports the scoped response message.
    expect(button.dataset.requestPath).to.equal(undefined);
    expect(button.dataset.requestScope).to.equal(undefined);
    expect(env.current.swal.calls[1].text).to.equal("Published events");
  });

  it("shows an error alert for failed invitation request actions", () => {
    // Prepare root for showing an error alert for failed invitation request.
    const root = mountEventsList();
    root.insertAdjacentHTML(
      "beforeend",
      `
        <button
          data-invitation-request-action
          data-error-message="Accept failed."
        >
          Accept
        </button>
      `,
    );
    initializeEventsListPage(root);

    // Dispatch the failed invitation action response.
    root.querySelector("[data-invitation-request-action]").dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: { xhr: { status: 500 } },
      }),
    );

    // Verify shows an error alert for failed invitation request actions.
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      text: "Accept failed.",
      icon: "error",
    });
  });

  it("initializes declarative events list roots on htmx load", () => {
    // Prepare an HTMX-loaded invitation requests root.
    document.body.innerHTML = `
      <div data-events-list-page>
        <button class="btn-actions" data-event-id="invitation-request-user-1">Actions</button>
        <div
          id="dropdown-actions-invitation-request-user-1"
          data-event-actions-dropdown
          class="dropdown hidden">
          <button
            data-invitation-request-action
            data-error-message="Accept failed.">
            Accept
          </button>
        </div>
      </div>
    `;

    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.body);

    // Verify the actions dropdown is initialized from the declarative root.
    document.querySelector(".btn-actions").click();
    expect(document.querySelector(".dropdown").classList.contains("hidden")).to.equal(false);

    // Dispatch the failed invitation action response.
    document.querySelector("[data-invitation-request-action]").dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: { xhr: { status: 500 } },
      }),
    );

    // Verify invitation request response handling is initialized too.
    expect(env.current.swal.calls[0]).to.include({
      text: "Accept failed.",
      icon: "error",
    });
  });

  it("does not close unrelated dropdowns when initialized on the document", () => {
    // Prepare root for does not close unrelated dropdowns when initialized.
    const root = mountEventsList();
    document.body.insertAdjacentHTML("beforeend", '<div id="user-dropdown" class="dropdown"></div>');
    initializeEventsListPage(document);

    // Keep a reference to the button actions element.
    const actionsButton = root.querySelector(".btn-actions");
    const eventDropdown = root.querySelector("[data-event-actions-dropdown]");
    const userDropdown = document.getElementById("user-dropdown");

    // Unrelated dropdowns remain open.
    actionsButton.click();
    document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }));

    // Unrelated dropdowns stay open when the document is initialized.
    expect(eventDropdown.classList.contains("hidden")).to.equal(true);
    expect(userDropdown.classList.contains("hidden")).to.equal(false);
  });
});
