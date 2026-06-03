import { expect } from "@open-wc/testing";

import "/static/js/dashboard/user/events.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";

describe("dashboard user events", () => {
  useDashboardTestEnv({
    path: "/dashboard/user?tab=events",
  });

  it("closes the open actions dropdown when another row action menu opens", () => {
    // Render two user event action dropdowns.
    document.body.innerHTML = `
      <details data-user-event-actions-dropdown>
        <summary>First actions</summary>
        <button type="button">First action</button>
      </details>
      <details data-user-event-actions-dropdown>
        <summary>Second actions</summary>
        <button type="button">Second action</button>
      </details>
    `;

    // Set up dropdowns.
    const dropdowns = document.querySelectorAll("[data-user-event-actions-dropdown]");

    dropdowns[0].open = true;
    dropdowns[1].querySelector("summary").click();

    // Assert that the flag is disabled.
    expect(dropdowns[0].open).to.equal(false);
    expect(dropdowns[1].open).to.equal(true);
  });

  it("closes open action dropdowns when clicking outside", () => {
    // Render an open user event action dropdown.
    document.body.innerHTML = `
      <details data-user-event-actions-dropdown open>
        <summary>Actions</summary>
        <button type="button">Action</button>
      </details>
      <button type="button" id="outside-button">Outside</button>
    `;

    // Set up dropdown.
    const dropdown = document.querySelector("[data-user-event-actions-dropdown]");

    // Click the outside button button.
    document.getElementById("outside-button").click();

    // Assert that the flag is disabled.
    expect(dropdown.open).to.equal(false);
  });
});
