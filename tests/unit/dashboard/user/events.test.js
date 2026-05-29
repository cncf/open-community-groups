import { expect } from "@open-wc/testing";

import "/static/js/dashboard/user/events.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";

describe("dashboard user events", () => {
  useDashboardTestEnv({
    path: "/dashboard/user?tab=events",
  });

  it("closes the open actions dropdown when another row action menu opens", () => {
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

    const dropdowns = document.querySelectorAll("[data-user-event-actions-dropdown]");

    dropdowns[0].open = true;
    dropdowns[1].querySelector("summary").click();

    expect(dropdowns[0].open).to.equal(false);
    expect(dropdowns[1].open).to.equal(true);
  });
});
