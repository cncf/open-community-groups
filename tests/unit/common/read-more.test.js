import { expect, nextFrame, waitUntil } from "@open-wc/testing";

import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

const LONG_TEXT = "Long description text. ".repeat(80);

/** ResizeObserver double that counts live instances. */
class TrackedResizeObserver extends ResizeObserver {
  static live = 0;

  constructor(callback) {
    super(callback);
    TrackedResizeObserver.live += 1;
  }

  disconnect() {
    TrackedResizeObserver.live -= 1;
    super.disconnect();
  }
}

/**
 * Renders a read more block with the clip the phone section of styles.src.css applies.
 * @param {string} content Body markup.
 * @returns {{block: HTMLElement, body: HTMLElement, toggle: HTMLButtonElement}} Block parts.
 */
const renderBlock = (content) => {
  document.body.insertAdjacentHTML(
    "beforeend",
    `<div class="read-more">
      <div class="read-more-body">${content}</div>
      <button type="button" class="read-more-toggle" aria-expanded="false"><span data-read-more-label>Read more</span><span class="svg-icon" aria-hidden="true"></span></button>
    </div>`,
  );
  const block = document.body.lastElementChild;

  return {
    block,
    body: block.querySelector(".read-more-body"),
    toggle: block.querySelector(".read-more-toggle"),
  };
};

/**
 * Waits for the observer to report a block as overflowing.
 * @param {HTMLElement} block Read more block.
 * @returns {Promise<void>} Resolves when the toggle would show.
 */
const waitForOverflowing = (block) => waitUntil(() => block.hasAttribute("data-overflowing"));

describe("read-more", () => {
  const originalResizeObserver = window.ResizeObserver;
  const documentListenerTypes = [];
  let initializeReadMore;
  let media;
  let style;

  before(async () => {
    const originalAddEventListener = document.addEventListener;

    // Load the module once under a false query, recording what it attaches.
    media = stubMatchMedia();
    window.ResizeObserver = TrackedResizeObserver;
    document.addEventListener = function (type, ...args) {
      documentListenerTypes.push(type);
      return originalAddEventListener.call(this, type, ...args);
    };
    ({ initializeReadMore } = await import("/static/js/common/read-more.js"));
    document.addEventListener = originalAddEventListener;

    style = document.createElement("style");
    style.textContent = `
      .read-more:not([data-expanded]) .read-more-body { max-height: 3lh; overflow: hidden; }
      .read-more:not([data-expanded]) .read-more-body img { max-height: 4rem; }
    `;
    document.head.append(style);
  });

  afterEach(() => {
    media.setMatches(PHONE_MEDIA_QUERY, false);
    resetDom();
  });

  after(() => {
    style.remove();
    media.restore();
    window.ResizeObserver = originalResizeObserver;
  });

  it("keeps one query listener and the two helper listeners at any width", () => {
    // Verify load attached only the allowed always-on listeners.
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(1);
    expect(documentListenerTypes.toSorted()).to.deep.equal(["htmx:historyRestore", "htmx:load"]);
  });

  it("has no effect while the query is false", async () => {
    const { block, body, toggle } = renderBlock(`<p>${LONG_TEXT}<a href="#link">Link</a></p>`);

    // Run every entry point off phones.
    initializeReadMore();
    document.dispatchEvent(new CustomEvent("htmx:load"));
    document.dispatchEvent(new CustomEvent("htmx:historyRestore"));
    toggle.click();
    body.querySelector("a").focus();
    await nextFrame();

    // Verify nothing was observed or written.
    expect(TrackedResizeObserver.live).to.equal(0);
    expect(block.attributes).to.have.length(1);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    expect(toggle.textContent).to.equal("Read more");
  });

  it("shows the toggle only for clipped text", async () => {
    const short = renderBlock("<p>Short text.</p>");
    const long = renderBlock(`<p>${LONG_TEXT}</p>`);

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(long.block);

    // Verify the short block stayed without a toggle.
    expect(short.block.hasAttribute("data-overflowing")).to.equal(false);
  });

  it("toggles the text and keeps the toggle state in step", async () => {
    const { block, toggle } = renderBlock(`<p>${LONG_TEXT}</p>`);

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(block);

    // Expand through the toggle.
    toggle.click();
    expect(block.hasAttribute("data-expanded")).to.equal(true);
    expect(toggle.getAttribute("aria-expanded")).to.equal("true");
    expect(toggle.textContent).to.equal("Read less");
    await nextFrame();
    expect(block.hasAttribute("data-overflowing")).to.equal(true);

    // Collapse it again.
    toggle.click();
    expect(block.hasAttribute("data-expanded")).to.equal(false);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    expect(toggle.textContent).to.equal("Read more");

    // Verify the label swap keeps the caret.
    expect(toggle.querySelector(".svg-icon")).to.not.equal(null);
  });

  it("expands on a tap on clipped text but leaves links and open text alone", async () => {
    const { block, body, toggle } = renderBlock(`<p>${LONG_TEXT}<a href="#link"><span>Link</span></a></p>`);
    const link = body.querySelector("a");
    link.addEventListener("click", (event) => event.preventDefault());

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(block);

    // Verify a tap on a link keeps its own action.
    link.querySelector("span").click();
    expect(block.hasAttribute("data-expanded")).to.equal(false);

    // Verify a tap on the text opens it.
    body.querySelector("p").click();
    expect(block.hasAttribute("data-expanded")).to.equal(true);
    expect(toggle.textContent).to.equal("Read less");

    // Verify a tap on the open text does not close it.
    body.querySelector("p").click();
    expect(block.hasAttribute("data-expanded")).to.equal(true);
  });

  it("ignores taps on text with nothing clipped", async () => {
    const { block, body } = renderBlock("<p>Short text.</p>");

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await nextFrame();
    body.querySelector("p").click();

    // Verify a block with nothing hidden has no open state.
    expect(block.hasAttribute("data-expanded")).to.equal(false);
  });

  it("expands when focus lands inside clipped text", async () => {
    const { block, body, toggle } = renderBlock(`<p>${LONG_TEXT}<a href="#link">Link</a></p>`);

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(block);
    body.querySelector("a").focus();

    // Verify tabbing into the text opens it.
    expect(block.hasAttribute("data-expanded")).to.equal(true);
    expect(toggle.getAttribute("aria-expanded")).to.equal("true");
  });

  it("leaves unclipped text alone on focus", async () => {
    const { block, body } = renderBlock('<p><a href="#link">Link</a></p>');

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await nextFrame();
    body.querySelector("a").focus();

    // Verify a block with nothing hidden has no open state.
    expect(block.hasAttribute("data-expanded")).to.equal(false);
  });

  it("measures again when a child grows behind the cap", async () => {
    const { block, body } = renderBlock("<p>Short text.</p><p>More.</p>");

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await nextFrame();
    expect(block.hasAttribute("data-overflowing")).to.equal(false);

    // Grow a child, as a late image would.
    body.querySelector("p").textContent = LONG_TEXT;

    await waitForOverflowing(block);
  });

  it("drops the toggle when removed content ends the clipping", async () => {
    const { block, body } = renderBlock(`<p>Short text.</p><p id="late">${LONG_TEXT}</p>`);

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(block);

    // Remove the paragraph, as data-ocg-remove-broken-images does.
    body.querySelector("#late").remove();

    await waitUntil(() => !block.hasAttribute("data-overflowing"));
  });

  it("counts an image held at the cap as clipped", async () => {
    const { block, body } = renderBlock('<img alt="" style="display: block; height: auto;">');
    const image = body.querySelector("img");
    const canvas = document.createElement("canvas");

    canvas.width = 40;
    canvas.height = 400;
    image.src = canvas.toDataURL();
    await image.decode();

    media.setMatches(PHONE_MEDIA_QUERY, true);

    await waitForOverflowing(block);
  });

  it("leaves no state or observers after the query turns false with a block open", async () => {
    const { block, toggle } = renderBlock(`<p>${LONG_TEXT}</p>`);

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(block);
    toggle.click();
    expect(TrackedResizeObserver.live).to.equal(1);

    media.setMatches(PHONE_MEDIA_QUERY, false);

    // Verify the state and the observer are gone.
    expect(TrackedResizeObserver.live).to.equal(0);
    expect(block.hasAttribute("data-expanded")).to.equal(false);
    expect(block.hasAttribute("data-overflowing")).to.equal(false);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    expect(toggle.textContent).to.equal("Read more");

    // Verify the toggle and the page listeners no longer act.
    toggle.click();
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));
    await nextFrame();
    expect(block.attributes).to.have.length(1);
  });

  it("binds again when the query turns true", async () => {
    const { block, toggle } = renderBlock(`<p>${LONG_TEXT}</p>`);

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(block);
    media.setMatches(PHONE_MEDIA_QUERY, false);
    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(block);
    toggle.click();

    // Verify one observer and one click listener survive the round trip.
    expect(TrackedResizeObserver.live).to.equal(1);
    expect(block.hasAttribute("data-expanded")).to.equal(true);
  });

  it("releases swapped-out blocks and binds their replacements once", async () => {
    const swapped = renderBlock(`<p>${LONG_TEXT}</p>`);

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(swapped.block);

    // Swap the content, with htmx:load firing for each new top-level node.
    swapped.block.remove();
    const { block, toggle } = renderBlock(`<p>${LONG_TEXT}</p>`);
    block.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
    block.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
    await waitForOverflowing(block);
    toggle.click();

    // Verify only the new block is observed and its click ran once.
    expect(TrackedResizeObserver.live).to.equal(1);
    expect(block.hasAttribute("data-expanded")).to.equal(true);
  });

  it("collapses open blocks before the history snapshot", async () => {
    const { block, toggle } = renderBlock(`<p>${LONG_TEXT}</p>`);

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(block);
    toggle.click();

    document.dispatchEvent(new CustomEvent("htmx:beforeHistorySave"));

    // Verify the snapshot would carry a closed block.
    expect(block.hasAttribute("data-expanded")).to.equal(false);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    expect(toggle.textContent).to.equal("Read more");
  });

  it("resets stale state from restored markup", async () => {
    media.setMatches(PHONE_MEDIA_QUERY, true);

    // Restore a snapshot that still carries an open, overflowing short block.
    const { block, toggle } = renderBlock("<p>Short text.</p>");
    block.setAttribute("data-expanded", "");
    block.setAttribute("data-overflowing", "");
    toggle.setAttribute("aria-expanded", "true");
    toggle.querySelector("[data-read-more-label]").textContent = "Read less";
    document.dispatchEvent(new CustomEvent("htmx:historyRestore"));

    await waitUntil(() => !block.hasAttribute("data-overflowing"));

    // Verify the block reads from the DOM, not from the snapshot.
    expect(block.hasAttribute("data-expanded")).to.equal(false);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    expect(toggle.textContent).to.equal("Read more");
  });

  it("collapses on a bfcache restore but not on the first pageshow", async () => {
    const { block, toggle } = renderBlock(`<p>${LONG_TEXT}</p>`);

    media.setMatches(PHONE_MEDIA_QUERY, true);
    await waitForOverflowing(block);
    toggle.click();

    // A first pageshow arrives after load and keeps what the reader opened.
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: false }));
    expect(block.hasAttribute("data-expanded")).to.equal(true);

    // A bfcache restore resets it.
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));
    expect(block.hasAttribute("data-expanded")).to.equal(false);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    await nextFrame();
    expect(block.hasAttribute("data-overflowing")).to.equal(true);
  });
});
