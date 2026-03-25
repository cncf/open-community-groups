import { expect } from "@open-wc/testing";

import { createNotificationModal } from "/static/js/dashboard/group/notificationModal.js";

describe("notification modal", () => {
  const originalSwal = globalThis.Swal;
  const originalPath = window.location.pathname;
  const originalScrollTo = window.scrollTo;

  let fireCalls;
  let scrollCalls;

  beforeEach(() => {
    fireCalls = [];
    scrollCalls = [];
    document.body.innerHTML = "";

    globalThis.Swal = {
      fire: async (options) => {
        fireCalls.push(options);
        return { isConfirmed: true };
      },
    };

    window.scrollTo = (options) => {
      scrollCalls.push(options);
    };

    history.replaceState({}, "", "/dashboard/groups");
  });

  afterEach(() => {
    document.body.innerHTML = "";
    globalThis.Swal = originalSwal;
    window.scrollTo = originalScrollTo;
    history.replaceState({}, "", originalPath);
  });

  it("updates the form endpoint and toggles the modal from controls", () => {
    document.body.innerHTML = `
      <button id="open-modal" type="button">Open</button>
      <div id="notification-modal" class="hidden"></div>
      <button id="close-modal" type="button">Close</button>
      <button id="cancel-modal" type="button">Cancel</button>
      <div id="modal-overlay"></div>
      <form id="notification-form" action="/initial">
        <input name="message" value="hello" />
      </form>
    `;

    const updateCalls = [];

    createNotificationModal({
      modalId: "notification-modal",
      formId: "notification-form",
      dataKey: "notificationReady",
      openButtonId: "open-modal",
      closeButtonId: "close-modal",
      cancelButtonId: "cancel-modal",
      overlayId: "modal-overlay",
      updateEndpoint: ({ form }) => {
        updateCalls.push(form.action);
        form.action = "/updated";
      },
    });

    const modal = document.getElementById("notification-modal");
    document.getElementById("open-modal")?.click();

    expect(updateCalls).to.have.length(2);
    expect(document.getElementById("notification-form")?.getAttribute("action")).to.equal("/updated");
    expect(modal.classList.contains("hidden")).to.equal(false);

    document.getElementById("close-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);

    document.getElementById("cancel-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(false);

    document.getElementById("modal-overlay")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("resets the form and closes the modal after a successful htmx request", () => {
    document.body.innerHTML = `
      <button id="open-modal" type="button">Open</button>
      <div id="notification-modal"></div>
      <form id="notification-form">
        <input name="message" value="hello" />
      </form>
    `;

    const form = document.getElementById("notification-form");
    let resetCalls = 0;
    form.reset = () => {
      resetCalls += 1;
    };

    createNotificationModal({
      modalId: "notification-modal",
      formId: "notification-form",
      dataKey: "notificationReady",
      openButtonId: "open-modal",
      successMessage: "Email sent.",
    });

    form.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: { status: 204, responseText: "" },
        },
      }),
    );

    expect(resetCalls).to.equal(1);
    expect(document.getElementById("notification-modal")?.classList.contains("hidden")).to.equal(true);
    expect(fireCalls).to.have.length(1);
    expect(fireCalls[0]).to.include({ text: "Email sent.", icon: "success" });
  });

  it("shows an error and keeps the modal open after a failed htmx request", () => {
    document.body.innerHTML = `
      <button id="open-modal" type="button">Open</button>
      <div id="notification-modal"></div>
      <form id="notification-form">
        <input name="message" value="hello" />
      </form>
    `;

    createNotificationModal({
      modalId: "notification-modal",
      formId: "notification-form",
      dataKey: "notificationReady",
      openButtonId: "open-modal",
    });

    document.getElementById("notification-form")?.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: { status: 500, responseText: "Server exploded" },
        },
      }),
    );

    expect(document.getElementById("notification-modal")?.classList.contains("hidden")).to.equal(false);
    expect(fireCalls).to.have.length(1);
    expect(fireCalls[0]).to.include({ text: "Server exploded", icon: "error" });
    expect(scrollCalls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });
});
