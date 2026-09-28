import { expect } from "@open-wc/testing";

import { initializeGroupCohostsList } from "/static/js/dashboard/group/cohosts.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

/**
 * Mounts a co-hosts list with approve, reject, and cancel actions and initializes it.
 * @returns {Element} Initialized co-hosts list root.
 */
const mountList = () => {
  document.body.innerHTML = `
    <div data-group-cohosts-list>
      <button type="button" data-cohost-action="approve">Approve</button>
      <button type="button" data-cohost-action="reject">Reject</button>
      <button type="button" data-cohost-action="cancel">Cancel co-hosting</button>
    </div>
  `;
  const root = document.querySelector("[data-group-cohosts-list]");
  initializeGroupCohostsList(root);
  return root;
};

/**
 * Dispatches an HTMX after request event from a co-host action button.
 * @param {HTMLButtonElement} button Co-host action button.
 * @param {object|null} xhr XHR-like request result.
 * @returns {void}
 */
const dispatchAfterRequest = (button, xhr) => {
  button.dispatchEvent(new CustomEvent("htmx:afterRequest", { bubbles: true, detail: { xhr } }));
};

describe("dashboard group co-host actions", () => {
  let htmx;
  let swal;

  beforeEach(() => {
    resetDom();
    htmx = mockHtmx();
    swal = mockSwal();
  });

  afterEach(() => {
    resetDom();
    htmx.restore();
    swal.restore();
  });

  it("shows the approval consequences and triggers the confirmed HTMX request", async () => {
    // Confirm the approval.
    const root = mountList();
    const button = root.querySelector('[data-cohost-action="approve"]');
    button.click();
    await waitForMicrotask();

    // Verify the consequences and the confirmed trigger.
    expect(swal.calls[0].html).to.include("The event appears on your group page");
    expect(swal.calls[0].html).to.include("you get no access to it");
    expect(htmx.triggerCalls).to.deep.equal([[button, "confirmed"]]);
  });

  it("does not trigger the request when the confirmation is canceled", async () => {
    // Dismiss the next confirmation.
    swal.setNextResult({ isConfirmed: false });

    // Trigger a rejection and dismiss it.
    const root = mountList();
    root.querySelector('[data-cohost-action="reject"]').click();
    await waitForMicrotask();

    // Verify no request was triggered.
    expect(swal.calls).to.have.length(1);
    expect(htmx.triggerCalls).to.have.length(0);
  });

  it("ignores clicks on disabled actions", async () => {
    // Disable the action as HTMX does while a request is pending.
    const root = mountList();
    const button = root.querySelector('[data-cohost-action="cancel"]');
    button.disabled = true;
    button.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    await waitForMicrotask();

    // Verify no confirmation or request was started.
    expect(swal.calls).to.have.length(0);
    expect(htmx.triggerCalls).to.have.length(0);
  });

  it("shows the action success alert after a successful request", () => {
    // Finish a successful cancel request.
    const root = mountList();
    dispatchAfterRequest(root.querySelector('[data-cohost-action="cancel"]'), { status: 204 });

    // Verify the success alert.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].icon).to.equal("success");
    expect(swal.calls[0].text).to.equal("Co-hosting canceled.");
  });

  it("shows an error alert when the request is rejected", () => {
    // Finish a failed approval request.
    const root = mountList();
    dispatchAfterRequest(root.querySelector('[data-cohost-action="approve"]'), {
      responseText: "",
      status: 500,
    });

    // Verify the error alert.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].icon).to.equal("error");
    expect(swal.calls[0].text).to.include("Something went wrong updating this co-hosting invitation");
  });

  it("warns that the outcome is unknown when the connection fails", () => {
    // Finish a request without a server response.
    const root = mountList();
    dispatchAfterRequest(root.querySelector('[data-cohost-action="reject"]'), { status: 0 });

    // Verify the unconfirmed outcome alert.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].icon).to.equal("error");
    expect(swal.calls[0].text).to.include("refresh the page before trying again");
  });
});
