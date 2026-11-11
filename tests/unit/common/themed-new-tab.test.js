import { expect } from "@open-wc/testing";

import "/static/js/common/themed-new-tab.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

const CREDENTIAL_PATH = "/badges/credentials/11111111-1111-1111-1111-111111111111";
const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";
// Theme tokens the placeholder reads from the opener.
const TOKENS = {
  "--color-primary-fg": "rgb(10, 20, 30)",
  "--color-stone-200": "rgb(40, 50, 60)",
  "--color-stone-600": "rgb(70, 80, 90)",
  "--color-surface": "rgb(1, 2, 3)",
};

describe("themed new tab", () => {
  let media;
  let opener;

  beforeEach(() => {
    resetDom();
    media = stubMatchMedia();
    Object.entries(TOKENS).forEach(([name, value]) => {
      document.documentElement.style.setProperty(name, value);
    });
    document.documentElement.style.colorScheme = "dark";
  });

  afterEach(() => {
    opener?.restore();
    opener = null;
    media.restore();
    resetDom();
  });

  it("opens a plain click in a themed tab and follows the link from it", () => {
    // Render a marked link and hand out a tab.
    const link = renderLink();
    opener = stubWindowOpen();

    // Click the link.
    const event = clickLink(link);

    // Verify the module opened an empty tab itself and cut its reference to this page.
    expect(event.defaultPrevented).to.equal(true);
    expect(opener.calls).to.deep.equal([["", "_blank"]]);
    expect(opener.tab.opener).to.equal(null);

    // Verify the placeholder shows the opener's theme and announces itself.
    const tabDocument = opener.tab.document;
    const status = tabDocument.querySelector('[role="status"]');
    const spinner = tabDocument.querySelector('[aria-hidden="true"]');
    expect(tabDocument.title).to.equal("Opening…");
    expect(tabDocument.documentElement.style.colorScheme).to.equal("dark");
    expect(tabDocument.body.style.backgroundColor).to.equal(TOKENS["--color-surface"]);
    expect(tabDocument.body.style.color).to.equal(TOKENS["--color-stone-600"]);
    expect(status.textContent).to.equal("Opening…");
    expect(spinner.style.borderTopColor).to.equal(TOKENS["--color-primary-fg"]);
    expect(spinner.getAnimations()).to.have.length(1);

    // Verify the tab follows the link itself, with a referrer as the link allows.
    expect(opener.followed).to.deep.equal([{ href: link.href, rel: "" }]);
  });

  it("sends no referrer when the link forbids it", () => {
    // Render a link that carries noreferrer.
    const link = renderLink({ rel: "noopener noreferrer" });
    opener = stubWindowOpen();

    // Click the link.
    clickLink(link);

    // Verify the navigation keeps the rule.
    expect(opener.followed).to.deep.equal([{ href: link.href, rel: "noreferrer" }]);
  });

  it("keeps the spinner still under reduced motion", () => {
    // Render a link for a viewer who asked for reduced motion.
    media.setMatches(REDUCED_MOTION_QUERY, true);
    const link = renderLink();
    opener = stubWindowOpen();

    // Click the link.
    clickLink(link);

    // Verify the placeholder shows without the turning ring.
    const spinner = opener.tab.document.querySelector('[aria-hidden="true"]');
    expect(spinner.getAnimations()).to.have.length(0);
    expect(opener.followed).to.have.length(1);
  });

  it("leaves modified clicks, other buttons and unmarked links to the browser", () => {
    // Render one marked and one unmarked link.
    const link = renderLink();
    const unmarkedLink = renderLink({ marked: false });
    opener = stubWindowOpen();

    // Click with a modifier, with the middle button, and on the unmarked link.
    const events = [
      clickLink(link, { ctrlKey: true }),
      clickLink(link, { metaKey: true }),
      clickLink(link, { shiftKey: true }),
      clickLink(link, { button: 1 }),
      clickLink(unmarkedLink),
    ];

    // Verify the native link handled every one of them.
    expect(events.map((event) => event.defaultPrevented)).to.deep.equal([false, false, false, false, false]);
    expect(opener.calls).to.deep.equal([]);
  });

  it("keeps the native link when the browser blocks the tab", () => {
    // Render a marked link while tabs opened from script are blocked.
    const link = renderLink();
    opener = stubWindowOpen({ blocked: true });

    // Click the link.
    const event = clickLink(link);

    // Verify the click still reaches the link's own target.
    expect(opener.calls).to.have.length(1);
    expect(event.defaultPrevented).to.equal(false);
  });
});

/**
 * Clicks a link and reports whether the module took the click over. The click never navigates
 * the test page.
 * @param {HTMLAnchorElement} link - Link to click.
 * @param {MouseEventInit} [init] - Click overrides, such as a modifier key.
 * @returns {{defaultPrevented: boolean}} State of the click once the document handled it.
 */
const clickLink = (link, init = {}) => {
  const result = { defaultPrevented: false };
  window.addEventListener(
    "click",
    (event) => {
      result.defaultPrevented = event.defaultPrevented;
      event.preventDefault();
    },
    { once: true },
  );
  link.dispatchEvent(new MouseEvent("click", { bubbles: true, button: 0, cancelable: true, ...init }));
  return result;
};

/**
 * Renders a new-tab link like the dashboard templates do.
 * @param {{marked?: boolean, rel?: string}} [options] - Whether the link opts in, and its rel.
 * @returns {HTMLAnchorElement} Rendered link.
 */
const renderLink = ({ marked = true, rel = "noopener" } = {}) => {
  const link = document.createElement("a");
  link.href = CREDENTIAL_PATH;
  link.rel = rel;
  link.target = "_blank";
  link.toggleAttribute("data-themed-new-tab", marked);
  link.innerHTML = '<span class="svg-icon"></span>';
  document.body.append(link);
  return link.firstElementChild.parentElement;
};

/**
 * Replaces `window.open` with a double that hands out a tab holding a detached document, and
 * records the links that document follows.
 * @param {{blocked?: boolean}} [options] - Whether the browser refuses the tab.
 * @returns {{calls: Array<unknown[]>, followed: Array<{href: string, rel: string}>,
 *   restore: () => void, tab: {document: Document, opener: unknown}}} Controls.
 */
const stubWindowOpen = ({ blocked = false } = {}) => {
  const calls = [];
  const followed = [];
  const originalOpen = window.open;
  const tabDocument = document.implementation.createHTMLDocument("");
  tabDocument.addEventListener("click", (event) => {
    followed.push({ href: event.target.href, rel: event.target.rel });
  });
  const tab = { document: tabDocument, opener: window };

  window.open = (...args) => {
    calls.push(args);
    return blocked ? null : tab;
  };

  return {
    calls,
    followed,
    restore: () => {
      window.open = originalOpen;
    },
    tab,
  };
};
