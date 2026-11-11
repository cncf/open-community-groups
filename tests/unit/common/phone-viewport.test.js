import { expect } from "@open-wc/testing";

import { holdScreenAwake, isPhoneViewport, PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";
import { mockWakeLock, restorePageVisibility, setPageVisibility } from "/tests/unit/test-utils/wake-lock.js";

/**
 * Loads a repository file served by the test runner.
 * @param {string} path - Repository path.
 * @returns {Promise<string>} File text.
 */
const loadFile = async (path) => {
  const response = await fetch(path);

  expect(response.ok, path).to.equal(true);

  return response.text();
};

describe("phone viewport", () => {
  let media;

  afterEach(() => {
    media?.restore();
  });

  it("matches the phone query", () => {
    // Stub a matching query that records what it receives.
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });

    // Verify the shared query reaches matchMedia.
    expect(isPhoneViewport()).to.equal(true);
    expect(media.calls).to.deep.equal([PHONE_MEDIA_QUERY]);
  });

  it("reports false when the query does not match", () => {
    media = stubMatchMedia();

    expect(isPhoneViewport()).to.equal(false);
  });

  it("reports false without matchMedia", () => {
    // Remove matchMedia, which the shared stub does not model.
    const originalMatchMedia = window.matchMedia;
    window.matchMedia = undefined;

    try {
      expect(isPhoneViewport()).to.equal(false);
    } finally {
      window.matchMedia = originalMatchMedia;
    }
  });

  it("does not match a fine pointer or print", () => {
    // Test browsers have a fine pointer, so the real query stays false at any width.
    expect(window.matchMedia(PHONE_MEDIA_QUERY).media).to.equal(PHONE_MEDIA_QUERY);
    expect(isPhoneViewport()).to.equal(false);
  });

  it("uses the same query text as the stylesheets", async () => {
    const mediaRule = `@media ${PHONE_MEDIA_QUERY} {`;

    // Verify the sources that repeat the query text.
    const sources = [
      "/ocg-server/static/css/styles.src.css",
      "/ocg-server/static/docs/assets/shell.css",
    ];
    for (const source of sources) {
      expect(await loadFile(source), source).to.include(mediaRule);
    }
  });
});

describe("holdScreenAwake", () => {
  let media;
  let wakeLock;

  beforeEach(() => {
    wakeLock = mockWakeLock();
  });

  afterEach(() => {
    media?.restore();
    wakeLock.restore();
    restorePageVisibility();
  });

  /** Tracks visibilitychange listeners added to the document during a test. */
  const trackVisibilityListeners = () => {
    const listeners = new Set();
    const { addEventListener, removeEventListener } = document;
    document.addEventListener = function (type, listener, options) {
      if (type === "visibilitychange") listeners.add(listener);
      addEventListener.call(this, type, listener, options);
    };
    document.removeEventListener = function (type, listener, options) {
      if (type === "visibilitychange") listeners.delete(listener);
      removeEventListener.call(this, type, listener, options);
    };
    return {
      listeners,
      restore: () => {
        delete document.addEventListener;
        delete document.removeEventListener;
      },
    };
  };

  it("does nothing off phones", async () => {
    // Hold the screen while the phone query is false.
    media = stubMatchMedia();
    const visibility = trackVisibilityListeners();
    const release = holdScreenAwake();
    await waitForMicrotask();

    // Verify nothing was requested and no listener was added.
    expect(wakeLock.requests).to.deep.equal([]);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
    expect(visibility.listeners.size).to.equal(0);

    // Verify the returned release is safe to call.
    release();
    visibility.restore();
  });

  it("does nothing without the API", () => {
    // Remove the API from a phone.
    wakeLock.restore();
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
    const original = Object.getOwnPropertyDescriptor(Navigator.prototype, "wakeLock");
    delete Navigator.prototype.wakeLock;

    // Verify holding and releasing add nothing.
    try {
      const release = holdScreenAwake();
      expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
      release();
    } finally {
      if (original) Object.defineProperty(Navigator.prototype, "wakeLock", original);
    }
  });

  it("requests a screen lock on phones and releases it", async () => {
    // Hold the screen on a phone.
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
    const visibility = trackVisibilityListeners();
    const release = holdScreenAwake();
    await waitForMicrotask();

    // Verify one screen lock was taken.
    expect(wakeLock.requests).to.deep.equal(["screen"]);
    expect(wakeLock.locks[0].released).to.equal(false);

    // Release and verify the lock and every listener are gone.
    release();
    await waitForMicrotask();
    expect(wakeLock.locks[0].released).to.equal(true);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
    expect(visibility.listeners.size).to.equal(0);
    visibility.restore();
  });

  it("requests the lock again when the page returns", async () => {
    // Hold the screen, then lose the lock as the browser does when the page hides.
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
    const release = holdScreenAwake();
    await waitForMicrotask();
    wakeLock.locks[0].released = true;
    setPageVisibility("hidden");
    await waitForMicrotask();

    // Verify nothing is requested while hidden, and one lock returns with the page.
    expect(wakeLock.requests.length).to.equal(1);
    setPageVisibility("visible");
    await waitForMicrotask();
    expect(wakeLock.requests.length).to.equal(2);

    // Verify a visible page with a live lock requests nothing more.
    setPageVisibility("visible");
    await waitForMicrotask();
    expect(wakeLock.requests.length).to.equal(2);
    release();
  });

  it("stops requesting after release", async () => {
    // Release a held lock.
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
    const release = holdScreenAwake();
    await waitForMicrotask();
    release();

    // Verify a later return to the page takes no lock.
    setPageVisibility("visible");
    await waitForMicrotask();
    expect(wakeLock.requests.length).to.equal(1);
  });

  it("releases a lock granted after the release", async () => {
    // Release before the request resolves.
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
    const release = holdScreenAwake();
    release();
    await waitForMicrotask();

    // Verify the late lock does not stay held.
    expect(wakeLock.locks.length).to.equal(1);
    expect(wakeLock.locks[0].released).to.equal(true);
  });

  it("survives a refused lock and tries again on return", async () => {
    // Refuse the first request.
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
    wakeLock.reject(new DOMException("Refused", "NotAllowedError"));
    const release = holdScreenAwake();
    await waitForMicrotask();
    expect(wakeLock.locks.length).to.equal(0);

    // Verify the next return to the page takes the lock.
    setPageVisibility("visible");
    await waitForMicrotask();
    expect(wakeLock.locks.length).to.equal(1);
    release();
  });

  it("releases while the query is false and resumes when it returns", async () => {
    // Hold the screen, then rotate past the phone width.
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
    const visibility = trackVisibilityListeners();
    const release = holdScreenAwake();
    await waitForMicrotask();
    media.setMatches(PHONE_MEDIA_QUERY, false);
    await waitForMicrotask();

    // Verify the lock and the page listener are gone off phones.
    expect(wakeLock.locks[0].released).to.equal(true);
    expect(visibility.listeners.size).to.equal(0);
    setPageVisibility("visible");
    await waitForMicrotask();
    expect(wakeLock.requests.length).to.equal(1);

    // Rotate back and verify the hold resumes.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForMicrotask();
    expect(wakeLock.requests.length).to.equal(2);
    expect(wakeLock.locks[1].released).to.equal(false);

    // Close and verify nothing stays attached.
    release();
    await waitForMicrotask();
    expect(wakeLock.locks[1].released).to.equal(true);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
    expect(visibility.listeners.size).to.equal(0);
    visibility.restore();
  });
});
