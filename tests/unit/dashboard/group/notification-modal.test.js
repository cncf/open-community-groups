import { expect } from "@open-wc/testing";

import { createNotificationModal } from "/static/js/dashboard/group/notification-modal.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";

describe("notification modal", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/groups",
    withScroll: true,
    withSwal: true,
  });

  it("updates the form endpoint and toggles the modal from controls", () => {
    // Render the DOM fixture for updating the form endpoint and toggles the modal.
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

    // Prepare update calls for updating the form endpoint and toggles the modal.
    const updateCalls = [];

    // Verify updates the form endpoint and toggles the modal.
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

    // Keep a reference to the notification modal element.
    const modal = document.getElementById("notification-modal");
    document.getElementById("open-modal")?.click();

    // Verify updates the form endpoint and toggles the modal from controls.
    expect(updateCalls).to.have.length(2);
    expect(document.getElementById("notification-form")?.getAttribute("action")).to.equal("/updated");
    expect(modal.classList.contains("hidden")).to.equal(false);

    // Close the modal from the close button.
    document.getElementById("close-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);

    // Close the modal from the cancel button.
    document.getElementById("cancel-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(false);

    // Close the modal from the overlay.
    document.getElementById("modal-overlay")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("resets the form and closes the modal after a successful htmx request", () => {
    // Render the DOM fixture for resetting the form and closes the modal.
    document.body.innerHTML = `
      <button id="open-modal" type="button">Open</button>
      <div id="notification-modal"></div>
      <form id="notification-form">
        <input name="message" value="hello" />
      </form>
    `;

    // Keep a reference to the notification form element.
    const form = document.getElementById("notification-form");
    let resetCalls = 0;
    form.reset = () => {
      resetCalls += 1;
    };

    // The form reset closes the modal.
    createNotificationModal({
      modalId: "notification-modal",
      formId: "notification-form",
      dataKey: "notificationReady",
      openButtonId: "open-modal",
      successMessage: "Email sent.",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(form, {
      status: 204,
    });

    // A successful HTMX response resets the form and closes the modal.
    expect(resetCalls).to.equal(1);
    expect(document.getElementById("notification-modal")?.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      text: "Email sent.",
      icon: "success",
    });
  });

  it("shows an error and keeps the modal open after a failed htmx request", () => {
    // Render the DOM fixture for showing an error and keeps the modal open.
    document.body.innerHTML = `
      <button id="open-modal" type="button">Open</button>
      <div id="notification-modal"></div>
      <form id="notification-form">
        <input name="message" value="hello" />
      </form>
    `;

    // Verify shows an error and keeps the modal open.
    createNotificationModal({
      modalId: "notification-modal",
      formId: "notification-form",
      dataKey: "notificationReady",
      openButtonId: "open-modal",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(document.getElementById("notification-form"), {
      status: 500,
      responseText: "Server exploded",
    });

    // Verify shows an error and keeps the modal open after a failed HTMX request.
    expect(document.getElementById("notification-modal")?.classList.contains("hidden")).to.equal(false);
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      text: "Server exploded",
      icon: "error",
    });
    expect(env.current.scrollToMock.calls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });
});
