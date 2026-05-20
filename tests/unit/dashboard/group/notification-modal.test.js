import { expect } from "@open-wc/testing";

import { createNotificationModal } from "/static/js/dashboard/group/notificationModal.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";

describe("notification modal", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/groups",
    withScroll: true,
    withSwal: true,
  });

  it("updates the form endpoint and toggles the modal from controls", () => {
    // Build the DOM fixture to check it updates the form endpoint and toggles the modal.
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

    // Prepare update calls to check it updates the form endpoint and toggles the modal.
    const updateCalls = [];

    // Exercise the flow to check it updates the form endpoint and toggles the modal.
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

    // Read the notification modal element to check it updates the form endpoint.
    const modal = document.getElementById("notification-modal");
    document.getElementById("open-modal")?.click();

    // Confirm it updates the form endpoint and toggles the modal from controls.
    expect(updateCalls).to.have.length(2);
    expect(
      document.getElementById("notification-form")?.getAttribute("action"),
    ).to.equal("/updated");
    expect(modal.classList.contains("hidden")).to.equal(false);

    // Trigger the user interaction to check it updates the form endpoint and toggles.
    document.getElementById("close-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);

    // Trigger the user interaction to check it updates the form endpoint and toggles.
    document.getElementById("cancel-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(false);

    // Trigger the user interaction to check it updates the form endpoint and toggles.
    document.getElementById("modal-overlay")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("resets the form and closes the modal after a successful htmx request", () => {
    // Build the DOM fixture to check it resets the form and closes the modal.
    document.body.innerHTML = `
      <button id="open-modal" type="button">Open</button>
      <div id="notification-modal"></div>
      <form id="notification-form">
        <input name="message" value="hello" />
      </form>
    `;

    // Read the notification form element to check it resets the form and closes.
    const form = document.getElementById("notification-form");
    let resetCalls = 0;
    form.reset = () => {
      resetCalls += 1;
    };

    // Exercise the flow to check it resets the form and closes the modal.
    createNotificationModal({
      modalId: "notification-modal",
      formId: "notification-form",
      dataKey: "notificationReady",
      openButtonId: "open-modal",
      successMessage: "Email sent.",
    });

    // Dispatch the HTMX after request event to check it resets the form and closes.
    dispatchHtmxAfterRequest(form, {
      status: 204,
    });

    // Confirm it resets the form and closes the modal after a successful HTMX request.
    expect(resetCalls).to.equal(1);
    expect(
      document
        .getElementById("notification-modal")
        ?.classList.contains("hidden"),
    ).to.equal(true);
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      text: "Email sent.",
      icon: "success",
    });
  });

  it("shows an error and keeps the modal open after a failed htmx request", () => {
    // Build the DOM fixture to check it shows an error and keeps the modal open.
    document.body.innerHTML = `
      <button id="open-modal" type="button">Open</button>
      <div id="notification-modal"></div>
      <form id="notification-form">
        <input name="message" value="hello" />
      </form>
    `;

    // Exercise the flow to check it shows an error and keeps the modal open.
    createNotificationModal({
      modalId: "notification-modal",
      formId: "notification-form",
      dataKey: "notificationReady",
      openButtonId: "open-modal",
    });

    // Dispatch the HTMX after request event to check it shows an error and keeps.
    dispatchHtmxAfterRequest(document.getElementById("notification-form"), {
      status: 500,
      responseText: "Server exploded",
    });

    // Confirm it shows an error and keeps the modal open after a failed HTMX request.
    expect(
      document
        .getElementById("notification-modal")
        ?.classList.contains("hidden"),
    ).to.equal(false);
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      text: "Server exploded",
      icon: "error",
    });
    expect(env.current.scrollToMock.calls).to.deep.equal([
      { top: 0, behavior: "auto" },
    ]);
  });
});
