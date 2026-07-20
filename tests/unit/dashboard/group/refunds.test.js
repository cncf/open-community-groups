import { expect } from "@open-wc/testing";

import { initializeRefundRecovery } from "/static/js/dashboard/group/refunds.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";

describe("dashboard group refund recovery", () => {
  useDashboardTestEnv({
    path: "/dashboard/group?tab=refunds",
    withScroll: true,
  });

  const renderRecoveryFixture = () => {
    document.body.innerHTML = `
      <div id="dashboard-content">
        <nav>
          <a
            id="refund-view-0"
            href="/dashboard/group?tab=refunds&view=needs-attention"
            hx-get="/dashboard/group/refunds?view=needs-attention"
          >
            Needs attention
          </a>
          <a
            data-refund-clear
            href="/dashboard/group?tab=refunds&view=active"
            hx-get="/dashboard/group/refunds?view=active"
          >
            Clear
          </a>
        </nav>
        <form id="refund-filters" action="/dashboard/group" hx-get="/dashboard/group/refunds">
          <input name="tab" value="refunds" />
          <input name="view" value="active" />
          <input id="refund-search" name="ts_query" value="Alice" />
          <select name="event_id"><option value="" selected>All events</option></select>
          <button id="refund-filter-apply" type="submit">Apply</button>
        </form>
        <details data-actions-menu open>
          <summary>Refund actions</summary>
          <button
            type="button"
            data-refund-recovery-open
            data-event-purchase-id="purchase-123"
            data-refund-attendee="Alice"
            data-refund-event="Community meetup"
          >
            Complete recovery
          </button>
        </details>
        <div id="refund-recovery-modal" class="hidden" aria-hidden="true">
          <button id="close-refund-recovery-modal" type="button">Close</button>
          <div id="overlay-refund-recovery-modal"></div>
          <form id="refund-recovery-form">
            <input id="refund-recovery-purchase-id" name="event_purchase_id" />
            <input id="refund-recovery-reference" name="recovery_reference" />
            <div id="refund-recovery-attendee"></div>
            <div id="refund-recovery-event"></div>
            <button id="cancel-refund-recovery-modal" type="button">Cancel</button>
          </form>
        </div>
      </div>
    `;

    const root = document.getElementById("dashboard-content");
    initializeRefundRecovery(root);
    return root;
  };

  it("populates and opens the modal for the selected recovery", () => {
    // Render and open one recoverable refund.
    renderRecoveryFixture();
    document.getElementById("refund-recovery-reference").value = "stale";
    document.querySelector("[data-refund-recovery-open]")?.click();

    // The selected purchase context is shown and stale form data is reset.
    expect(document.getElementById("refund-recovery-modal")?.classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("refund-recovery-purchase-id")?.value).to.equal("purchase-123");
    expect(document.getElementById("refund-recovery-attendee")?.textContent).to.equal("Alice");
    expect(document.getElementById("refund-recovery-event")?.textContent).to.equal("Community meetup");
    expect(document.getElementById("refund-recovery-reference")?.value).to.equal("");
    expect(document.querySelector("[data-actions-menu]")?.open).to.equal(false);
    expect(document.activeElement).to.equal(document.getElementById("close-refund-recovery-modal"));
  });

  it("closes the modal after successful recovery completion", () => {
    // Open the recovery modal.
    renderRecoveryFixture();
    document.querySelector("[data-refund-recovery-open]")?.click();
    const form = document.getElementById("refund-recovery-form");

    // A successful HTMX request closes the modal and restores body scroll.
    dispatchHtmxAfterRequest(form, { status: 204 });
    expect(document.getElementById("refund-recovery-modal")?.classList.contains("hidden")).to.equal(true);
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.activeElement).to.equal(document.querySelector("[data-actions-menu] summary"));
  });

  it("keeps the modal open after a failed recovery request", () => {
    // Open the recovery modal.
    renderRecoveryFixture();
    document.querySelector("[data-refund-recovery-open]")?.click();
    const form = document.getElementById("refund-recovery-form");

    // Failed validation leaves the evidence visible for correction.
    dispatchHtmxAfterRequest(form, { status: 422 });
    expect(document.getElementById("refund-recovery-modal")?.classList.contains("hidden")).to.equal(false);
  });

  it("preserves refund navigation history and focus across partial swaps", () => {
    // Render refund navigation and prepare the requested filter state.
    const root = renderRecoveryFixture();
    const viewLink = document.getElementById("refund-view-0");
    const clearLink = document.querySelector("[data-refund-clear]");
    const filterForm = document.getElementById("refund-filters");

    // Configure full dashboard URLs for links and filter submissions.
    viewLink.dispatchEvent(new CustomEvent("htmx:configRequest", { bubbles: true }));
    filterForm.dispatchEvent(new CustomEvent("htmx:configRequest", { bubbles: true }));
    expect(viewLink.getAttribute("hx-push-url")).to.equal(
      "/dashboard/group?tab=refunds&view=needs-attention",
    );
    expect(filterForm.getAttribute("hx-push-url")).to.equal(
      "/dashboard/group?tab=refunds&view=active&ts_query=Alice",
    );

    // Restore focus when a swapped navigation control has no replacement.
    clearLink.dispatchEvent(new CustomEvent("htmx:configRequest", { bubbles: true }));
    document.body.focus();
    dispatchHtmxAfterSwap(root);
    expect(clearLink.getAttribute("hx-push-url")).to.equal(
      "/dashboard/group?tab=refunds&view=active",
    );
    expect(document.activeElement).to.equal(document.getElementById("refund-search"));
  });
});
