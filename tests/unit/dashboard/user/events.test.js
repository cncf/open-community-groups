import { expect } from "@open-wc/testing";

import "/static/js/dashboard/user/events.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";

describe("dashboard user events", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/user?tab=events",
    withHtmx: true,
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
});
