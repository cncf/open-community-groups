import { expect } from "@open-wc/testing";

import { createNotificationModal } from "/static/js/dashboard/group/notificationModal.js";
import { setupDashboardTestEnv } from "/tests/unit/test-utils/env.js";

describe("notification modal", () => {
  let env;

  beforeEach(() => {
    env = setupDashboardTestEnv({
      path: "/dashboard/groups",
      withScroll: true,
      withSwal: true,
    });
  });

  afterEach(() => {
    env.restore();
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
    expect(env.swal.calls).to.have.length(1);
    expect(env.swal.calls[0]).to.include({ text: "Email sent.", icon: "success" });
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
    expect(env.swal.calls).to.have.length(1);
    expect(env.swal.calls[0]).to.include({ text: "Server exploded", icon: "error" });
    expect(env.scrollToMock.calls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });
});
