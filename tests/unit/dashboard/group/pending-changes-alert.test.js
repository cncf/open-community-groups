import { expect } from "@open-wc/testing";

import { initializePendingChangesAlert } from "/static/js/dashboard/group/pending-changes-alert.js";

const waitForAnimationFrames = async (count = 2) => {
  for (let index = 0; index < count; index += 1) {
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
  }
};

const waitForMicrotask = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("pending changes alert", () => {
  const originalSwal = globalThis.Swal;
  const originalHtmx = globalThis.htmx;

  let fireCalls;
  let triggerCalls;

  beforeEach(() => {
    fireCalls = [];
    triggerCalls = [];
    document.body.innerHTML = "";

    globalThis.Swal = {
      fire: async (options) => {
        fireCalls.push(options);
        return { isConfirmed: true };
      },
    };

    globalThis.htmx = {
      trigger: (...args) => {
        triggerCalls.push(args);
      },
    };
  });

  afterEach(() => {
    document.body.innerHTML = "";
    globalThis.Swal = originalSwal;
    globalThis.htmx = originalHtmx;
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
    expect(fireCalls).to.have.length(1);
    expect(fireCalls[0].text).to.equal("Discard pending changes?");
    expect(fireCalls[0].confirmButtonText).to.equal("Discard");
    expect(triggerCalls).to.deep.equal([["#cancel-button", "confirmed"]]);
  });
});
