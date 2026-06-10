import { expect } from "@open-wc/testing";

import { initializeEventCheckIn } from "/static/js/event/check-in.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxLoad,
} from "/tests/unit/test-utils/htmx.js";

describe("event check-in", () => {
  let swal;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
  });

  const renderCheckInDom = () => {
    document.body.innerHTML = `
      <div id="check-in-success-card" class="hidden"></div>
      <div id="check-in-form-container"></div>
      <form id="event-check-in-form"></form>
      <a id="view-event-details-button" class="hidden"></a>
    `;
  };

  it("shows the checked-in state after a successful response", () => {
    // Build the DOM fixture and initialize check-in behavior.
    renderCheckInDom();
    initializeEventCheckIn();

    // Dispatch the successful HTMX response from the form.
    dispatchHtmxAfterRequest(document.getElementById("event-check-in-form"), { status: 204 });

    // The success state is visible and the check-in form is hidden.
    expect(document.getElementById("check-in-success-card")?.classList.contains("hidden")).to.equal(
      false,
    );
    expect(document.getElementById("check-in-form-container")?.classList.contains("hidden")).to.equal(
      true,
    );
    expect(document.getElementById("event-check-in-form")?.classList.contains("hidden")).to.equal(
      true,
    );
    expect(
      document.getElementById("view-event-details-button")?.classList.contains("hidden"),
    ).to.equal(false);
    expect(swal.calls[0]).to.include({
      text: "You're all checked in! Enjoy the event.",
      icon: "success",
    });
  });

  it("initializes restored check-in content after HTMX loads", () => {
    // Build the DOM fixture inside a fragment root that HTMX loaded.
    document.body.innerHTML = `<section id="check-in-content"></section>`;
    const content = document.getElementById("check-in-content");
    content.innerHTML = `
      <div id="check-in-success-card" class="hidden"></div>
      <div id="check-in-form-container"></div>
      <form id="event-check-in-form"></form>
      <a id="view-event-details-button" class="hidden"></a>
    `;

    // Dispatch the HTMX load event emitted for the restored check-in fragment.
    dispatchHtmxLoad(content);
    dispatchHtmxAfterRequest(document.getElementById("event-check-in-form"), { status: 204 });

    // The restored form is wired and can show the successful check-in state.
    expect(document.getElementById("check-in-success-card")?.classList.contains("hidden")).to.equal(
      false,
    );
    expect(swal.calls[0]).to.include({
      text: "You're all checked in! Enjoy the event.",
      icon: "success",
    });
  });

  it("keeps the form visible after a failed response", () => {
    // Build the DOM fixture and initialize check-in behavior.
    renderCheckInDom();
    initializeEventCheckIn();

    // Dispatch the failed HTMX response from the form.
    dispatchHtmxAfterRequest(document.getElementById("event-check-in-form"), { status: 500 });

    // The check-in form remains visible and the failure alert is shown.
    expect(document.getElementById("check-in-success-card")?.classList.contains("hidden")).to.equal(
      true,
    );
    expect(document.getElementById("event-check-in-form")?.classList.contains("hidden")).to.equal(
      false,
    );
    expect(swal.calls[0]).to.include({
      text: "Check-in failed. Please try again later.",
      icon: "error",
    });
  });
});
