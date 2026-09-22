import { expect } from "@open-wc/testing";

import {
  DESKTOP_MODE,
  VIEWPORT_MODE_ATTRIBUTE,
  VIEWPORT_MODE_COOKIE,
  buildViewportModeCookie,
  initViewportModeToggle,
  setViewportMode,
  setViewportModeReloadHandler,
} from "/static/js/common/viewport-mode.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const DESKTOP_COOKIE = "ocg_viewport_mode=desktop; Path=/; Max-Age=31536000; SameSite=Lax";
const CLEARED_COOKIE = "ocg_viewport_mode=; Path=/; Max-Age=0; SameSite=Lax";

/** Intercepts document.cookie writes without touching the real cookie jar. */
const interceptCookieWrites = () => {
  const writes = [];

  Object.defineProperty(document, "cookie", {
    configurable: true,
    get: () => "",
    set: (value) => {
      writes.push(value);
    },
  });

  return {
    writes,
    restore() {
      delete document.cookie;
    },
  };
};

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
    setViewportModeReloadHandler(() => window.location.reload());
    resetDom();
  });

  it("shares the cookie and attribute names with the base template initializer", async () => {
    // Load the base template that applies the mode before first paint.
    const response = await fetch("/ocg-server/templates/common/base.html");
    expect(response.ok).to.equal(true);
    const template = await response.text();
    const inlineScript = [...template.matchAll(/<script>([\s\S]*?)<\/script>/g)]
      .map((match) => match[1])
      .find((body) => body.includes(VIEWPORT_MODE_COOKIE));
    expect(inlineScript, "viewport mode initializer").not.to.equal(undefined);

    // Verify both files agree on the persisted cookie pair and the html attribute.
    expect(inlineScript).to.include(`"${VIEWPORT_MODE_COOKIE}=${DESKTOP_MODE}"`);
    expect(inlineScript).to.include(`"${VIEWPORT_MODE_ATTRIBUTE}", "${DESKTOP_MODE}"`);
  });

  it("builds a long-lived site-wide cookie for the desktop mode", () => {
    // Verify the plain cookie used on HTTP development servers.
    expect(buildViewportModeCookie("desktop")).to.equal(DESKTOP_COOKIE);

    // Verify HTTPS pages add the Secure attribute.
    expect(buildViewportModeCookie("desktop", { secure: true })).to.equal(`${DESKTOP_COOKIE}; Secure`);
  });

  it("builds an expiring cookie on the same path for any other mode", () => {
    // Verify clearing reuses the path so the browser removes the stored cookie.
    expect(buildViewportModeCookie("default")).to.equal(CLEARED_COOKIE);
    expect(buildViewportModeCookie("", { secure: true })).to.equal(`${CLEARED_COOKIE}; Secure`);
  });

  it("writes the cookie and reloads once when a mode is selected", () => {
    // Enable the desktop mode from the page served over HTTP.
    setViewportMode("desktop");

    // Verify the cookie is written without Secure and the page reloads once.
    expect(cookieWrites.writes).to.deep.equal([DESKTOP_COOKIE]);
    expect(reloadCount).to.equal(1);

    // Restore the default mode.
    setViewportMode("default");

    // Verify the cookie is cleared and the page reloads again.
    expect(cookieWrites.writes).to.deep.equal([DESKTOP_COOKIE, CLEARED_COOKIE]);
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

    // Verify the desktop cookie is written and the page reloads exactly once.
    expect(cookieWrites.writes).to.deep.equal([DESKTOP_COOKIE]);
    expect(reloadCount).to.equal(1);

    // Click the mobile entry.
    document.getElementById("mobile-label").dispatchEvent(new MouseEvent("click", { bubbles: true }));

    // Verify the cookie is cleared and the page reloads once more.
    expect(cookieWrites.writes).to.deep.equal([DESKTOP_COOKIE, CLEARED_COOKIE]);
    expect(reloadCount).to.equal(2);
  });

  it("ignores clicks outside the viewport mode controls", () => {
    // Render an unrelated menu link.
    document.body.innerHTML = `<a id="other-link" href="/">Home</a>`;

    // Click the link while preventing navigation.
    document.addEventListener("click", (event) => event.preventDefault(), { once: true });
    document
      .getElementById("other-link")
      .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    // Verify nothing is written and no reload happens.
    expect(cookieWrites.writes).to.deep.equal([]);
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

      // Verify the page is neither re-marked nor reloaded.
      expect(cookieWrites.writes).to.deep.equal([]);
      expect(reloadCount).to.equal(0);
    } finally {
      document.documentElement.removeAttribute(VIEWPORT_MODE_ATTRIBUTE);
    }
  });
});
