import { initializeMatchingRoots, initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";
import { isPhoneViewport, PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";

const COLLAPSED_LABEL = "Read more";
const EXPANDED_LABEL = "Read less";
// Taps on these keep their own action instead of expanding the text.
const INTERACTIVE_SELECTOR = "a, button, input, label, select, summary, textarea";
const LABEL_SELECTOR = "[data-read-more-label]";
const READ_MORE_SELECTOR = ".read-more";

/** Cleanup function of each bound block. */
const boundBlocks = new Map();

/** Aborts the page listeners, and is set only while the phone layout is active. */
let pageListeners = null;

/**
 * Binds the read more blocks under a root. Does nothing off phones, where the
 * text is never clipped.
 * @param {Document|Element} [root=document] Root element to scan from.
 * @returns {void}
 */
export const initializeReadMore = (root = document) => {
  if (!isPhoneViewport()) {
    return;
  }

  pageListeners ??= bindPageListeners();
  boundBlocks.forEach((_, block) => {
    if (!block.isConnected) {
      releaseBlock(block);
    }
  });
  initializeMatchingRoots(root, READ_MORE_SELECTOR, bindBlock);
};

/**
 * Binds one block. The observer's first callback sets `data-overflowing`. A tap
 * on the clipped text expands it, so the fade works as part of the toggle.
 * @param {Element} block Read more block.
 * @returns {void}
 */
const bindBlock = (block) => {
  if (boundBlocks.has(block)) {
    return;
  }

  const body = block.querySelector(".read-more-body");
  const listeners = new AbortController();
  const { signal } = listeners;
  // The body keeps its capped height while clipped, so late images only resize its children.
  const observer = new ResizeObserver(() => measureBlock(block, body));

  setExpanded(block, false);
  block
    .querySelector(".read-more-toggle")
    .addEventListener("click", () => setExpanded(block, !block.hasAttribute("data-expanded")), { signal });
  body.addEventListener(
    "click",
    (event) => {
      if (
        block.hasAttribute("data-overflowing") &&
        !block.hasAttribute("data-expanded") &&
        !event.target.closest(INTERACTIVE_SELECTOR)
      ) {
        setExpanded(block, true);
      }
    },
    { signal },
  );
  body.addEventListener(
    "focusin",
    () => {
      if (block.hasAttribute("data-overflowing")) {
        setExpanded(block, true);
      }
    },
    { signal },
  );
  [body, ...body.children].forEach((element) => observer.observe(element));

  boundBlocks.set(block, () => {
    listeners.abort();
    observer.disconnect();
  });
};

/**
 * Binds the listeners that collapse open blocks before history can keep them.
 * @returns {AbortController} Controller that removes the listeners.
 */
const bindPageListeners = () => {
  const listeners = new AbortController();
  const { signal } = listeners;

  document.addEventListener("htmx:beforeHistorySave", collapseAllBlocks, { signal });
  window.addEventListener(
    "pageshow",
    (event) => {
      // The first pageshow comes after load and must not close a block already opened.
      if (event.persisted) {
        collapseAllBlocks();
      }
    },
    { signal },
  );

  return listeners;
};

/**
 * Collapses every block in the document, bound or not.
 * @returns {void}
 */
const collapseAllBlocks = () => {
  document.querySelectorAll(READ_MORE_SELECTOR).forEach((block) => setExpanded(block, false));
};

/**
 * Follows the phone query: binds when it turns true, releases when it turns false.
 * @param {MediaQueryListEvent} event Query change event.
 * @returns {void}
 */
const handlePhoneQueryChange = (event) => {
  if (event.matches) {
    initializeReadMore();
  } else {
    releaseAllBlocks();
  }
};

/**
 * Checks whether an image sits at the height clipped blocks cap it to.
 * @param {HTMLImageElement} image Image inside a block.
 * @returns {boolean} True when the image is cut down.
 */
const isCappedImage = (image) =>
  image.getBoundingClientRect().height >= parseFloat(getComputedStyle(image).maxHeight);

/**
 * Shows the toggle only when the collapsed body hides something. An expanded
 * body has no cap to measure against, so it keeps its last result.
 * @param {Element} block Read more block.
 * @param {Element} body Clipped body.
 * @returns {void}
 */
const measureBlock = (block, body) => {
  if (block.hasAttribute("data-expanded")) {
    return;
  }

  const overflowing =
    body.scrollHeight > body.clientHeight || [...body.querySelectorAll("img")].some(isCappedImage);
  block.toggleAttribute("data-overflowing", overflowing);
};

/**
 * Releases every bound block and the page listeners, leaving no state behind.
 * Keys on held state, because the query is already false here.
 * @returns {void}
 */
const releaseAllBlocks = () => {
  pageListeners?.abort();
  pageListeners = null;
  boundBlocks.forEach((_, block) => {
    releaseBlock(block);
    setExpanded(block, false);
    block.removeAttribute("data-overflowing");
  });
};

/**
 * Removes a block's listeners and observer.
 * @param {Element} block Read more block.
 * @returns {void}
 */
const releaseBlock = (block) => {
  boundBlocks.get(block)?.();
  boundBlocks.delete(block);
};

/**
 * Expands or collapses a block, keeping its toggle in step.
 * @param {Element} block Read more block.
 * @param {boolean} expanded Next state.
 * @returns {void}
 */
const setExpanded = (block, expanded) => {
  const toggle = block.querySelector(".read-more-toggle");

  block.toggleAttribute("data-expanded", expanded);
  toggle.setAttribute("aria-expanded", String(expanded));
  toggle.querySelector(LABEL_SELECTOR).textContent = expanded ? EXPANDED_LABEL : COLLAPSED_LABEL;
};

window.matchMedia(PHONE_MEDIA_QUERY).addEventListener("change", handlePhoneQueryChange);
initializeOnReadyAndHtmxLoad(initializeReadMore);
