import { expect } from "@open-wc/testing";

import { getAttendanceMeta } from "/static/js/event/attendance-dom.js";
import { renderMeetingDetails } from "/static/js/event/attendance-view.js";
import {
  renderAttendanceCheckResponse,
  storePendingAttendanceCheckResponse,
} from "/static/js/event/attendance/status-renderer.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const PAST_TITLE = "You cannot change attendance because the event has already started.";
const REFUND_PENDING_TITLE = "Your refund request is waiting for organizer review.";
const SOLD_OUT_TITLE = "This event is sold out.";

/** Builds an attendance container with the controls the bar reads. */
const renderContainer = ({ dataset = {}, phoneBar = false } = {}) => {
  document.body.innerHTML = `
    <div
      data-attendance-container
      data-availability-hydrated="true"
      data-has-visible-ticket-types="true"
      data-is-simple-rsvp="true"
      data-ticket-purchase-available="true"
      ${phoneBar ? 'data-phone-bar="hidden"' : ""}
    >
      <div data-attendance-role="bar-summary">
        <p data-attendance-role="bar-reason"></p>
      </div>
      <button data-attendance-role="loading-btn" disabled></button>
      <button data-attendance-role="signin-btn" class="hidden">
        <div data-attendance-icon></div><span data-attendance-label></span>
      </button>
      <button data-attendance-role="attend-btn" class="hidden">
        <div data-attendance-icon></div><span data-attendance-label></span>
      </button>
      <a data-join-link class="hidden" href="https://example.test/meeting"></a>
      <button data-attendance-role="leave-btn" class="hidden">
        <div data-attendance-icon></div><span data-attendance-label></span>
      </button>
      <details data-attendance-role="actions-menu">
        <button data-attendance-role="checkout-cancel-btn" class="hidden">
          <div data-attendance-icon></div><span data-attendance-label></span>
        </button>
      </details>
      <button data-attendance-role="refund-btn" class="hidden">
        <div data-attendance-icon></div><span data-attendance-label></span>
      </button>
    </div>
  `;

  const container = document.querySelector("[data-attendance-container]");
  Object.assign(container.dataset, dataset);
  return container;
};

/** Returns the afterRequest event of a successful enrollment response. */
const enrollmentEvent = (response) => ({
  detail: { xhr: { responseText: JSON.stringify(response), status: 200 } },
});

const signedOutEvent = { detail: { xhr: { responseText: "", status: 401 } } };

const getReason = (container) =>
  container.querySelector('[data-attendance-role="bar-reason"]').textContent;

describe("attendance status renderer", () => {
  const originalMatchMedia = window.matchMedia;

  /** Stubs the phone query with a fixed answer. */
  const setPhoneQuery = (matches) => {
    window.matchMedia = () => ({ matches });
  };

  afterEach(() => {
    window.matchMedia = originalMatchMedia;
    resetDom();
  });

  describe("on phones", () => {
    beforeEach(() => {
      setPhoneQuery(true);
    });

    it("leaves the bar alone while the visible control is enabled", () => {
      // Render a guest on an open event.
      const container = renderContainer();
      renderAttendanceCheckResponse(container, enrollmentEvent({ status: "guest" }));

      expect(container.hasAttribute("data-bar-reason")).to.equal(false);
      expect(getReason(container)).to.equal("");
      expect(container.hasAttribute("data-phone-bar")).to.equal(false);
    });

    it("falls back to the control's label when a disabled control has no title", () => {
      // Render a member whose latest ticket offer expired.
      const container = renderContainer();
      renderAttendanceCheckResponse(container, enrollmentEvent({ status: "offer-expired" }));

      expect(container.hasAttribute("data-bar-reason")).to.equal(true);
      expect(getReason(container)).to.equal("Ticket offer expired");
    });

    it("writes the disabled control's title as the reason", () => {
      // Render a guest on a sold-out event without a waiting list.
      const container = renderContainer({ dataset: { capacity: "10", remainingCapacity: "0" } });
      renderAttendanceCheckResponse(container, enrollmentEvent({ status: "guest" }));

      expect(container.hasAttribute("data-bar-reason")).to.equal(true);
      expect(getReason(container)).to.equal(SOLD_OUT_TITLE);
    });

    it("clears the reason once the control is enabled again", () => {
      // Render a full event, then a spot opening up.
      const container = renderContainer({ dataset: { capacity: "10", remainingCapacity: "0" } });
      renderAttendanceCheckResponse(container, enrollmentEvent({ status: "guest" }));
      container.dataset.remainingCapacity = "2";
      renderAttendanceCheckResponse(container, enrollmentEvent({ status: "guest" }));

      expect(container.hasAttribute("data-bar-reason")).to.equal(false);
      expect(getReason(container)).to.equal("");
    });

    it("keeps the bar hidden on a past event with no action", () => {
      // An attendee on a past event has only a disabled Cancel attendance.
      const container = renderContainer({ dataset: { isPast: "true" }, phoneBar: true });
      renderAttendanceCheckResponse(container, enrollmentEvent({ status: "attendee" }));

      expect(container.dataset.phoneBar).to.equal("hidden");
    });

    it("keeps the bar hidden for signed-out visitors on a canceled event", () => {
      const container = renderContainer({ dataset: { canceled: "true" }, phoneBar: true });
      renderAttendanceCheckResponse(container, signedOutEvent);

      expect(container.dataset.phoneBar).to.equal("hidden");
    });

    it("removes the hidden state for a refund state", () => {
      // A pending refund is disabled, but the user still needs to see its status.
      const container = renderContainer({ dataset: { isPast: "true" }, phoneBar: true });
      renderAttendanceCheckResponse(
        container,
        enrollmentEvent({ refund_request_status: "pending", status: "attendee" }),
      );

      expect(container.hasAttribute("data-phone-bar")).to.equal(false);
      expect(getReason(container)).to.equal(REFUND_PENDING_TITLE);
    });

    it("removes the hidden state for an enabled action", () => {
      // A refund that can still be requested is an enabled action.
      const container = renderContainer({ dataset: { canceled: "true" }, phoneBar: true });
      renderAttendanceCheckResponse(
        container,
        enrollmentEvent({ can_request_refund: true, status: "attendee" }),
      );

      expect(container.hasAttribute("data-phone-bar")).to.equal(false);
      expect(container.hasAttribute("data-bar-reason")).to.equal(false);
    });

    it("restores the hidden state when the action goes away", () => {
      // The refund offer lapses between two enrollment checks.
      const container = renderContainer({ dataset: { isPast: "true" }, phoneBar: true });
      renderAttendanceCheckResponse(
        container,
        enrollmentEvent({ can_request_refund: true, status: "attendee" }),
      );
      renderAttendanceCheckResponse(container, enrollmentEvent({ status: "attendee" }));

      expect(container.dataset.phoneBar).to.equal("hidden");
    });

    it("treats Join meeting as the action on a started event", () => {
      // Cancel attendance is disabled, but Join meeting replaces it.
      const container = renderContainer({
        dataset: { attendeeMeetingAccessOpen: "true", isPast: "true" },
        phoneBar: true,
      });
      renderAttendanceCheckResponse(container, enrollmentEvent({ status: "attendee" }));

      expect(container.hasAttribute("data-phone-bar")).to.equal(false);
      expect(container.hasAttribute("data-bar-reason")).to.equal(false);
    });

    it("treats Cancel checkout as the action on a past event", () => {
      // Continue to checkout is disabled, so the menu is what is left.
      const container = renderContainer({ dataset: { isPast: "true" }, phoneBar: true });
      renderAttendanceCheckResponse(
        container,
        enrollmentEvent({ resume_checkout_url: "/checkout", status: "pending-payment" }),
      );

      expect(container.hasAttribute("data-phone-bar")).to.equal(false);
      expect(getReason(container)).to.equal(PAST_TITLE);
    });

    it("writes nothing while availability has not hydrated", () => {
      // The response waits for availability, and the initial hidden state stays.
      const container = renderContainer({
        dataset: { availabilityHydrated: "false", isPast: "true" },
        phoneBar: true,
      });
      renderAttendanceCheckResponse(
        container,
        enrollmentEvent({ refund_request_status: "pending", status: "attendee" }),
      );

      expect(container.dataset.phoneBar).to.equal("hidden");
      expect(container.hasAttribute("data-bar-reason")).to.equal(false);
    });
  });

  describe("off phones", () => {
    beforeEach(() => {
      setPhoneQuery(false);
    });

    it("never writes the bar state", () => {
      // Render the states that write on phones.
      const container = renderContainer({ dataset: { isPast: "true" }, phoneBar: true });
      const refund = enrollmentEvent({ refund_request_status: "pending", status: "attendee" });
      renderAttendanceCheckResponse(container, refund);

      // The server's attribute stays as rendered, and no reason is written.
      expect(container.dataset.phoneBar).to.equal("hidden");
      expect(container.hasAttribute("data-bar-reason")).to.equal(false);
      expect(getReason(container)).to.equal("");
    });

    it("does not add the attribute to a past event rendered without it", () => {
      const container = renderContainer({ dataset: { isPast: "true" } });
      renderAttendanceCheckResponse(container, enrollmentEvent({ status: "attendee" }));

      expect(container.hasAttribute("data-phone-bar")).to.equal(false);
    });
  });

  describe("phone query listener", () => {
    /** Loads a fresh module on a fake query and returns its listeners. */
    const loadWithFakeQuery = async (id) => {
      const listeners = [];
      const query = {
        addEventListener: (type, listener) => listeners.push({ listener, type }),
        matches: false,
      };
      window.matchMedia = () => query;
      const module = await import(`/static/js/event/attendance/status-renderer.js?test=${id}`);

      return { listeners, module, query };
    };

    it("keeps exactly one listener and re-runs the bar on rotation into a phone", async () => {
      // Render in landscape, where the query is false and nothing is written.
      const { listeners, module, query } = await loadWithFakeQuery("rotate");
      const container = renderContainer({ dataset: { isPast: "true" }, phoneBar: true });
      module.renderAttendanceCheckResponse(
        container,
        enrollmentEvent({ refund_request_status: "pending", status: "attendee" }),
      );
      expect(listeners).to.have.length(1);
      expect(listeners[0].type).to.equal("change");
      expect(container.dataset.phoneBar).to.equal("hidden");

      // Rotate, so the query turns true.
      query.matches = true;
      listeners[0].listener({ matches: true });

      expect(container.hasAttribute("data-phone-bar")).to.equal(false);
      expect(getReason(container)).to.equal(REFUND_PENDING_TITLE);
    });

    it("writes nothing when the query turns false", async () => {
      // Render a disabled state in landscape, then fire the false transition.
      const { listeners, module } = await loadWithFakeQuery("leave");
      const container = renderContainer({ dataset: { capacity: "10", remainingCapacity: "0" } });
      module.renderAttendanceCheckResponse(container, enrollmentEvent({ status: "guest" }));
      listeners[0].listener({ matches: false });

      expect(container.hasAttribute("data-bar-reason")).to.equal(false);
    });

    it("skips containers that have no response yet", async () => {
      // A pending response is not the last rendered one.
      const { listeners, query } = await loadWithFakeQuery("pending");
      const container = renderContainer({ dataset: { isPast: "true" }, phoneBar: true });
      storePendingAttendanceCheckResponse(container, enrollmentEvent({ status: "attendee" }));
      query.matches = true;
      listeners[0].listener({ matches: true });

      expect(container.dataset.phoneBar).to.equal("hidden");
    });
  });

  it("toggles phone:flex with xl:flex on the join link, never statically", () => {
    // Show and hide meeting access.
    const container = renderContainer();
    const joinLink = container.querySelector("[data-join-link]");
    const meta = { ...getAttendanceMeta(container), attendeeMeetingAccessOpen: true };

    renderMeetingDetails(true, meta);
    expect(joinLink.classList.contains("phone:flex")).to.equal(true);
    expect(joinLink.classList.contains("xl:flex")).to.equal(true);

    renderMeetingDetails(false, meta);
    expect(joinLink.classList.contains("phone:flex")).to.equal(false);
    expect(joinLink.classList.contains("hidden")).to.equal(true);
  });
});
