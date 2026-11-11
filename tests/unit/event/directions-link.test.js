import { expect } from "@open-wc/testing";

import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

const ANDROID_USER_AGENT =
  "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36";
const CHROME_IPHONE_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.54 Mobile/15E148 Safari/604.1";
const IPAD_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15";
const IPHONE_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1";

const APPLE_COORDINATES_URL = "https://maps.apple.com/directions?destination=40.7128,-74.006";
const GOOGLE_COORDINATES_URL =
  "https://www.google.com/maps/dir/?api=1&destination=40.7128%2C-74.006";

const originalAddEventListener = document.addEventListener;

/**
 * Renders one directions link.
 * @param {string} href Link URL.
 * @returns {HTMLAnchorElement} Rendered link.
 */
const renderLink = (href = GOOGLE_COORDINATES_URL) => {
  document.body.innerHTML = `<a data-directions-link href="${href}">Directions</a>`;

  return document.querySelector("[data-directions-link]");
};

describe("directions link", () => {
  /** Listeners the module added to the document, removed after each test. */
  let documentListeners = [];
  let buildAppleMapsUrl;
  let initializeDirectionsLinks;
  let media;

  before(async () => {
    // Record what loading the module does on this desktop browser.
    const loadTimeListeners = [];
    document.addEventListener = function addEventListener(type, ...rest) {
      loadTimeListeners.push(type);
      return originalAddEventListener.call(this, type, ...rest);
    };

    ({ buildAppleMapsUrl, initializeDirectionsLinks } = await import(
      "/static/js/event/directions-link.js"
    ));
    document.addEventListener = originalAddEventListener;

    expect(loadTimeListeners).to.deep.equal([]);
  });

  beforeEach(() => {
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
    document.addEventListener = function addEventListener(type, listener, ...rest) {
      documentListeners.push([type, listener]);
      return originalAddEventListener.call(this, type, listener, ...rest);
    };
  });

  afterEach(() => {
    documentListeners.forEach(([type, listener]) => document.removeEventListener(type, listener));
    documentListeners = [];
    document.addEventListener = originalAddEventListener;
    media?.restore();
    resetDom();
  });

  it("swaps a coordinates link to Apple Maps on an iPhone", () => {
    const link = renderLink();

    initializeDirectionsLinks(IPHONE_USER_AGENT);

    expect(link.href).to.equal(APPLE_COORDINATES_URL);
  });

  it("treats Chrome on an iPhone as an iPhone", () => {
    const link = renderLink();

    initializeDirectionsLinks(CHROME_IPHONE_USER_AGENT);

    expect(link.href).to.equal(APPLE_COORDINATES_URL);
  });

  it("encodes an address and keeps its commas", () => {
    // Spaces arrive as plus signs from the server's form encoding.
    const link = renderLink(
      "https://www.google.com/maps/dir/?api=1&destination=Caf%C3%A9+%26+Bar%2C+1+Main+St%2C+Seattle",
    );

    initializeDirectionsLinks(IPHONE_USER_AGENT);

    expect(link.href).to.equal(
      "https://maps.apple.com/directions?destination=Caf%C3%A9%20%26%20Bar,%201%20Main%20St,%20Seattle",
    );
  });

  it("leaves a link without a destination alone", () => {
    const href = "https://www.google.com/maps/dir/?api=1";
    const link = renderLink(href);

    initializeDirectionsLinks(IPHONE_USER_AGENT);

    expect(link.href).to.equal(href);
    expect(buildAppleMapsUrl(href)).to.equal(null);
  });

  it("skips a link already on Apple Maps", () => {
    const link = renderLink(APPLE_COORDINATES_URL);
    const observer = new MutationObserver(() => {});
    observer.observe(link, { attributes: true });

    initializeDirectionsLinks(IPHONE_USER_AGENT);

    expect(link.href).to.equal(APPLE_COORDINATES_URL);
    expect(observer.takeRecords()).to.have.length(0);
    observer.disconnect();
  });

  it("swaps links that arrive through HTMX and history", () => {
    renderLink();
    initializeDirectionsLinks(IPHONE_USER_AGENT);

    // A swapped fragment whose root is the link itself.
    const swappedLink = renderLink();
    swappedLink.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
    expect(swappedLink.href).to.equal(APPLE_COORDINATES_URL);

    // A snapshot restored with the server's Google link.
    const restoredLink = renderLink();
    document.dispatchEvent(new CustomEvent("htmx:historyRestore"));
    expect(restoredLink.href).to.equal(APPLE_COORDINATES_URL);
  });

  it("does nothing while the phone query is false", () => {
    const link = renderLink();
    media.setMatches(PHONE_MEDIA_QUERY, false);

    initializeDirectionsLinks(IPHONE_USER_AGENT);
    document.dispatchEvent(new CustomEvent("htmx:load"));

    expect(link.href).to.equal(GOOGLE_COORDINATES_URL);
  });

  it("swaps after rotating into the phone layout", () => {
    const link = renderLink();
    media.setMatches(PHONE_MEDIA_QUERY, false);
    initializeDirectionsLinks(IPHONE_USER_AGENT);

    media.setMatches(PHONE_MEDIA_QUERY, true);

    expect(link.href).to.equal(APPLE_COORDINATES_URL);
  });

  it("keeps one query listener on an iPhone", () => {
    renderLink();

    initializeDirectionsLinks(IPHONE_USER_AGENT);

    expect(media.calls.length).to.equal(1);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(1);
    expect(documentListeners.map(([type]) => type)).to.deep.equal([
      "htmx:load",
      "htmx:historyRestore",
    ]);
  });

  for (const [name, userAgent] of [
    ["Android", ANDROID_USER_AGENT],
    ["iPad", IPAD_USER_AGENT],
  ]) {
    it(`adds nothing on ${name}`, () => {
      const link = renderLink();

      initializeDirectionsLinks(userAgent);
      document.dispatchEvent(new CustomEvent("htmx:load"));

      expect(link.href).to.equal(GOOGLE_COORDINATES_URL);
      expect(media.calls.length).to.equal(0);
      expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
      expect(documentListeners).to.have.length(0);
    });
  }
});
