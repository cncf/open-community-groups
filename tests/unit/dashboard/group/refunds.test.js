import { expect } from "@open-wc/testing";

import { initializeRefundRecovery } from "/static/js/dashboard/group/refunds.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";

describe("dashboard group refund recovery", () => {
  useDashboardTestEnv({
    path: "/dashboard/group?tab=refunds",
    withScroll: true,
  });

  const renderRecoveryFixture = () => {
    document.body.innerHTML = `
      <div id="dashboard-content">
        <button
          type="button"
          data-refund-recovery-open
          data-event-purchase-id="purchase-123"
          data-refund-attendee="Alice"
          data-refund-event="Community meetup"
        >
          Complete recovery
        </button>
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
});
