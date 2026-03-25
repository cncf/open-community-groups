import { expect } from "@open-wc/testing";

import { trackPageView } from "/static/js/common/page-views.js";

const waitForMicrotask = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("page views", () => {
  const originalSendBeacon = navigator.sendBeacon;
  const originalFetch = globalThis.fetch;
  const originalVisibilityState = Object.getOwnPropertyDescriptor(Document.prototype, "visibilityState");
  const originalWindowAddEventListener = window.addEventListener.bind(window);
  const originalDocumentAddEventListener = document.addEventListener.bind(document);

  let beaconCalls;
  let fetchCalls;
  let visibilityState;
  let listenersToRemove;

  beforeEach(() => {
    beaconCalls = [];
    fetchCalls = [];
    visibilityState = "visible";
    listenersToRemove = [];

    navigator.sendBeacon = (endpoint, payload) => {
      beaconCalls.push({ endpoint, payload });
      return true;
    };

    globalThis.fetch = (...args) => {
      fetchCalls.push(args);
      return Promise.resolve({ ok: true });
    };

    Object.defineProperty(document, "visibilityState", {
      configurable: true,
      get: () => visibilityState,
    });

    window.addEventListener = (type, listener, options) => {
      listenersToRemove.push(() => window.removeEventListener(type, listener, options));
      return originalWindowAddEventListener(type, listener, options);
    };

    document.addEventListener = (type, listener, options) => {
      listenersToRemove.push(() => document.removeEventListener(type, listener, options));
      return originalDocumentAddEventListener(type, listener, options);
    };

    delete window.__ocgPageViewTracker;
  });

  afterEach(() => {
    delete window.__ocgPageViewTracker;

    if (originalSendBeacon) {
      navigator.sendBeacon = originalSendBeacon;
    } else {
      delete navigator.sendBeacon;
    }

    globalThis.fetch = originalFetch;
    window.addEventListener = originalWindowAddEventListener;
    document.addEventListener = originalDocumentAddEventListener;
    listenersToRemove.forEach((removeListener) => removeListener());

    if (originalVisibilityState) {
      Object.defineProperty(Document.prototype, "visibilityState", originalVisibilityState);
    }
    delete document.visibilityState;
  });

  it("sends a beacon for visible community page views", () => {
    trackPageView({ entityId: "cncf", entityType: "community" });

    expect(beaconCalls).to.have.length(1);
    expect(beaconCalls[0].endpoint).to.equal("/communities/cncf/views");
    expect(fetchCalls).to.have.length(0);
  });

  it("falls back to fetch when sendBeacon does not queue the event", async () => {
    navigator.sendBeacon = (endpoint, payload) => {
      beaconCalls.push({ endpoint, payload });
      return false;
    };

    trackPageView({ entityId: "123", entityType: "event" });
    await waitForMicrotask();

    expect(beaconCalls).to.have.length(1);
    expect(fetchCalls).to.deep.equal([
      ["/events/123/views", { method: "POST", keepalive: true }],
    ]);
  });

  it("queues hidden page views until the document becomes visible", () => {
    visibilityState = "hidden";

    trackPageView({ entityId: "group-a", entityType: "group" });

    expect(beaconCalls).to.have.length(0);
    expect(window.__ocgPageViewTracker.pendingViews).to.equal(1);

    visibilityState = "visible";
    document.dispatchEvent(new Event("visibilitychange"));

    expect(beaconCalls).to.have.length(1);
    expect(beaconCalls[0].endpoint).to.equal("/groups/group-a/views");
    expect(window.__ocgPageViewTracker.pendingViews).to.equal(0);
  });

  it("replays page views when a persisted page is shown again", () => {
    trackPageView({ entityId: "cncf", entityType: "community" });
    expect(beaconCalls).to.have.length(1);

    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

    expect(beaconCalls).to.have.length(2);
    expect(beaconCalls[1].endpoint).to.equal("/communities/cncf/views");
  });

  it("ignores incomplete tracking payloads", () => {
    trackPageView({ entityId: "", entityType: "community" });
    trackPageView({ entityId: "cncf", entityType: "" });

    expect(beaconCalls).to.have.length(0);
    expect(fetchCalls).to.have.length(0);
  });
});
