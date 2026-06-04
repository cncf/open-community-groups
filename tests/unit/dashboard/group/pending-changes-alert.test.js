import { expect } from "@open-wc/testing";

import { initializePendingChangesAlert } from "/static/js/dashboard/group/pending-changes-alert.js";
import {
  waitForAnimationFrames,
  waitForMicrotask,
} from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

describe("pending changes alert", () => {
  let swal;
  let htmx;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
    htmx = mockHtmx();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
    htmx.restore();
  });

  it("tracks dirty state for form changes and shows the alert", async () => {
    // Render the DOM fixture for tracking dirty state for form changes and shows.
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <form id="event-form">
        <input name="title" value="Original title" />
      </form>
    `;

    // Prepare API for tracking dirty state for form changes and shows the alert.
    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["event-form"],
    });

    // Wait for async UI before checking it tracks dirty state for form changes and shows.
    await waitForAnimationFrames();

    // Form changes mark the page dirty and show the alert.
    expect(api.hasPendingChanges()).to.equal(false);
    expect(
      document.getElementById("pending-alert")?.classList.contains("hidden"),
    ).to.equal(true);

    // Read the form and alert state after the first change.
    const titleInput = document.querySelector(
      '#event-form input[name="title"]',
    );
    titleInput.value = "Updated title";
    titleInput.dispatchEvent(new Event("input", { bubbles: true }));

    // Wait for async UI before checking it tracks dirty state for form changes and shows.
    await waitForAnimationFrames();

    // Resetting the form clears dirty state and hides the alert.
    expect(api.hasPendingChanges()).to.equal(true);
    expect(
      document.getElementById("pending-alert")?.classList.contains("hidden"),
    ).to.equal(false);
  });

  it("tracks dirty state across multiple forms including payment-only changes", async () => {
    // Render the DOM fixture for tracking dirty state across multiple forms.
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <form id="details-form">
        <input name="title" value="Original title" />
      </form>
      <form id="payments-form">
        <input name="payment_currency_code" value="EUR" />
      </form>
    `;

    // Prepare API for tracking dirty state across multiple forms including.
    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["details-form", "payments-form"],
    });

    // Wait for async UI before checking it tracks dirty state across multiple forms.
    await waitForAnimationFrames();

    // Read the forms and payment fields under dirty-state tracking.
    const currencyInput = document.querySelector(
      '#payments-form input[name="payment_currency_code"]',
    );
    currencyInput.value = "USD";
    currencyInput.dispatchEvent(new Event("change", { bubbles: true }));

    // Wait for async UI before checking it tracks dirty state across multiple forms.
    await waitForAnimationFrames();

    // Dirty state includes payment-only changes across forms.
    expect(api.hasPendingChanges()).to.equal(true);
    expect(
      document.getElementById("pending-alert")?.classList.contains("hidden"),
    ).to.equal(false);
  });

  it("ignores fields inside pending-changes-ignore containers", async () => {
    // Render the DOM fixture for ignoring fields inside pending-changes-ignore.
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <form id="event-form">
        <input name="title" value="Original title" />
        <div data-pending-changes-ignore>
          <input name="temporary_note" value="unchanged" />
        </div>
      </form>
    `;

    // Prepare API for ignoring fields inside pending-changes-ignore containers.
    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["event-form"],
    });

    // Wait for async UI before checking it ignores fields inside pending-changes-ignore.
    await waitForAnimationFrames();

    // Read the ignored and tracked fields.
    const ignoredInput = document.querySelector(
      '#event-form input[name="temporary_note"]',
    );
    ignoredInput.value = "updated";
    ignoredInput.dispatchEvent(new Event("input", { bubbles: true }));

    // Wait for async UI before checking it ignores fields inside pending-changes-ignore.
    await waitForAnimationFrames();

    // Ignored fields do not mark the page dirty.
    expect(api.hasPendingChanges()).to.equal(false);
    expect(
      document.getElementById("pending-alert")?.classList.contains("hidden"),
    ).to.equal(true);
  });

  it("asks for confirmation when cancelling with pending changes", async () => {
    // Render the DOM fixture for asking for confirmation when cancelling.
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <button id="cancel-button" type="button">Cancel</button>
      <form id="event-form">
        <input name="title" value="Original title" />
      </form>
    `;

    // Prepare API for asking for confirmation when cancelling with pending changes.
    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["event-form"],
      cancelButtonId: "cancel-button",
      confirmMessage: "Discard pending changes?",
      confirmText: "Discard",
    });

    // Wait for async UI before checking it asks for confirmation when cancelling.
    await waitForAnimationFrames();

    // Read the cancel button before confirming pending changes.
    const titleInput = document.querySelector(
      '#event-form input[name="title"]',
    );
    titleInput.value = "Updated title";
    titleInput.dispatchEvent(new Event("input", { bubbles: true }));

    // Wait for async UI before checking it asks for confirmation when cancelling.
    await waitForAnimationFrames();

    // Cancelling with no changes does not show confirmation.
    document.getElementById("cancel-button")?.click();
    await waitForMicrotask();

    // Cancelling with pending changes asks for confirmation.
    expect(api.hasPendingChanges()).to.equal(true);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Discard pending changes?");
    expect(swal.calls[0].confirmButtonText).to.equal("Discard");
    expect(htmx.triggerCalls).to.deep.equal([["#cancel-button", "confirmed"]]);
  });
});
