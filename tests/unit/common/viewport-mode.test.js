import { expect } from "@open-wc/testing";

import {
  DESKTOP_MODE,
  VIEWPORT_MODE_ATTRIBUTE,
  VIEWPORT_MODE_STORAGE_KEY,
  getViewportModeReloadUrl,
  initViewportModeToggle,
  setViewportMode,
  setViewportModeReloadHandler,
} from "/static/js/common/viewport-mode.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const EXPIRED_LEGACY_COOKIE = "ocg_viewport_mode=; Path=/; Max-Age=0; SameSite=Lax";

/**
 * Intercepts document.cookie without touching the real cookie jar.
 * @param {string} [readable=""] - Cookie string the getter returns.
 * @returns {{readable: string, restore: () => void, writes: string[]}} Recorded writes and controls.
 */
const interceptCookieWrites = (readable = "") => {
  const writes = [];
  const cookies = { readable };

  Object.defineProperty(document, "cookie", {
    configurable: true,
    get: () => cookies.readable,
    set: (value) => {
      writes.push(value);
    },
  });

  return {
    get readable() {
      return cookies.readable;
    },
    set readable(value) {
      cookies.readable = value;
    },
    restore() {
      delete document.cookie;
    },
    writes,
  };
};

/**
 * Reads the stored viewport mode from the test page's real storage.
 * @returns {string|null} Stored mode.
 */
const readStoredMode = () => window.localStorage.getItem(VIEWPORT_MODE_STORAGE_KEY);

describe("viewport mode", () => {
  let cookieWrites;
  let reloadCount;

  beforeEach(() => {
    resetDom();
    reloadCount = 0;
    setViewportModeReloadHandler(() => {
      reloadCount += 1;
    });
    cookieWrites = interceptCookieWrites();
  });

  afterEach(() => {
    cookieWrites.restore();
    window.localStorage.removeItem(VIEWPORT_MODE_STORAGE_KEY);
    setViewportModeReloadHandler(() =>
      window.location.replace(getViewportModeReloadUrl(window.location.href)),
    );
    resetDom();
  });

  it("shares the storage key and attribute names with the inline preferences script", async () => {
    // Load the script the base template inlines to apply the mode before first paint.
    const response = await fetch("/ocg-server/templates/common/scripts/preferences_init.js");
    expect(response.ok).to.equal(true);
    const inlineScript = await response.text();

    // Verify both files agree on the storage key and the html attribute.
    expect(inlineScript).to.include(`"${VIEWPORT_MODE_STORAGE_KEY}"`);
    expect(inlineScript).to.include(`"${VIEWPORT_MODE_ATTRIBUTE}", "${DESKTOP_MODE}"`);
  });

  it("stores the desktop mode and reloads once", () => {
    // Enable the desktop mode.
    setViewportMode("desktop");

    // Verify the key is written and the page reloads once.
    expect(readStoredMode()).to.equal(DESKTOP_MODE);
    expect(reloadCount).to.equal(1);
  });

  it("removes the stored mode and reloads once for the default mode", () => {
    // Store the desktop mode, then restore the default one.
    window.localStorage.setItem(VIEWPORT_MODE_STORAGE_KEY, DESKTOP_MODE);
    setViewportMode("default");

    // Verify the key is removed and the page reloads once.
    expect(readStoredMode()).to.equal(null);
    expect(reloadCount).to.equal(1);
  });

  it("never sets a cookie for either mode", () => {
    // Select both modes.
    setViewportMode("desktop");
    setViewportMode("default");

    // Verify no cookie is written.
    expect(cookieWrites.writes).to.deep.equal([]);
    expect(reloadCount).to.equal(2);
  });

  it("neither reloads nor writes a cookie when storage rejects the write", () => {
    const originalSetItem = Storage.prototype.setItem;
    const originalRemoveItem = Storage.prototype.removeItem;
    Storage.prototype.setItem = () => {
      throw new DOMException("Blocked", "SecurityError");
    };
    Storage.prototype.removeItem = () => {
      throw new DOMException("Blocked", "SecurityError");
    };

    try {
      // Select both modes while storage throws.
      setViewportMode("desktop");
      setViewportMode("default");
    } finally {
      Storage.prototype.setItem = originalSetItem;
      Storage.prototype.removeItem = originalRemoveItem;
    }

    // Verify the page stays and no cookie is touched.
    expect(reloadCount).to.equal(0);
    expect(cookieWrites.writes).to.deep.equal([]);
  });

  it("expires a readable legacy cookie before reloading", () => {
    // Make a legacy cookie readable, as a tab loaded before the release can rewrite it.
    cookieWrites.readable = "theme=x; ocg_viewport_mode=desktop";
    let writesAtReload = null;
    setViewportModeReloadHandler(() => {
      reloadCount += 1;
      writesAtReload = [...cookieWrites.writes];
    });

    // Enable the desktop mode.
    setViewportMode("desktop");

    // Verify exactly one expiring write happens before the reload.
    expect(cookieWrites.writes).to.deep.equal([EXPIRED_LEGACY_COOKIE]);
    expect(writesAtReload).to.deep.equal([EXPIRED_LEGACY_COOKIE]);
    expect(reloadCount).to.equal(1);

    // Restore the default mode with the legacy cookie still readable.
    setViewportMode("default");

    // Verify the default mode expires it the same way.
    expect(cookieWrites.writes).to.deep.equal([EXPIRED_LEGACY_COOKIE, EXPIRED_LEGACY_COOKIE]);
    expect(writesAtReload).to.deep.equal([EXPIRED_LEGACY_COOKIE, EXPIRED_LEGACY_COOKIE]);
    expect(reloadCount).to.equal(2);
  });

  it("leaves look-alike cookies alone", () => {
    // Make only a cookie whose name merely ends with the key readable.
    cookieWrites.readable = "xocg_viewport_mode=desktop";

    // Select both modes.
    setViewportMode("desktop");
    setViewportMode("default");

    // Verify no cookie is written.
    expect(cookieWrites.writes).to.deep.equal([]);
    expect(reloadCount).to.equal(2);
  });

  it("applies the mode of the clicked menu entry through document delegation", () => {
    // Render the menu fragment the header macro produces.
    document.body.innerHTML = `
      <ul role="none">
        <li role="none">
          <button type="button" data-viewport-mode="desktop" role="menuitem">
            <span class="flex items-center">
              <span class="svg-icon size-4 icon-desktop bg-stone-600"></span>
              <span id="desktop-label" class="ms-2 text-xs/6">Desktop version</span>
            </span>
          </button>
        </li>
        <li role="none">
          <button type="button" data-viewport-mode="default" role="menuitem">
            <span id="mobile-label" class="ms-2 text-xs/6">Mobile version</span>
          </button>
        </li>
      </ul>
    `;

    // Calling the initializer again must not bind a second listener.
    initViewportModeToggle();

    // Click the inner label of the desktop entry.
    document.getElementById("desktop-label").dispatchEvent(new MouseEvent("click", { bubbles: true }));

    // Verify the desktop mode is stored and the page reloads exactly once.
    expect(readStoredMode()).to.equal(DESKTOP_MODE);
    expect(reloadCount).to.equal(1);

    // Click the mobile entry.
    document.getElementById("mobile-label").dispatchEvent(new MouseEvent("click", { bubbles: true }));

    // Verify the stored mode is cleared and the page reloads once more.
    expect(readStoredMode()).to.equal(null);
    expect(reloadCount).to.equal(2);
    expect(cookieWrites.writes).to.deep.equal([]);
  });

  it("ignores clicks outside the viewport mode controls", () => {
    // Render an unrelated menu link.
    document.body.innerHTML = `<a id="other-link" href="/">Home</a>`;

    // Click the link while preventing navigation.
    document.addEventListener("click", (event) => event.preventDefault(), { once: true });
    document
      .getElementById("other-link")
      .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    // Verify nothing is stored and no reload happens.
    expect(readStoredMode()).to.equal(null);
    expect(reloadCount).to.equal(0);
  });

  it("does not treat the active mode attribute on the document root as a control", () => {
    // Mark the document as already being in desktop mode, as the base template initializer does.
    document.documentElement.setAttribute(VIEWPORT_MODE_ATTRIBUTE, DESKTOP_MODE);
    document.body.innerHTML = `<a id="other-link" href="/">Home</a>`;

    try {
      // Click an ordinary element whose ancestors include the marked root.
      document.addEventListener("click", (event) => event.preventDefault(), { once: true });
      document
        .getElementById("other-link")
        .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      // Verify nothing is stored and the page does not reload.
      expect(readStoredMode()).to.equal(null);
      expect(reloadCount).to.equal(0);
    } finally {
      document.documentElement.removeAttribute(VIEWPORT_MODE_ATTRIBUTE);
    }
  });

  it("reloads the current URL without its hash", () => {
    // Verify a hash is dropped, since replacing to it would only scroll.
    expect(getViewportModeReloadUrl("https://example.com/docs?page=2#setup")).to.equal(
      "https://example.com/docs?page=2",
    );
    expect(getViewportModeReloadUrl("https://example.com/explore?entity=events")).to.equal(
      "https://example.com/explore?entity=events",
    );
  });
});
