import { expect } from "@open-wc/testing";

import { initializeEventsListPage } from "/static/js/dashboard/group/events-list-page.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";

// Prepare scoped action markup to check it covers the current behavior.
const scopedActionMarkup = ({ hasRelatedEvents = false } = {}) => `
  <button
    id="publish-event-123"
    data-event-scoped-action
    data-action-url="/dashboard/group/events/123/publish"
    data-has-related-events="${String(hasRelatedEvents)}"
    data-current-scope-text="Only this event"
    data-series-scope-text="All in series"
    data-confirm-text="Yes"
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
      <button class="btn-actions" data-event-id="123">Actions</button>
      <div id="dropdown-actions-123" data-event-actions-dropdown class="dropdown hidden">
        ${scopedActionMarkup({ hasRelatedEvents })}
      </div>
    </div>
  `;
  return document.getElementById("events-list-root");
};

describe("events list page", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/group?tab=events",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
  });

  it("toggles event action dropdowns with delegated handlers", () => {
    // Prepare root to check it toggles event action dropdowns with delegated handlers.
    const root = mountEventsList();
    initializeEventsListPage(root);

    // Read the btn actions element to check it toggles event action dropdowns.
    const actionsButton = root.querySelector(".btn-actions");
    const dropdown = root.querySelector(".dropdown");

    // Trigger the user interaction to check it toggles event action dropdowns.
    actionsButton.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    // Dispatch the event event to check it toggles event action dropdowns with delegated.
    root.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(true);
  });

  it("confirms a single-event action and rewrites the HTMX request path", async () => {
    // Prepare root to check it confirms a single-event action and rewrites the HTMX.
    const root = mountEventsList();
    initializeEventsListPage(root);

    // Read the event scoped action element to check it confirms a single-event action.
    const button = root.querySelector("[data-event-scoped-action]");
    button.click();
    await waitForMicrotask();

    // Confirm it confirms a single-event action and rewrites the HTMX request path.
    expect(env.current.swal.calls[0].text).to.equal("Publish this event?");
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      [button, "confirmed"],
    ]);
    expect(button.dataset.requestScope).to.equal("this");

    // Prepare config event to check it confirms a single-event action and rewrites.
    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: { path: "/original" },
    });
    button.dispatchEvent(configEvent);

    // Confirm it confirms a single-event action and rewrites the HTMX request path.
    expect(configEvent.detail.path).to.equal(
      "/dashboard/group/events/123/publish",
    );
  });

  it("confirms a series action and reports the scoped response message", async () => {
    // Prepare root to check it confirms a series action and reports the scoped response.
    const root = mountEventsList({ hasRelatedEvents: true });
    initializeEventsListPage(root);
    env.current.swal.setNextResult({ isConfirmed: false, isDenied: true });

    // Read the event scoped action element to check it confirms a series action.
    const button = root.querySelector("[data-event-scoped-action]");
    button.click();
    await waitForMicrotask();

    // Confirm it confirms a series action and reports the scoped response message.
    expect(env.current.swal.calls[0].text).to.equal("Publish this series?");
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      [button, "confirmed"],
    ]);

    // Prepare config event to check it confirms a series action and reports the scoped.
    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: { path: "/original" },
    });
    button.dispatchEvent(configEvent);

    // Confirm it confirms a series action and reports the scoped response message.
    expect(configEvent.detail.path).to.equal(
      "/dashboard/group/events/123/publish?scope=series",
    );

    // Dispatch the event event to check it confirms a series action and reports.
    button.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: { xhr: { status: 204 } },
      }),
    );

    // Confirm it confirms a series action and reports the scoped response message.
    expect(button.dataset.requestPath).to.equal(undefined);
    expect(button.dataset.requestScope).to.equal(undefined);
    expect(env.current.swal.calls[1].text).to.equal("Published events");
  });

  it("shows an error alert for failed invitation request actions", () => {
    // Prepare root to check it shows an error alert for failed invitation request.
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

    // Dispatch the event event to check it shows an error alert for failed invitation.
    root.querySelector("[data-invitation-request-action]").dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: { xhr: { status: 500 } },
      }),
    );

    // Confirm it shows an error alert for failed invitation request actions.
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      text: "Accept failed.",
      icon: "error",
    });
  });

  it("does not close unrelated dropdowns when initialized on the document", () => {
    // Prepare root to check it does not close unrelated dropdowns when initialized.
    const root = mountEventsList();
    document.body.insertAdjacentHTML(
      "beforeend",
      '<div id="user-dropdown" class="dropdown"></div>',
    );
    initializeEventsListPage(document);

    // Read the btn actions element to check it does not close unrelated dropdowns.
    const actionsButton = root.querySelector(".btn-actions");
    const eventDropdown = root.querySelector("[data-event-actions-dropdown]");
    const userDropdown = document.getElementById("user-dropdown");

    // Trigger the user interaction to check it does not close unrelated dropdowns.
    actionsButton.click();
    document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }));

    // Confirm it does not close unrelated dropdowns when initialized on the document.
    expect(eventDropdown.classList.contains("hidden")).to.equal(true);
    expect(userDropdown.classList.contains("hidden")).to.equal(false);
  });
});
