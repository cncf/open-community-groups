import { expect } from "@open-wc/testing";

import { initializePendingChangesAlert } from "/static/js/dashboard/group/pending-changes-alert.js";
import { waitForAnimationFrames, waitForMicrotask } from "/tests/unit/test-utils/async.js";
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
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <form id="event-form">
        <input name="title" value="Original title" />
      </form>
    `;

    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["event-form"],
    });

    await waitForAnimationFrames();

    expect(api.hasPendingChanges()).to.equal(false);
    expect(document.getElementById("pending-alert")?.classList.contains("hidden")).to.equal(true);

    const titleInput = document.querySelector('#event-form input[name="title"]');
    titleInput.value = "Updated title";
    titleInput.dispatchEvent(new Event("input", { bubbles: true }));

    await waitForAnimationFrames();

    expect(api.hasPendingChanges()).to.equal(true);
    expect(document.getElementById("pending-alert")?.classList.contains("hidden")).to.equal(false);
  });

  it("tracks dirty state across multiple forms including payment-only changes", async () => {
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <form id="details-form">
        <input name="title" value="Original title" />
      </form>
      <form id="payments-form">
        <input name="payment_currency_code" value="EUR" />
      </form>
    `;

    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["details-form", "payments-form"],
    });

    await waitForAnimationFrames();

    const currencyInput = document.querySelector('#payments-form input[name="payment_currency_code"]');
    currencyInput.value = "USD";
    currencyInput.dispatchEvent(new Event("change", { bubbles: true }));

    await waitForAnimationFrames();

    expect(api.hasPendingChanges()).to.equal(true);
    expect(document.getElementById("pending-alert")?.classList.contains("hidden")).to.equal(false);
  });

  it("ignores fields inside pending-changes-ignore containers", async () => {
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <form id="event-form">
        <input name="title" value="Original title" />
        <div data-pending-changes-ignore>
          <input name="temporary_note" value="unchanged" />
        </div>
      </form>
    `;

    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["event-form"],
    });

    await waitForAnimationFrames();

    const ignoredInput = document.querySelector('#event-form input[name="temporary_note"]');
    ignoredInput.value = "updated";
    ignoredInput.dispatchEvent(new Event("input", { bubbles: true }));

    await waitForAnimationFrames();

    expect(api.hasPendingChanges()).to.equal(false);
    expect(document.getElementById("pending-alert")?.classList.contains("hidden")).to.equal(true);
  });

  it("asks for confirmation when cancelling with pending changes", async () => {
    document.body.innerHTML = `
      <div id="pending-alert" class="hidden"></div>
      <button id="cancel-button" type="button">Cancel</button>
      <form id="event-form">
        <input name="title" value="Original title" />
      </form>
    `;

    const api = initializePendingChangesAlert({
      alertId: "pending-alert",
      formIds: ["event-form"],
      cancelButtonId: "cancel-button",
      confirmMessage: "Discard pending changes?",
      confirmText: "Discard",
    });

    await waitForAnimationFrames();

    const titleInput = document.querySelector('#event-form input[name="title"]');
    titleInput.value = "Updated title";
    titleInput.dispatchEvent(new Event("input", { bubbles: true }));

    await waitForAnimationFrames();

    document.getElementById("cancel-button")?.click();
    await waitForMicrotask();

    expect(api.hasPendingChanges()).to.equal(true);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Discard pending changes?");
    expect(swal.calls[0].confirmButtonText).to.equal("Discard");
    expect(htmx.triggerCalls).to.deep.equal([["#cancel-button", "confirmed"]]);
  });
});
