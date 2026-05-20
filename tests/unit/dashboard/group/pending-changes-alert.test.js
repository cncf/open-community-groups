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
    // Build the DOM fixture to check it tracks dirty state for form changes and shows.
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <form id="event-form">
        <input name="title" value="Original title" />
      </form>
    `;

    // Prepare api to check it tracks dirty state for form changes and shows the alert.
    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["event-form"],
    });

    // Wait for async UI before checking it tracks dirty state for form changes and shows.
    await waitForAnimationFrames();

    // Confirm it tracks dirty state for form changes and shows the alert.
    expect(api.hasPendingChanges()).to.equal(false);
    expect(
      document.getElementById("pending-alert")?.classList.contains("hidden"),
    ).to.equal(true);

    // Read the DOM to check it tracks dirty state for form changes and shows the alert.
    const titleInput = document.querySelector(
      '#event-form input[name="title"]',
    );
    titleInput.value = "Updated title";
    titleInput.dispatchEvent(new Event("input", { bubbles: true }));

    // Wait for async UI before checking it tracks dirty state for form changes and shows.
    await waitForAnimationFrames();

    // Confirm it tracks dirty state for form changes and shows the alert.
    expect(api.hasPendingChanges()).to.equal(true);
    expect(
      document.getElementById("pending-alert")?.classList.contains("hidden"),
    ).to.equal(false);
  });

  it("tracks dirty state across multiple forms including payment-only changes", async () => {
    // Build the DOM fixture to check it tracks dirty state across multiple forms.
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <form id="details-form">
        <input name="title" value="Original title" />
      </form>
      <form id="payments-form">
        <input name="payment_currency_code" value="EUR" />
      </form>
    `;

    // Prepare api to check it tracks dirty state across multiple forms including.
    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["details-form", "payments-form"],
    });

    // Wait for async UI before checking it tracks dirty state across multiple forms.
    await waitForAnimationFrames();

    // Read the DOM to check it tracks dirty state across multiple forms including.
    const currencyInput = document.querySelector(
      '#payments-form input[name="payment_currency_code"]',
    );
    currencyInput.value = "USD";
    currencyInput.dispatchEvent(new Event("change", { bubbles: true }));

    // Wait for async UI before checking it tracks dirty state across multiple forms.
    await waitForAnimationFrames();

    // Confirm it tracks dirty state across multiple forms including payment-only changes.
    expect(api.hasPendingChanges()).to.equal(true);
    expect(
      document.getElementById("pending-alert")?.classList.contains("hidden"),
    ).to.equal(false);
  });

  it("ignores fields inside pending-changes-ignore containers", async () => {
    // Build the DOM fixture to check it ignores fields inside pending-changes-ignore.
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <form id="event-form">
        <input name="title" value="Original title" />
        <div data-pending-changes-ignore>
          <input name="temporary_note" value="unchanged" />
        </div>
      </form>
    `;

    // Prepare api to check it ignores fields inside pending-changes-ignore containers.
    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["event-form"],
    });

    // Wait for async UI before checking it ignores fields inside pending-changes-ignore.
    await waitForAnimationFrames();

    // Read the DOM to check it ignores fields inside pending-changes-ignore containers.
    const ignoredInput = document.querySelector(
      '#event-form input[name="temporary_note"]',
    );
    ignoredInput.value = "updated";
    ignoredInput.dispatchEvent(new Event("input", { bubbles: true }));

    // Wait for async UI before checking it ignores fields inside pending-changes-ignore.
    await waitForAnimationFrames();

    // Confirm it ignores fields inside pending-changes-ignore containers.
    expect(api.hasPendingChanges()).to.equal(false);
    expect(
      document.getElementById("pending-alert")?.classList.contains("hidden"),
    ).to.equal(true);
  });

  it("asks for confirmation when cancelling with pending changes", async () => {
    // Build the DOM fixture to check it asks for confirmation when cancelling.
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <button id="cancel-button" type="button">Cancel</button>
      <form id="event-form">
        <input name="title" value="Original title" />
      </form>
    `;

    // Prepare api to check it asks for confirmation when cancelling with pending changes.
    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["event-form"],
      cancelButtonId: "cancel-button",
      confirmMessage: "Discard pending changes?",
      confirmText: "Discard",
    });

    // Wait for async UI before checking it asks for confirmation when cancelling.
    await waitForAnimationFrames();

    // Read the DOM to check it asks for confirmation when cancelling with pending.
    const titleInput = document.querySelector(
      '#event-form input[name="title"]',
    );
    titleInput.value = "Updated title";
    titleInput.dispatchEvent(new Event("input", { bubbles: true }));

    // Wait for async UI before checking it asks for confirmation when cancelling.
    await waitForAnimationFrames();

    // Trigger the user interaction to check it asks for confirmation when cancelling.
    document.getElementById("cancel-button")?.click();
    await waitForMicrotask();

    // Confirm it asks for confirmation when cancelling with pending changes.
    expect(api.hasPendingChanges()).to.equal(true);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Discard pending changes?");
    expect(swal.calls[0].confirmButtonText).to.equal("Discard");
    expect(htmx.triggerCalls).to.deep.equal([["#cancel-button", "confirmed"]]);
  });
});
