import { expect } from "@open-wc/testing";

import { initializeGroupCohostsList } from "/static/js/dashboard/group/cohosts.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

/**
 * Mounts a co-hosts list with approve, reject, and cancel actions and initializes it.
 * @returns {Element} Initialized co-hosts list root.
 */
const mountList = () => {
  document.body.innerHTML = `
    <div data-group-cohosts-list>
      <button
        type="button"
        data-cohost-action="approve"
        data-cohost-url="/dashboard/group/cohosts/invitation-1/approve"
      >Approve</button>
      <button
        type="button"
        data-cohost-action="reject"
        data-cohost-url="/dashboard/group/cohosts/invitation-1/reject"
      >Reject</button>
      <button
        type="button"
        data-cohost-action="cancel"
        data-cohost-url="/dashboard/group/cohosts/invitation-1/cancel"
      >Cancel co-hosting</button>
    </div>
  `;
  const root = document.querySelector("[data-group-cohosts-list]");
  initializeGroupCohostsList(root);
  return root;
};

describe("dashboard group co-host actions", () => {
  let swal;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
  });

  it("shows the approval consequences and sends the invitation id PUT URL", async () => {
    // Track list refreshes and respond with the refresh trigger.
    const refreshEvents = [];
    document.body.addEventListener("refresh-group-cohosts", () => {
      refreshEvents.push("refresh");
    });
    const fetchMock = mockFetch({
      response: new Response(null, {
        headers: { "HX-Trigger": "refresh-group-cohosts" },
        status: 204,
      }),
    });

    try {
      // Confirm the approval and let the request settle.
      const root = mountList();
      root.querySelector('[data-cohost-action="approve"]').click();
      await waitForMicrotask();
      await waitForMicrotask();

      // Verify the consequences, the request, and the list refresh.
      expect(swal.calls[0].html).to.include("The event appears on your group page");
      expect(swal.calls[0].html).to.include("you get no access to it");
      expect(fetchMock.calls).to.have.length(1);
      expect(fetchMock.calls[0][0]).to.equal("/dashboard/group/cohosts/invitation-1/approve");
      expect(fetchMock.calls[0][1].method).to.equal("PUT");
      expect(refreshEvents).to.deep.equal(["refresh"]);
    } finally {
      fetchMock.restore();
    }
  });

  it("does not send a request when the confirmation is canceled", async () => {
    // Dismiss the next confirmation.
    swal.setNextResult({ isConfirmed: false });
    const fetchMock = mockFetch();

    try {
      // Trigger a rejection and dismiss it.
      const root = mountList();
      root.querySelector('[data-cohost-action="reject"]').click();
      await waitForMicrotask();

      // Verify no request was sent.
      expect(fetchMock.calls).to.have.length(0);
    } finally {
      fetchMock.restore();
    }
  });

  it("blocks repeat clicks while a request is pending", async () => {
    // Keep the action request pending until resolved manually.
    let resolveResponse;
    const fetchMock = mockFetch({
      impl: () =>
        new Promise((resolve) => {
          resolveResponse = resolve;
        }),
    });

    try {
      // Click the action twice while the first request is pending.
      const root = mountList();
      const button = root.querySelector('[data-cohost-action="cancel"]');
      button.click();
      await waitForMicrotask();
      button.click();
      await waitForMicrotask();

      // Verify only one request was sent and the button is disabled.
      expect(fetchMock.calls).to.have.length(1);
      expect(button.disabled).to.equal(true);

      // Resolve the request and verify the button is restored.
      resolveResponse(new Response(null, { status: 204 }));
      await waitForMicrotask();
      expect(button.disabled).to.equal(false);
    } finally {
      fetchMock.restore();
    }
  });

  it("shows an error and restores the action when the request fails", async () => {
    // Track list refreshes and fail the action request.
    const refreshEvents = [];
    document.body.addEventListener("refresh-group-cohosts", () => {
      refreshEvents.push("refresh");
    });
    const fetchMock = mockFetch({
      impl: async () => {
        throw new TypeError("Failed to fetch");
      },
    });

    try {
      // Confirm the rejection and let the failed request settle.
      const root = mountList();
      const button = root.querySelector('[data-cohost-action="reject"]');
      button.click();
      await waitForMicrotask();
      await waitForMicrotask();

      // Verify the error alert and the restored action.
      expect(fetchMock.calls).to.have.length(1);
      expect(swal.calls).to.have.length(2);
      expect(swal.calls[1].icon).to.equal("error");
      expect(swal.calls[1].text).to.include("refresh the page before trying again");
      expect(button.disabled).to.equal(false);
      expect(button.hasAttribute("aria-busy")).to.equal(false);
      expect(refreshEvents).to.deep.equal([]);
    } finally {
      fetchMock.restore();
    }
  });
});
