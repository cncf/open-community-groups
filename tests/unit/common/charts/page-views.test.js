import { expect } from "@open-wc/testing";

import {
  initializePageViewTracking,
  resetPageViewTracker,
  trackPageView,
} from "/static/js/common/charts/page-views.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom, setLocationPath, trackAddedEventListeners } from "/tests/unit/test-utils/dom.js";
import { mockFetch, mockSendBeacon, mockVisibilityState } from "/tests/unit/test-utils/network.js";

const HTMX_HISTORY_PATH_STORAGE_KEY = "htmx-current-path-for-history";

describe("page views", () => {
  let eventListeners;
  let fetchMock;
  let originalLocationPath;
  let sendBeaconMock;
  let visibilityState;

  beforeEach(() => {
    originalLocationPath = `${window.location.pathname}${window.location.search}${window.location.hash}`;
    resetDom();
    resetPageViewTracker();
    sessionStorage.removeItem(HTMX_HISTORY_PATH_STORAGE_KEY);
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
    sessionStorage.removeItem(HTMX_HISTORY_PATH_STORAGE_KEY);
    setLocationPath(originalLocationPath);
  });

  it("attributes event page views to UTM parameters and removes them from the URL", () => {
    // Load an event URL with UTM and unrelated parameters.
    setLocationPath(
      "/cncf/group/g/event/e?ref=home&utm_source=newsletter&utm_medium=&utm_campaign=launch#details",
    );
    history.replaceState({ htmx: true }, "", window.location.href);

    // Track the page view event.
    trackPageView({ entityId: "event-123", entityType: "event" });

    // The view carries the non-empty UTM parameters.
    expect(sendBeaconMock.calls).to.have.length(1);
    expect(sendBeaconMock.calls[0].endpoint).to.equal(
      "/events/event-123/views?utm_campaign=launch&utm_source=newsletter",
    );

    // The URL keeps everything except the UTM parameters, and the history state.
    expect(window.location.pathname).to.equal("/cncf/group/g/event/e");
    expect(window.location.search).to.equal("?ref=home");
    expect(window.location.hash).to.equal("#details");
    expect(history.state).to.deep.equal({ htmx: true });

    // No HTMX history path is recorded when HTMX has not recorded one.
    expect(sessionStorage.getItem(HTMX_HISTORY_PATH_STORAGE_KEY)).to.equal(null);
  });

  it("keeps the other query parameters exactly as written when removing UTM parameters", () => {
    // Load an event URL whose other parameters use encodings URLSearchParams would rewrite.
    const eventPath = "/cncf/group/g/event/e?q=a%20b&utm_source=newsletter&flag&x=1+2&utm%5Fcampaign=launch";
    setLocationPath(`${eventPath}#top`);
    sessionStorage.setItem(HTMX_HISTORY_PATH_STORAGE_KEY, eventPath);

    // Track the page view event.
    trackPageView({ entityId: "event-123", entityType: "event" });

    // The view carries the UTM parameters, including the percent-encoded name.
    expect(sendBeaconMock.calls.map(({ endpoint }) => endpoint)).to.deep.equal([
      "/events/event-123/views?utm_campaign=launch&utm_source=newsletter",
    ]);

    // Only the UTM segments are removed from the URL and the HTMX history path.
    expect(window.location.search).to.equal("?q=a%20b&flag&x=1+2");
    expect(window.location.hash).to.equal("#top");
    expect(sessionStorage.getItem(HTMX_HISTORY_PATH_STORAGE_KEY)).to.equal(
      "/cncf/group/g/event/e?q=a%20b&flag&x=1+2",
    );
  });

  it("leaves event URLs without UTM parameters untouched", () => {
    // Load an event URL without UTM parameters and a recorded HTMX history path.
    const eventPath = "/cncf/group/g/event/e?q=a%20b&flag";
    setLocationPath(eventPath);
    history.replaceState({ htmx: true }, "", eventPath);
    sessionStorage.setItem(HTMX_HISTORY_PATH_STORAGE_KEY, "/recorded");

    // Track the page view event.
    trackPageView({ entityId: "event-123", entityType: "event" });

    // The view is not attributed and the URL, state, and history path stay the same.
    expect(sendBeaconMock.calls.map(({ endpoint }) => endpoint)).to.deep.equal(["/events/event-123/views"]);
    expect(window.location.search).to.equal("?q=a%20b&flag");
    expect(history.state).to.deep.equal({ htmx: true });
    expect(sessionStorage.getItem(HTMX_HISTORY_PATH_STORAGE_KEY)).to.equal("/recorded");
  });

  it("keeps the HTMX history path in sync with the cleaned event URL", () => {
    // Load an event URL with UTM parameters recorded by HTMX as its history path.
    const eventPath = "/cncf/group/g/event/e?ref=home&utm_source=newsletter";
    setLocationPath(eventPath);
    sessionStorage.setItem(HTMX_HISTORY_PATH_STORAGE_KEY, eventPath);

    // Track the page view event.
    trackPageView({ entityId: "event-123", entityType: "event" });

    // HTMX saves the page snapshot under the cleaned URL restored on back navigation.
    expect(sessionStorage.getItem(HTMX_HISTORY_PATH_STORAGE_KEY)).to.equal("/cncf/group/g/event/e?ref=home");
  });

  it("keeps UTM parameters out of community and group page views", () => {
    // Load a URL with UTM parameters.
    setLocationPath("/cncf?utm_source=newsletter");

    // Track community and group page views.
    trackPageView({ entityId: "cncf", entityType: "community" });
    trackPageView({ entityId: "group-a", entityType: "group" });

    // The views and the URL are left untouched.
    expect(sendBeaconMock.calls.map(({ endpoint }) => endpoint)).to.deep.equal([
      "/communities/cncf/views",
      "/groups/group-a/views",
    ]);
    expect(window.location.search).to.equal("?utm_source=newsletter");
  });

  it("sends back-forward cache restores of event pages without UTM attribution", () => {
    // Load an event URL with UTM parameters.
    setLocationPath("/cncf/group/g/event/e?utm_source=newsletter");

    // Track the page view event and restore the page from the back-forward cache.
    trackPageView({ entityId: "event-123", entityType: "event" });
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

    // Only the first view carries the UTM parameters read before the URL was cleaned.
    expect(sendBeaconMock.calls.map(({ endpoint }) => endpoint)).to.deep.equal([
      "/events/event-123/views?utm_source=newsletter",
      "/events/event-123/views",
    ]);
    expect(window.location.search).to.equal("");
  });

  it("keeps the UTM attribution for the first view of a hidden event page", () => {
    // Load a hidden event page with UTM parameters.
    visibilityState.set("hidden");
    setLocationPath("/cncf/group/g/event/e?utm_campaign=launch");

    // Track the page view event and restore the page before it is shown.
    trackPageView({ entityId: "event-123", entityType: "event" });
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));
    expect(sendBeaconMock.calls).to.have.length(0);

    // Show the page.
    visibilityState.set("visible");
    document.dispatchEvent(new Event("visibilitychange"));

    // The queued views are sent once, and only the first one is attributed.
    expect(sendBeaconMock.calls.map(({ endpoint }) => endpoint)).to.deep.equal([
      "/events/event-123/views?utm_campaign=launch",
      "/events/event-123/views",
    ]);
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

  it("tracks a declarative page view marker when the marker is the root", () => {
    // Build the marker shape HTMX can provide as a loaded root.
    const marker = document.createElement("span");
    marker.dataset.pageView = "";
    marker.dataset.entityId = "group-123";
    marker.dataset.entityType = "group";

    // Initialize tracking from the marker itself.
    initializePageViewTracking(marker);

    // The marker sends one page view to the expected endpoint.
    expect(sendBeaconMock.calls).to.have.length(1);
    expect(sendBeaconMock.calls[0].endpoint).to.equal("/groups/group-123/views");
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

describe("page views HTMX history contract", () => {
  it("syncs the history path key used by the HTMX bundle the base template loads", async () => {
    // Find the HTMX bundle loaded by the base template.
    const template = await (await fetch("/ocg-server/templates/common/base.html")).text();
    const htmxBundlePath = template.match(
      /<script src="(\/static\/vendor\/js\/htmx\.v[\d.]+\.min\.js)">/,
    )?.[1];
    expect(htmxBundlePath).to.be.a("string");

    // The bundle records the history path under the key the tracker syncs.
    const bundle = await (await fetch(`/ocg-server${htmxBundlePath}`)).text();
    expect(bundle).to.include(`"${HTMX_HISTORY_PATH_STORAGE_KEY}"`);
  });
});
