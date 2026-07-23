import { expect } from "@open-wc/testing";

import { initializeRefundRecovery } from "/static/js/dashboard/group/refunds.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";

describe("dashboard group refunds", () => {
  useDashboardTestEnv({
    path: "/dashboard/group?tab=refunds",
    withScroll: true,
  });

  const renderRecoveryFixture = () => {
    document.body.innerHTML = `
      <div id="dashboard-content">
        <form id="refund-filters" action="/dashboard/group" hx-get="/dashboard/group/refunds">
          <input name="tab" value="refunds" />
          <input id="refund-search" name="ts_query" value="Alice" />
          <button type="button" data-refund-search-clear hx-get="/dashboard/group/refunds">
            Clear search
          </button>
          <select name="event_id"><option value="event-1" selected>Event one</option></select>
          <select id="refund-view" name="view"><option value="active" selected>Active</option></select>
        </form>
        <details data-actions-menu open>
          <summary>Refund actions</summary>
          <button
            type="button"
            data-refund-approve-open
            data-refund-approve-url="/dashboard/group/refunds/purchase-123/approve"
            data-refund-attendee="Alice"
            data-refund-event="Community meetup"
            data-refund-reason="Schedule conflict"
          >
            Approve refund
          </button>
          <button
            type="button"
            data-refund-reject-open
            data-refund-reject-url="/dashboard/group/refunds/purchase-123/reject"
            data-refund-attendee="Alice"
            data-refund-event="Community meetup"
            data-refund-reason="Schedule conflict"
          >
            Reject refund
          </button>
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
        <div id="refund-approve-modal" class="hidden" aria-hidden="true">
          <button id="close-refund-approve-modal" type="button">Close</button>
          <div id="overlay-refund-approve-modal"></div>
          <form id="refund-approve-form">
            <div id="refund-approve-attendee"></div>
            <div id="refund-approve-event"></div>
            <div id="refund-approve-reason"></div>
            <textarea id="refund-approve-review-note" name="review_note" autofocus></textarea>
            <button id="cancel-refund-approve-modal" type="button">Cancel</button>
          </form>
        </div>
        <div id="refund-reject-modal" class="hidden" aria-hidden="true">
          <button id="close-refund-reject-modal" type="button">Close</button>
          <div id="overlay-refund-reject-modal"></div>
          <form id="refund-reject-form">
            <div id="refund-reject-attendee"></div>
            <div id="refund-reject-event"></div>
            <div id="refund-reject-reason"></div>
            <textarea id="refund-review-note" name="review_note" autofocus></textarea>
            <button id="cancel-refund-reject-modal" type="button">Cancel</button>
          </form>
        </div>
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

  it("collects and preserves an optional approval note", () => {
    // Render one pending refund and open its approval modal.
    const originalHtmx = window.htmx;
    const processCalls = [];
    window.htmx = {
      process: (element) => processCalls.push(element?.id),
    };
    renderRecoveryFixture();
    document.getElementById("refund-approve-review-note").value = "stale";

    try {
      document.querySelector("[data-refund-approve-open]")?.click();
      const form = document.getElementById("refund-approve-form");
      const modal = document.getElementById("refund-approve-modal");
      const reviewNote = document.getElementById("refund-approve-review-note");

      // Verify the selected context, endpoint, reset state, and focus contract.
      expect(modal?.classList.contains("hidden")).to.equal(false);
      expect(form?.getAttribute("hx-put")).to.equal("/dashboard/group/refunds/purchase-123/approve");
      expect(document.getElementById("refund-approve-attendee")?.textContent).to.equal("Alice");
      expect(document.getElementById("refund-approve-event")?.textContent).to.equal("Community meetup");
      expect(document.getElementById("refund-approve-reason")?.textContent).to.equal("Schedule conflict");
      expect(reviewNote.value).to.equal("");
      expect(document.activeElement).to.equal(reviewNote);
      expect(processCalls).to.deep.equal(["refund-approve-form"]);

      // Trim the review note and preserve it when the request fails.
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

      // Close after a successful request.
      dispatchHtmxAfterRequest(form, { status: 204 });
      expect(modal?.classList.contains("hidden")).to.equal(true);
    } finally {
      window.htmx = originalHtmx;
    }
  });

  it("populates and opens the rejection modal for the selected refund", () => {
    // Render one pending refund and prepare stale rejection data.
    const originalHtmx = window.htmx;
    const processCalls = [];
    window.htmx = {
      process: (element) => processCalls.push(element?.id),
    };
    renderRecoveryFixture();
    document.getElementById("refund-review-note").value = "stale";

    try {
      // Open the selected refund rejection.
      document.querySelector("[data-refund-reject-open]")?.click();

      // Verify the selected context and endpoint populate the modal.
      const form = document.getElementById("refund-reject-form");
      expect(document.getElementById("refund-reject-modal")?.classList.contains("hidden")).to.equal(false);
      expect(form?.getAttribute("hx-put")).to.equal("/dashboard/group/refunds/purchase-123/reject");
      expect(document.getElementById("refund-reject-attendee")?.textContent).to.equal("Alice");
      expect(document.getElementById("refund-reject-event")?.textContent).to.equal("Community meetup");
      expect(document.getElementById("refund-reject-reason")?.textContent).to.equal("Schedule conflict");
      expect(document.getElementById("refund-review-note")?.value).to.equal("");
      expect(document.querySelector("[data-actions-menu]")?.open).to.equal(false);
      expect(document.activeElement).to.equal(document.getElementById("refund-review-note"));
      expect(processCalls).to.deep.equal(["refund-reject-form"]);
    } finally {
      window.htmx = originalHtmx;
    }
  });

  it("explains when the refund request has no reason", () => {
    // Render a refund request without a reason.
    renderRecoveryFixture();
    const rejectTrigger = document.querySelector("[data-refund-reject-open]");
    delete rejectTrigger.dataset.refundReason;

    // Open the rejection modal and verify the empty reason state.
    rejectTrigger.click();
    expect(document.getElementById("refund-reject-reason")?.textContent).to.equal(
      "No reason provided.",
    );
  });

  it("omits a blank rejection note and trims a provided note", () => {
    // Open the rejection modal for the selected refund.
    renderRecoveryFixture();
    document.querySelector("[data-refund-reject-open]")?.click();
    const form = document.getElementById("refund-reject-form");
    const reviewNote = document.getElementById("refund-review-note");

    // Omit a whitespace-only optional note.
    reviewNote.value = "   ";
    const blankEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters: { review_note: "   " },
        unfilteredParameters: { review_note: "   " },
      },
    });
    form.dispatchEvent(blankEvent);
    expect(blankEvent.detail.parameters).not.to.have.property("review_note");
    expect(blankEvent.detail.unfilteredParameters).not.to.have.property("review_note");

    // Trim a provided review note before submission.
    reviewNote.value = "  Duplicate purchase  ";
    const filledEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters: { review_note: "  Duplicate purchase  " },
        unfilteredParameters: { review_note: "  Duplicate purchase  " },
      },
    });
    form.dispatchEvent(filledEvent);
    expect(reviewNote.value).to.equal("Duplicate purchase");
    expect(filledEvent.detail.parameters.review_note).to.equal("Duplicate purchase");
    expect(filledEvent.detail.unfilteredParameters.review_note).to.equal("Duplicate purchase");
  });

  it("preserves the review note on failure and closes after successful rejection", () => {
    // Open the rejection modal with a review note.
    const root = renderRecoveryFixture();
    const actionsSummary = document.querySelector("[data-actions-menu] summary");
    document.querySelector("[data-refund-reject-open]")?.click();
    const form = document.getElementById("refund-reject-form");
    const modal = document.getElementById("refund-reject-modal");
    const reviewNote = document.getElementById("refund-review-note");
    reviewNote.value = "Duplicate purchase";

    // Keep recoverable work visible after a failed request.
    dispatchHtmxAfterRequest(form, { status: 422 });
    expect(modal?.classList.contains("hidden")).to.equal(false);
    expect(reviewNote.value).to.equal("Duplicate purchase");

    // Close after success and focus the refreshed refunds search.
    dispatchHtmxAfterRequest(form, { status: 204 });
    expect(modal?.classList.contains("hidden")).to.equal(true);
    expect(document.activeElement).to.equal(actionsSummary);
    root.innerHTML = '<input id="refund-search" type="search" />';
    dispatchHtmxAfterSwap(root);
    expect(document.activeElement).to.equal(document.getElementById("refund-search"));
  });

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

  it("focuses the refreshed refunds after successful recovery completion", () => {
    // Open the recovery modal.
    const root = renderRecoveryFixture();
    document.querySelector("[data-refund-recovery-open]")?.click();
    const form = document.getElementById("refund-recovery-form");

    // A successful HTMX request closes the modal before refreshing the refunds.
    dispatchHtmxAfterRequest(form, { status: 204 });
    expect(document.getElementById("refund-recovery-modal")?.classList.contains("hidden")).to.equal(true);
    expect(document.body.dataset.modalOpenCount).to.equal("0");

    // The refreshed search replaces the removed action and receives focus.
    root.innerHTML = '<input id="refund-search" type="search" />';
    dispatchHtmxAfterSwap(root);
    expect(document.activeElement).to.equal(document.getElementById("refund-search"));
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
    const clearButton = document.querySelector("[data-refund-search-clear]");
    const filterForm = document.getElementById("refund-filters");

    // Configure the full dashboard URL for filter submissions.
    filterForm.dispatchEvent(new CustomEvent("htmx:configRequest", { bubbles: true }));
    expect(filterForm.getAttribute("hx-push-url")).to.equal(
      "/dashboard/group?tab=refunds&ts_query=Alice&event_id=event-1&view=active",
    );

    // Restore focus when a swapped navigation control has no replacement.
    clearButton.dispatchEvent(new CustomEvent("htmx:configRequest", { bubbles: true }));
    document.body.focus();
    dispatchHtmxAfterSwap(root);
    expect(clearButton.getAttribute("hx-push-url")).to.equal(
      "/dashboard/group?tab=refunds&event_id=event-1&view=active",
    );
    expect(document.activeElement).to.equal(document.getElementById("refund-search"));
  });

  it("restores the focused refund filter after a partial swap", () => {
    // Focus a filter before its form starts HTMX navigation.
    const root = renderRecoveryFixture();
    const filterForm = document.getElementById("refund-filters");
    document.getElementById("refund-view").focus();
    filterForm.dispatchEvent(new CustomEvent("htmx:configRequest", { bubbles: true }));

    // Replace the form and verify focus moves to the corresponding control.
    root.innerHTML = '<select id="refund-view"><option>Active</option></select>';
    dispatchHtmxAfterSwap(root);
    expect(document.activeElement).to.equal(document.getElementById("refund-view"));
  });
});
