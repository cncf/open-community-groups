import {
  closestElement,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
} from "/static/js/common/dom.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";

const COUNTER_SELECTOR = "[data-snap-counter]";
const DOT_CLASS = "snap-dot";
const ROW_SELECTOR = "[data-snap-dots]";
const SCROLLER_SELECTOR = `:has(+ ${ROW_SELECTOR})`;
const SCROLL_LISTENER_OPTIONS = { capture: true, passive: true };

const phoneQuery = window.matchMedia(PHONE_MEDIA_QUERY);

/**
 * Syncs the position rows of snap carousels with their scrollers.
 *
 * A row is a `not-phone:hidden`, `aria-hidden` element carrying `data-snap-dots`, placed
 * directly after its scroller, because desktop nodes may not gain attributes. It starts
 * empty: this module adds one dot per rendered item, up to `data-snap-dots-max`, and fills
 * an optional `data-snap-counter` child. Does nothing off phones.
 * @param {Document|Element} root Root to scan for rows.
 * @returns {void}
 */
export const syncSnapDots = (root = document) => {
  if (!phoneQuery.matches) {
    return;
  }

  initializeMatchingRoots(root, ROW_SELECTOR, syncRow);
};

/**
 * Reads the active item of a scroller.
 * @param {Element} scroller Scroller element.
 * @param {Element[]} items Rendered scroller items.
 * @returns {number} Index of the active item.
 */
const getActiveIndex = (scroller, items) => {
  const step = items.length > 1 ? items[1].offsetLeft - items[0].offsetLeft : 0;
  if (step <= 0) {
    return 0;
  }

  return Math.min(Math.round(scroller.scrollLeft / step), items.length - 1);
};

/**
 * Matches the row's dots to the item count.
 * @param {Element} row Position row.
 * @param {number} count Number of dots to show.
 * @returns {Element[]} Dots in the row.
 */
const getRowDots = (row, count) => {
  const dots = [...row.querySelectorAll(`.${DOT_CLASS}`)];
  if (dots.length === count) {
    return dots;
  }

  dots.forEach((dot) => dot.remove());
  const nextDots = Array.from({ length: count }, () => {
    const dot = document.createElement("span");
    dot.className = DOT_CLASS;
    return dot;
  });
  row.prepend(...nextDots);
  return nextDots;
};

/**
 * Keeps the scroll listener on phones only.
 * @returns {void}
 */
const handlePhoneChange = () => {
  if (phoneQuery.matches) {
    document.addEventListener("scroll", handleScroll, SCROLL_LISTENER_OPTIONS);
    syncSnapDots();
  } else {
    document.removeEventListener("scroll", handleScroll, SCROLL_LISTENER_OPTIONS);
  }
};

/**
 * Follows a carousel scroll. Scroll events reach document from any scroller, and from
 * document itself, which has no closest().
 * @param {Event} event Captured scroll event.
 * @returns {void}
 */
const handleScroll = (event) => {
  const scroller = closestElement(event.target, SCROLLER_SELECTOR);
  if (scroller) {
    syncRow(scroller.nextElementSibling);
  }
};

/**
 * Syncs one position row with the scroller before it.
 * @param {Element} row Position row.
 * @returns {void}
 */
const syncRow = (row) => {
  const scroller = row.previousElementSibling;
  if (!scroller) {
    return;
  }

  // Scrollers may hold items phones do not render, such as the gallery's md:hidden tiles.
  const items = [...scroller.children].filter((item) => item.getClientRects().length > 0);
  const maxDots = Number(row.dataset.snapDotsMax ?? Infinity);
  const dotCount = items.length > 1 && items.length <= maxDots ? items.length : 0;
  const activeIndex = getActiveIndex(scroller, items);

  getRowDots(row, dotCount).forEach((dot, index) => {
    dot.toggleAttribute("data-active", index === activeIndex);
  });

  const counter = row.querySelector(COUNTER_SELECTOR);
  const counterText = `${activeIndex + 1} / ${items.length}`;
  if (counter && counter.textContent !== counterText) {
    counter.textContent = counterText;
  }
};

phoneQuery.addEventListener("change", handlePhoneChange);
handlePhoneChange();
// Back restores the markup but not scrollLeft, so restored rows resync.
initializeOnReadyAndHtmxLoad(syncSnapDots);
