import { expect } from "@open-wc/testing";

import { initializeAuditLogs } from "/static/js/dashboard/audit-logs.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard audit logs", () => {
  const buildAuditLogsFixture = () => {
    document.body.innerHTML = `
      <button id="open-audit-log-filters-modal" type="button"></button>
      <span id="audit-log-filters-active-indicator" class="hidden"></span>
      <div id="audit-log-filters-modal" class="hidden">
        <div id="overlay-audit-log-filters-modal"></div>
        <button id="close-audit-log-filters-modal" type="button"></button>
        <form id="audit-log-filters-form">
          <select id="audit-action" name="action">
            <option value="">All actions</option>
            <option value="member-added" selected>Member added</option>
          </select>
          <input id="audit-actor" name="actor" value="">
          <input id="audit-date-from" name="date_from" value="">
          <input id="audit-date-to" name="date_to" value="">
          <a id="reset-audit-log-filters" href="/dashboard/logs">Reset</a>
        </form>
      </div>
      <div data-audit-log-details-group>
        <button
          type="button"
          data-audit-log-details-trigger
          aria-controls="audit-log-details-1"
          aria-expanded="false"
        ></button>
        <div id="audit-log-details-1" data-audit-log-details-card class="hidden"></div>
      </div>
    `;
  };

  beforeEach(() => {
    resetDom();
    buildAuditLogsFixture();
  });

  afterEach(() => {
    resetDom();
  });

  it("initializes filter modal controls once", () => {
    // Run initialization twice to verify modal event handlers are not duplicated.
    initializeAuditLogs();
    initializeAuditLogs();

    // Verify active filters are reflected on the filter button.
    expect(
      document
        .getElementById("audit-log-filters-active-indicator")
        .classList.contains("hidden"),
    ).to.equal(false);
    expect(
      document
        .getElementById("open-audit-log-filters-modal")
        .getAttribute("aria-pressed"),
    ).to.equal("true");

    // Open and close the modal to verify one click produces one toggle.
    document.getElementById("open-audit-log-filters-modal").click();
    expect(
      document
        .getElementById("audit-log-filters-modal")
        .classList.contains("hidden"),
    ).to.equal(false);

    document.getElementById("close-audit-log-filters-modal").click();
    expect(
      document
        .getElementById("audit-log-filters-modal")
        .classList.contains("hidden"),
    ).to.equal(true);
  });

  it("toggles details popovers from the document handlers", () => {
    // Initialize details popover behavior.
    initializeAuditLogs();

    const trigger = document.querySelector("[data-audit-log-details-trigger]");
    const card = document.getElementById("audit-log-details-1");

    // Open the details popover from its trigger.
    trigger.click();
    expect(trigger.getAttribute("aria-expanded")).to.equal("true");
    expect(card.classList.contains("hidden")).to.equal(false);

    // Close the details popover from an outside click.
    document.body.click();
    expect(trigger.getAttribute("aria-expanded")).to.equal("false");
    expect(card.classList.contains("hidden")).to.equal(true);
  });

  it("initializes swapped audit log content on htmx load", () => {
    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.body);

    // Verify the swapped content is bound without calling the initializer directly.
    expect(document.getElementById("audit-log-filters-modal").dataset.bound).to.equal(
      "true",
    );
    expect(
      document
        .querySelector("[data-audit-log-details-group]")
        .getAttribute("data-audit-log-hover-bound"),
    ).to.equal("true");
  });
});
