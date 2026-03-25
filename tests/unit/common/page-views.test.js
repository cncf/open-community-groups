import { expect } from "@open-wc/testing";

import { trackPageView } from "/static/js/common/page-views.js";
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
    eventListeners = trackAddedEventListeners();
    fetchMock = mockFetch();
    sendBeaconMock = mockSendBeacon();
    visibilityState = mockVisibilityState();
  });

  afterEach(() => {
    resetDom();
    visibilityState.restore();
    fetchMock.restore();
    sendBeaconMock.restore();
    eventListeners.restore();
  });

  it("sends a beacon for visible community page views", () => {
    trackPageView({ entityId: "cncf", entityType: "community" });

    expect(sendBeaconMock.calls).to.have.length(1);
    expect(sendBeaconMock.calls[0].endpoint).to.equal("/communities/cncf/views");
    expect(fetchMock.calls).to.have.length(0);
  });

  it("falls back to fetch when sendBeacon does not queue the event", async () => {
    sendBeaconMock.setReturnValue(false);

    trackPageView({ entityId: "123", entityType: "event" });
    await waitForMicrotask();

    expect(sendBeaconMock.calls).to.have.length(1);
    expect(fetchMock.calls).to.deep.equal([
      ["/events/123/views", { method: "POST", keepalive: true }],
    ]);
  });

  it("queues hidden page views until the document becomes visible", () => {
    visibilityState.set("hidden");

    trackPageView({ entityId: "group-a", entityType: "group" });

    expect(sendBeaconMock.calls).to.have.length(0);
    expect(window.__ocgPageViewTracker.pendingViews).to.equal(1);

    visibilityState.set("visible");
    document.dispatchEvent(new Event("visibilitychange"));

    expect(sendBeaconMock.calls).to.have.length(1);
    expect(sendBeaconMock.calls[0].endpoint).to.equal("/groups/group-a/views");
    expect(window.__ocgPageViewTracker.pendingViews).to.equal(0);
  });

  it("replays page views when a persisted page is shown again", () => {
    trackPageView({ entityId: "cncf", entityType: "community" });
    expect(sendBeaconMock.calls).to.have.length(1);

    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

    expect(sendBeaconMock.calls).to.have.length(2);
    expect(sendBeaconMock.calls[1].endpoint).to.equal("/communities/cncf/views");
  });

  it("ignores incomplete tracking payloads", () => {
    trackPageView({ entityId: "", entityType: "community" });
    trackPageView({ entityId: "cncf", entityType: "" });

    expect(sendBeaconMock.calls).to.have.length(0);
    expect(fetchMock.calls).to.have.length(0);
  });
});
