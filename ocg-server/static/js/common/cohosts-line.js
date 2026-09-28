import { closestElement, initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";

const DATA_KEY = "cohostsLinesReady";
const FIT_STATE = Object.freeze({
  full: "full",
  summary: "summary",
});
const FULL_SELECTOR = "[data-cohosts-full]";
const HIDE_DELAY_MS = 100;
const LINE_SELECTOR = "[data-cohosts-line]";
const PANEL_GAP = 4;
const PANEL_TEMPLATE_SELECTOR = "template[data-cohosts-panel-template]";
const SUMMARY_SELECTOR = "[data-cohosts-summary]";
const SUMMARY_TRIGGER_SELECTOR = `${LINE_SELECTOR}[data-cohosts-fit="${FIT_STATE.summary}"] ${SUMMARY_SELECTOR}`;
const VIEWPORT_PADDING = 16;

let activePanel = null;
let activeTrigger = null;
let hideTimer = null;

/**
 * Chooses once per rendered line between the full co-hosts credit and the
 * reduced count, so later viewport changes never swap the copy.
 * @param {Document|Element} root Root element to scan.
 * @returns {void}
 */
export const fitCohostsLines = (root = document) => {
  const lines = root instanceof Element && root.matches(LINE_SELECTOR) ? [root] : [];
  lines.push(...(root?.querySelectorAll?.(LINE_SELECTOR) || []));
  lines.forEach(fitCohostsLine);
};

/**
 * Hides the co-hosts panel opened from a reduced credit.
 * @returns {void}
 */
export const hideCohostsPanel = () => {
  cancelHide();
  activePanel?.remove();
  activePanel = null;
  activeTrigger = null;
};

/**
 * Wires delegated panel handlers and fits credits on page load and HTMX swaps.
 * @returns {void}
 */
export const initializeCohostsLines = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("focusin", handleFocusIn);
  document.addEventListener("focusout", handleFocusOut);
  // Remove the body-level panel before HTMX snapshots or replaces the page.
  document.addEventListener("htmx:beforeHistorySave", hideCohostsPanel);
  document.addEventListener("htmx:beforeSwap", hideCohostsPanel);
  document.addEventListener("keydown", handleKeydown);
  document.addEventListener("pointerout", handlePointerOut);
  document.addEventListener("pointerover", handlePointerOver);
  window.addEventListener("scroll", handleScroll, { capture: true, passive: true });
  initializeOnReadyAndHtmxLoad(fitCohostsLinesAfterFontsLoad);
};

/**
 * Cancels a pending panel hide.
 * @returns {void}
 */
const cancelHide = () => {
  clearTimeout(hideTimer);
  hideTimer = null;
};

/**
 * Switches one line to its reduced count when the full names overflow it.
 * @param {HTMLElement} line Co-hosts credit line.
 * @returns {void}
 */
const fitCohostsLine = (line) => {
  if (line.dataset.cohostsFit) {
    return;
  }

  const full = line.querySelector(FULL_SELECTOR);
  const summary = line.querySelector(SUMMARY_SELECTOR);

  // Leave unrendered lines unmarked so a later scan can measure them.
  if (!full || !summary || full.clientWidth === 0) {
    return;
  }

  if (full.scrollWidth <= full.clientWidth) {
    line.dataset.cohostsFit = FIT_STATE.full;
    return;
  }

  // Keep the full names for screen readers while showing the count visually.
  line.dataset.cohostsFit = FIT_STATE.summary;
  line.removeAttribute("title");
  full.classList.replace("truncate", "sr-only");
  summary.classList.remove("hidden");
};

/**
 * Measures credits once web fonts are ready so text widths are final.
 * @param {Document|Element} root Root element to scan.
 * @returns {void}
 */
const fitCohostsLinesAfterFontsLoad = (root) => {
  if (!document.fonts?.ready) {
    fitCohostsLines(root);
    return;
  }

  document.fonts.ready.then(() => fitCohostsLines(root));
};

/**
 * Opens the panel when keyboard focus reaches a card with a reduced credit.
 * @param {FocusEvent} event Focus event.
 * @returns {void}
 */
const handleFocusIn = (event) => {
  const owner = event.target;
  if (!(owner instanceof Element) || !owner.matches(":focus-visible")) {
    return;
  }

  const trigger = owner.querySelector(SUMMARY_TRIGGER_SELECTOR);
  if (trigger instanceof HTMLElement) {
    showCohostsPanel(trigger);
  }
};

/**
 * Closes the panel when focus leaves the card that opened it.
 * @param {FocusEvent} event Focus event.
 * @returns {void}
 */
const handleFocusOut = (event) => {
  if (activeTrigger && event.target instanceof Node && event.target.contains(activeTrigger)) {
    hideCohostsPanel();
  }
};

/**
 * Dismisses the panel with Escape.
 * @param {KeyboardEvent} event Keyboard event.
 * @returns {void}
 */
const handleKeydown = (event) => {
  if (event.key === "Escape" && activePanel) {
    hideCohostsPanel();
  }
};

/**
 * Schedules a hide when the pointer leaves both the credit and its panel.
 * @param {PointerEvent} event Pointer event.
 * @returns {void}
 */
const handlePointerOut = (event) => {
  if (!activeTrigger || !isInsideActiveElements(event.target)) {
    return;
  }

  if (!isInsideActiveElements(event.relatedTarget)) {
    scheduleHide();
  }
};

/**
 * Opens the panel for a hovered reduced credit and keeps it open over the panel.
 * @param {PointerEvent} event Pointer event.
 * @returns {void}
 */
const handlePointerOver = (event) => {
  const trigger = closestElement(event.target, SUMMARY_TRIGGER_SELECTOR);
  if (trigger instanceof HTMLElement) {
    showCohostsPanel(trigger);
    return;
  }

  if (activePanel?.contains(event.target)) {
    cancelHide();
  }
};

/**
 * Hides the panel when the page or a container scrolls under it.
 * @param {Event} event Scroll event.
 * @returns {void}
 */
const handleScroll = (event) => {
  if (activePanel && !(event.target instanceof Node && activePanel.contains(event.target))) {
    hideCohostsPanel();
  }
};

/**
 * Checks whether a target belongs to the active count or its panel.
 * @param {EventTarget|null} target Event target.
 * @returns {boolean} True when the target is inside either element.
 */
const isInsideActiveElements = (target) =>
  target instanceof Node && Boolean(activeTrigger?.contains(target) || activePanel?.contains(target));

/**
 * Drops the panel below the count, flipping above only when there is more room.
 * @param {HTMLElement} trigger Visible co-hosts count.
 * @param {HTMLElement} panel Co-hosts panel.
 * @returns {void}
 */
const positionCohostsPanel = (trigger, panel) => {
  const triggerRect = trigger.getBoundingClientRect();
  const panelRect = panel.getBoundingClientRect();
  const viewportHeight = window.innerHeight;
  const viewportWidth = document.documentElement.clientWidth;
  const availableAbove = triggerRect.top - PANEL_GAP - VIEWPORT_PADDING;
  const availableBelow = viewportHeight - triggerRect.bottom - PANEL_GAP - VIEWPORT_PADDING;
  const placeBelow = panelRect.height <= availableBelow || availableBelow >= availableAbove;
  const availableHeight = Math.max(0, placeBelow ? availableBelow : availableAbove);
  const displayedHeight = Math.min(panelRect.height, availableHeight);
  const maximumLeft = viewportWidth - VIEWPORT_PADDING - panelRect.width;

  panel.style.left = `${Math.max(VIEWPORT_PADDING, Math.min(triggerRect.left, maximumLeft))}px`;
  panel.style.maxHeight = `${availableHeight}px`;
  panel.style.top = placeBelow
    ? `${triggerRect.bottom + PANEL_GAP}px`
    : `${triggerRect.top - PANEL_GAP - displayedHeight}px`;
};

/**
 * Delays hiding so the pointer can travel from the credit into the panel.
 * @returns {void}
 */
const scheduleHide = () => {
  cancelHide();
  hideTimer = setTimeout(hideCohostsPanel, HIDE_DELAY_MS);
};

/**
 * Renders the co-hosts panel in the body so card clipping cannot hide it.
 * @param {HTMLElement} trigger Visible co-hosts count.
 * @returns {void}
 */
const showCohostsPanel = (trigger) => {
  cancelHide();
  if (activeTrigger === trigger && activePanel?.isConnected) {
    return;
  }

  const template = trigger.closest(LINE_SELECTOR)?.querySelector(PANEL_TEMPLATE_SELECTOR);
  const panel = template?.content.firstElementChild?.cloneNode(true);
  if (!(panel instanceof HTMLElement)) {
    return;
  }

  hideCohostsPanel();
  document.body.append(panel);
  positionCohostsPanel(trigger, panel);
  activePanel = panel;
  activeTrigger = trigger;
};

initializeCohostsLines();
