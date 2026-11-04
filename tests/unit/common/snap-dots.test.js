import { expect } from "@open-wc/testing";

import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

const ITEM_WIDTH = 150;
const ITEM_GAP = 10;
const STEP = ITEM_WIDTH + ITEM_GAP;

const originalAddEventListener = document.addEventListener;
const originalMatchMedia = window.matchMedia;
const originalRemoveEventListener = document.removeEventListener;

/** Query the module keeps for its whole life, since it reads matchMedia only on load. */
const phoneQuery = {
  listeners: new Set(),
  matches: false,
  addEventListener(type, listener) {
    if (type === "change") {
      this.listeners.add(listener);
    }
  },
  removeEventListener(type, listener) {
    if (type === "change") {
      this.listeners.delete(listener);
    }
  },
};

/**
 * Changes the phone query and notifies the module.
 * @param {boolean} matches Next query state.
 * @returns {void}
 */
const setPhone = (matches) => {
  phoneQuery.matches = matches;
  phoneQuery.listeners.forEach((listener) => listener({ matches }));
};

/**
 * Renders a scroller and its position row.
 * @param {object} options Fixture options.
 * @param {number} options.items Rendered item count.
 * @param {string} options.rowAttributes Extra row attributes.
 * @param {string} options.rowContent Row children.
 * @returns {{dots: () => Element[], row: Element, scroller: Element}} Fixture nodes.
 */
const renderCarousel = ({ items = 3, rowAttributes = "", rowContent = "" } = {}) => {
  const tiles = Array.from(
    { length: items },
    () =>
      `<div style="flex: 0 0 ${ITEM_WIDTH}px; height: 20px"></div><div style="display: none"></div>`,
  ).join("");
  document.body.innerHTML = `
    <div>
      <div data-test-scroller style="display: flex; gap: ${ITEM_GAP}px; overflow-x: auto; width: 200px">
        ${tiles}
      </div>
      <div aria-hidden="true" data-snap-dots ${rowAttributes}>${rowContent}</div>
    </div>
  `;
  const row = document.querySelector("[data-snap-dots]");

  return {
    dots: () => [...row.querySelectorAll(".snap-dot")],
    row,
    scroller: document.querySelector("[data-test-scroller]"),
  };
};

/**
 * Scrolls a scroller and waits for its scroll event.
 * @param {Element} scroller Scroller element.
 * @param {number} left Target scrollLeft.
 * @returns {Promise<void>} Resolved once the event has run.
 */
const scrollTo = async (scroller, left) => {
  const scrolled = new Promise((resolve) => {
    scroller.addEventListener("scroll", resolve, { once: true });
  });
  scroller.scrollLeft = left;
  await scrolled;
};

/**
 * Reads which dots are active.
 * @param {Element[]} dots Dots to read.
 * @returns {boolean[]} Active state per dot.
 */
const activeStates = (dots) => dots.map((dot) => dot.hasAttribute("data-active"));

describe("snap-dots", () => {
  const documentListeners = [];
  const removedDocumentListeners = [];
  let syncSnapDots;

  before(async () => {
    // Record the module's load-time wiring with the phone query false.
    window.matchMedia = (text) => (text === PHONE_MEDIA_QUERY ? phoneQuery : { matches: false });
    document.addEventListener = function addEventListener(type, ...rest) {
      documentListeners.push(type);
      return originalAddEventListener.call(this, type, ...rest);
    };
    document.removeEventListener = function removeEventListener(type, ...rest) {
      removedDocumentListeners.push(type);
      return originalRemoveEventListener.call(this, type, ...rest);
    };

    ({ syncSnapDots } = await import("/static/js/common/snap-dots.js"));
    await import("/static/js/common/modals/images-gallery.js");
  });

  after(() => {
    document.addEventListener = originalAddEventListener;
    document.removeEventListener = originalRemoveEventListener;
    window.matchMedia = originalMatchMedia;
  });

  afterEach(() => {
    setPhone(false);
    removeMountedElements("images-gallery");
    resetDom();
  });

  it("keeps one query listener and only the HTMX listeners off phones", () => {
    // The load-time wiring matches the section 8.3 allowance.
    expect(phoneQuery.listeners.size).to.equal(1);
    expect(documentListeners.filter((type) => type === "htmx:load")).to.have.length(1);
    expect(documentListeners.filter((type) => type === "htmx:historyRestore")).to.have.length(1);
    expect(documentListeners).to.not.include("scroll");
  });

  it("writes nothing to a row off phones", () => {
    // Render a carousel while the query is false.
    const { row } = renderCarousel({ rowContent: "<span data-snap-counter></span>" });

    // Direct syncs and HTMX events leave the row untouched.
    syncSnapDots();
    document.dispatchEvent(new CustomEvent("htmx:load"));
    document.dispatchEvent(new CustomEvent("htmx:historyRestore"));
    expect(row.querySelectorAll(".snap-dot")).to.have.length(0);
    expect(row.querySelector("[data-snap-counter]").textContent).to.equal("");
  });

  it("adds one dot per rendered item when the query turns true", () => {
    // Render the carousel, with a display:none twin after each item.
    const { dots } = renderCarousel({ rowContent: "<span data-snap-counter></span>" });

    // The phone branch fills the row and marks the first item.
    setPhone(true);
    expect(activeStates(dots())).to.deep.equal([true, false, false]);
    expect(document.querySelector("[data-snap-counter]").textContent).to.equal("1 / 3");
    expect(document.querySelector("[data-snap-dots]").lastElementChild.dataset.snapCounter).to.equal(
      "",
    );
  });

  it("follows scrollLeft", async () => {
    // Render the carousel on a phone.
    const { dots, scroller } = renderCarousel({ rowContent: "<span data-snap-counter></span>" });
    setPhone(true);

    // The active dot and the counter follow the scroll position.
    await scrollTo(scroller, STEP);
    expect(activeStates(dots())).to.deep.equal([false, true, false]);
    expect(document.querySelector("[data-snap-counter]").textContent).to.equal("2 / 3");

    // The rounded index moves past the halfway point, and the last item stays reachable.
    await scrollTo(scroller, STEP * 0.4);
    expect(activeStates(dots())).to.deep.equal([true, false, false]);
    await scrollTo(scroller, scroller.scrollWidth);
    expect(activeStates(dots())).to.deep.equal([false, false, true]);
  });

  it("ignores scrolls of the document and of other elements", () => {
    // Render the carousel on a phone.
    const { dots } = renderCarousel();
    setPhone(true);

    // Document has no closest(), and an unrelated element has no row.
    document.dispatchEvent(new Event("scroll"));
    document.body.dispatchEvent(new Event("scroll"));
    expect(activeStates(dots())).to.deep.equal([true, false, false]);
  });

  it("keeps the counter and drops the dots above the row's limit", () => {
    // Render more items than the row allows.
    const { dots } = renderCarousel({
      items: 4,
      rowAttributes: 'data-snap-dots-max="3"',
      rowContent: "<span data-snap-counter></span>",
    });
    setPhone(true);

    // Only the counter remains.
    expect(dots()).to.have.length(0);
    expect(document.querySelector("[data-snap-counter]").textContent).to.equal("1 / 4");
  });

  it("shows no dots for a single item", () => {
    // Render one item.
    const { dots } = renderCarousel({ items: 1 });
    setPhone(true);

    expect(dots()).to.have.length(0);
  });

  it("resyncs rows after an HTMX swap and a history restore", async () => {
    // Swapped-in markup is synced from htmx:load.
    setPhone(true);
    const { dots, row, scroller } = renderCarousel();
    expect(dots()).to.have.length(0);
    scroller.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
    expect(dots()).to.have.length(0);
    row.parentElement.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
    expect(dots()).to.have.length(3);

    // A restored snapshot keeps its old dot while scrollLeft is back at 0.
    await scrollTo(scroller, STEP);
    const restoredMarkup = document.body.innerHTML;
    document.body.innerHTML = restoredMarkup;
    const restoredDots = () => [...document.querySelectorAll(".snap-dot")];
    expect(activeStates(restoredDots())).to.deep.equal([false, true, false]);

    // htmx:historyRestore corrects it, keeping the same nodes.
    const [firstDot] = restoredDots();
    document.body.dispatchEvent(new CustomEvent("htmx:historyRestore", { bubbles: true }));
    expect(activeStates(restoredDots())).to.deep.equal([true, false, false]);
    expect(restoredDots()[0]).to.equal(firstDot);
  });

  it("stops following the scroller when the query turns false", async () => {
    // Render the carousel on a phone.
    const { dots, scroller } = renderCarousel();
    setPhone(true);
    const scrollListeners = documentListeners.filter((type) => type === "scroll").length;
    const removedScrollListeners = removedDocumentListeners.filter((type) => type === "scroll").length;

    // Rotating past 768px removes the scroll listener.
    setPhone(false);
    expect(removedDocumentListeners.filter((type) => type === "scroll")).to.have.length(
      removedScrollListeners + 1,
    );
    await scrollTo(scroller, STEP);
    expect(activeStates(dots())).to.deep.equal([true, false, false]);

    // Rotating back listens again and catches up.
    setPhone(true);
    expect(documentListeners.filter((type) => type === "scroll")).to.have.length(scrollListeners + 1);
    expect(activeStates(dots())).to.deep.equal([false, true, false]);
  });

  it("fills the gallery row after its first render", async () => {
    // Phones never render the md:hidden tiles.
    const style = document.createElement("style");
    style.textContent = ".md\\:hidden { display: none; }";
    document.head.append(style);
    setPhone(true);

    // Render a gallery within the dots limit.
    const gallery = await mountLitComponent("images-gallery", {
      images: ["https://example.com/1.png", "https://example.com/2.png"],
    });
    expect(gallery.querySelectorAll("[data-snap-dots] .snap-dot")).to.have.length(2);
    expect(gallery.querySelector("[data-snap-counter]").textContent).to.equal("1 / 2");

    // Past the limit the gallery keeps only its counter.
    const longGallery = await mountLitComponent("images-gallery", {
      images: Array.from({ length: 11 }, (_, index) => `https://example.com/${index}.png`),
    });
    expect(longGallery.querySelectorAll("[data-snap-dots] .snap-dot")).to.have.length(0);
    expect(longGallery.querySelector("[data-snap-counter]").textContent).to.equal("1 / 11");

    // Lit re-renders keep the dots the module added.
    gallery._openModal(1);
    await gallery.updateComplete;
    expect(gallery.querySelectorAll("[data-snap-dots] .snap-dot")).to.have.length(2);
    gallery._closeModal();
    style.remove();
  });
});
