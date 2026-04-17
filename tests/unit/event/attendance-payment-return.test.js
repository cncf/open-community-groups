import { expect } from "@open-wc/testing";

import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

const renderAttendanceDom = () => {
  document.body.innerHTML = `
    <div
      data-attendance-container
      data-is-ticketed="true"
      data-ticket-purchase-available="true"
      data-starts="2099-05-10T10:00:00Z"
      data-is-live="false"
      data-waitlist-enabled="false"
    >
      <button
        data-attendance-role="attendance-checker"
        hx-get="/test-community/event/test-event/attendance"
      ></button>
      <button data-attendance-role="attend-btn" data-attend-label="Buy ticket">
        <span data-attendance-label>Buy ticket</span>
      </button>
      <button data-attendance-role="leave-btn" data-attendee-label="Cancel attendance">
        <span data-attendance-label>Cancel attendance</span>
      </button>
      <button data-attendance-role="refund-btn" data-refund-label="Request refund">
        <span data-attendance-label>Request refund</span>
      </button>
      <button data-attendance-role="signin-btn">
        <span data-attendance-label>Buy ticket</span>
      </button>
    </div>
  `;
};

describe("event attendance payment return", () => {
  const env = useDashboardTestEnv({
    path: "/events/test-event?payment=success",
    withSwal: true,
    bodyDatasetKeysToClear: ["attendanceListenersReady"],
  });

  it("shows a fallback message when the success return cannot be reconciled", async () => {
    renderAttendanceDom();
    const fetchMock = mockFetch({
      impl: async () => {
        throw new Error("network error");
      },
    });

    try {
      await import(`/static/js/event/attendance.js?test=${Date.now()}`);
      await waitForMicrotask();

      expect(env.current.swal.calls.at(-1)).to.include({
        icon: "info",
        text: "Your payment was submitted. If the page still shows Complete payment, wait a few seconds and refresh.",
      });
      expect(window.location.search).to.equal("");
    } finally {
      fetchMock.restore();
    }
  });
});
