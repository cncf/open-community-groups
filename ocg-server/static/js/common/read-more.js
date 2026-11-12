import { initializeMatchingRoots, initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";
import { isPhoneViewport, PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";

// Custom property that ends a collapsed body under its last shown line.
const CLIP_HEIGHT_PROPERTY = "--read-more-clip";
const COLLAPSED_LABEL = "Read more";
// Lines of text a collapsed body shows; styles.src.css falls back to the same count.
const COLLAPSED_LINES = 10;
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
 * on the clipped text expands it, like the toggle.
 * @param {Element} block Read more block.
 * @returns {void}
 */
const bindBlock = (block) => {
  if (boundBlocks.has(block)) {
    return;
  }

  const body = block.querySelector(".read-more-body");
  const toggle = block.querySelector(".read-more-toggle");
  const listeners = new AbortController();
  const { signal } = listeners;
  // Only the children are observed. Late images resize them, while each measure resizes the
  // body, which the observer would report as a loop.
  const observer = new ResizeObserver(() => measureBlock(block, body));
  const mutations = new MutationObserver((records) => {
    records.forEach(({ addedNodes, removedNodes }) => {
      getElements(removedNodes).forEach((element) => observer.unobserve(element));
      getElements(addedNodes).forEach((element) => observer.observe(element));
    });
    measureBlock(block, body);
  });

  setExpanded(block, false);
  toggle.addEventListener(
    "click",
    () => {
      setExpanded(block, !block.hasAttribute("data-expanded"));
      // Lines can move while the text is open, so a collapse measures again.
      measureBlock(block, body);
    },
    { signal },
  );
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
  [...body.children].forEach((element) => observer.observe(element));
  mutations.observe(body, { childList: true });

  boundBlocks.set(block, () => {
    listeners.abort();
    mutations.disconnect();
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
 * Finds the height that ends a collapsed body under its last shown line.
 * @param {Element} body Read more body.
 * @returns {number|null} Height in pixels, or null when every line of text is shown.
 */
const getClipHeight = (body) => {
  const lines = getTextLines(body, COLLAPSED_LINES + 1);
  if (lines.length <= COLLAPSED_LINES) {
    return null;
  }

  const lastLine = lines[COLLAPSED_LINES - 1];
  const nextLine = lines[COLLAPSED_LINES];
  // A line box reaches half a line height below the center of its text. Without a numeric line
  // height the text's own bottom edge is the cut. Whole pixels absorb uneven half-leading.
  const lineHeight = Number.parseFloat(getComputedStyle(body).lineHeight) || 0;
  const lineBoxBottom = (lastLine.top + lastLine.bottom + lineHeight) / 2;
  const clipBottom = Math.max(lastLine.bottom, Math.min(lineBoxBottom, nextLine.top));

  return Math.round(clipBottom - body.getBoundingClientRect().top);
};

/**
 * Keeps the elements of a node list.
 * @param {NodeList} nodes Nodes to filter.
 * @returns {Element[]} Element nodes.
 */
const getElements = (nodes) => [...nodes].filter((node) => node instanceof Element);

/**
 * Collects the lines of text in a body from the top, reading where the text is
 * laid out rather than where it is clipped.
 * @param {Element} body Read more body.
 * @param {number} limit Lines to complete before stopping.
 * @returns {{bottom: number, top: number}[]} Vertical extent of each line.
 */
const getTextLines = (body, limit) => {
  const lines = [];
  const range = document.createRange();
  const walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);

  // A line is complete once the next one starts, so collect one past the limit.
  while (lines.length <= limit && walker.nextNode()) {
    range.selectNodeContents(walker.currentNode);
    for (const { bottom, height, top } of range.getClientRects()) {
      const line = lines.at(-1);

      if (height === 0) {
        continue;
      }
      // A fragment centered inside the last line continues it.
      if (line && (top + bottom) / 2 < line.bottom) {
        line.bottom = Math.max(line.bottom, bottom);
        line.top = Math.min(line.top, top);
      } else {
        lines.push({ bottom, top });
      }
    }
  }

  return lines;
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
 * Ends the collapsed body under its last shown line, and shows the toggle only
 * when that hides something. An expanded body has no cap to measure against, so
 * it keeps its last result.
 * @param {Element} block Read more block.
 * @param {Element} body Clipped body.
 * @returns {void}
 */
const measureBlock = (block, body) => {
  if (block.hasAttribute("data-expanded")) {
    return;
  }

  const clipHeight = getClipHeight(body);
  const overflowing = clipHeight !== null || [...body.querySelectorAll("img")].some(isCappedImage);

  body.style.setProperty(CLIP_HEIGHT_PROPERTY, clipHeight === null ? "none" : `${clipHeight}px`);
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
    block.querySelector(".read-more-body").style.removeProperty(CLIP_HEIGHT_PROPERTY);
  });
};

/**
 * Removes a block's listeners and observers.
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
