import { expect } from "@open-wc/testing";

import {
  initializePageViewTracking,
  resetPageViewTracker,
  trackPageView,
} from "/static/js/common/page-views.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom, trackAddedEventListeners } from "/tests/unit/test-utils/dom.js";
import { mockFetch, mockSendBeacon, mockVisibilityState } from "/tests/unit/test-utils/network.js";

describe("page views", () => {
  let eventListeners;
  let fetchMock;
  let sendBeaconMock;
  let visibilityState;

  beforeEach(() => {
    resetDom();
    resetPageViewTracker();
    eventListeners = trackAddedEventListeners();
    fetchMock = mockFetch();
    sendBeaconMock = mockSendBeacon();
    visibilityState = mockVisibilityState();
  });

  afterEach(() => {
    resetDom();
    resetPageViewTracker();
    visibilityState.restore();
    fetchMock.restore();
    sendBeaconMock.restore();
    eventListeners.restore();
  });

  it("sends a beacon for visible community page views", () => {
    // Track the page view event.
    trackPageView({ entityId: "cncf", entityType: "community" });

    // Sends a beacon for visible community page views.
    expect(sendBeaconMock.calls).to.have.length(1);
    expect(sendBeaconMock.calls[0].endpoint).to.equal("/communities/cncf/views");
    expect(fetchMock.calls).to.have.length(0);
  });

  it("tracks declarative page view markers once", () => {
    // Build the DOM fixture with a server-rendered page view marker.
    document.body.innerHTML = `
      <span data-page-view data-entity-id="event-123" data-entity-type="event" hidden></span>
    `;

    // Initialize tracking twice to verify the marker is consumed only once.
    initializePageViewTracking();
    initializePageViewTracking();

    // The marker sends one page view to the expected endpoint.
    expect(sendBeaconMock.calls).to.have.length(1);
    expect(sendBeaconMock.calls[0].endpoint).to.equal("/events/event-123/views");
    expect(fetchMock.calls).to.have.length(0);
  });

  it("falls back to fetch when sendBeacon does not queue the event", async () => {
    // Set the mock return value.
    sendBeaconMock.setReturnValue(false);

    // Track the page view event.
    trackPageView({ entityId: "123", entityType: "event" });
    await waitForMicrotask();

    // Fallback to fetch when sendBeacon does not queue the event.
    expect(sendBeaconMock.calls).to.have.length(1);
    expect(fetchMock.calls).to.deep.equal([["/events/123/views", { method: "POST", keepalive: true }]]);
  });

  it("queues hidden page views until the document becomes visible", () => {
    // Set up queues hidden page views until the document becomes visible.
    visibilityState.set("hidden");

    // Track the page view event.
    trackPageView({ entityId: "group-a", entityType: "group" });

    // Assert the captured calls.
    expect(sendBeaconMock.calls).to.have.length(0);
    expect(window.__ocgPageViewTracker).to.equal(undefined);

    // Set up queues hidden page views until the document becomes visible.
    visibilityState.set("visible");
    document.dispatchEvent(new Event("visibilitychange"));

    // Assert the later captured calls.
    expect(sendBeaconMock.calls).to.have.length(1);
    expect(sendBeaconMock.calls[0].endpoint).to.equal("/groups/group-a/views");
    expect(window.__ocgPageViewTracker).to.equal(undefined);
  });

  it("replays page views when a persisted page is shown again", () => {
    // Track the page view event.
    trackPageView({ entityId: "cncf", entityType: "community" });
    expect(sendBeaconMock.calls).to.have.length(1);

    // Dispatch the new page transition event("pageshow", { persisted: true } event.
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

    // Assert the captured calls.
    expect(sendBeaconMock.calls).to.have.length(2);
    expect(sendBeaconMock.calls[1].endpoint).to.equal("/communities/cncf/views");
  });

  it("ignores incomplete tracking payloads", () => {
    // Track the page view event.
    trackPageView({ entityId: "", entityType: "community" });
    trackPageView({ entityId: "cncf", entityType: "" });

    // The request uses the expected endpoint and options.
    expect(sendBeaconMock.calls).to.have.length(0);
    expect(fetchMock.calls).to.have.length(0);
  });
});
