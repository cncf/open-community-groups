import { expect } from "@open-wc/testing";

import { initializeEventsListPage } from "/static/js/dashboard/group/events-list-page.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";

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

const mountEventsList = ({ hasRelatedEvents = false } = {}) => {
  document.body.innerHTML = `
    <div id="events-list-root">
      <button class="btn-actions" data-event-id="123">Actions</button>
      <div id="dropdown-actions-123" class="dropdown hidden">
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
    const root = mountEventsList();
    initializeEventsListPage(root);

    const actionsButton = root.querySelector(".btn-actions");
    const dropdown = root.querySelector(".dropdown");

    actionsButton.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    root.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(true);
  });

  it("confirms a single-event action and rewrites the HTMX request path", async () => {
    const root = mountEventsList();
    initializeEventsListPage(root);

    const button = root.querySelector("[data-event-scoped-action]");
    button.click();
    await waitForMicrotask();

    expect(env.current.swal.calls[0].text).to.equal("Publish this event?");
    expect(env.current.htmx.triggerCalls).to.deep.equal([[button, "confirmed"]]);
    expect(button.dataset.requestScope).to.equal("this");

    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: { path: "/original" },
    });
    button.dispatchEvent(configEvent);

    expect(configEvent.detail.path).to.equal("/dashboard/group/events/123/publish");
  });

  it("confirms a series action and reports the scoped response message", async () => {
    const root = mountEventsList({ hasRelatedEvents: true });
    initializeEventsListPage(root);
    env.current.swal.setNextResult({ isConfirmed: false, isDenied: true });

    const button = root.querySelector("[data-event-scoped-action]");
    button.click();
    await waitForMicrotask();

    expect(env.current.swal.calls[0].text).to.equal("Publish this series?");
    expect(env.current.htmx.triggerCalls).to.deep.equal([[button, "confirmed"]]);

    const configEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: { path: "/original" },
    });
    button.dispatchEvent(configEvent);

    expect(configEvent.detail.path).to.equal("/dashboard/group/events/123/publish?scope=series");

    button.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: { xhr: { status: 204 } },
      }),
    );

    expect(button.dataset.requestPath).to.equal(undefined);
    expect(button.dataset.requestScope).to.equal(undefined);
    expect(env.current.swal.calls[1].text).to.equal("Published events");
  });
});
