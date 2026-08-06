import { closestElement, markDatasetReady } from "/static/js/common/dom.js";

const DATA_KEY = "tooltipPanelsReady";
const TOOLTIP_SELECTOR = "[data-tooltip-panel]";
const TRIGGER_GAP = 4;
const VIEWPORT_PADDING = 16;

let activeTooltip = null;
let activeTrigger = null;

/**
 * Initializes viewport-aware positioning for shared tooltip panels.
 * @returns {void}
 */
export const initializeTooltipPanels = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("focusin", positionTooltipFromEvent);
  document.addEventListener("pointerover", positionTooltipFromEvent);
  window.addEventListener("resize", repositionActiveTooltip, { passive: true });
  window.addEventListener("scroll", repositionActiveTooltip, {
    capture: true,
    passive: true,
  });
  window.visualViewport?.addEventListener("resize", repositionActiveTooltip, {
    passive: true,
  });
  window.visualViewport?.addEventListener("scroll", repositionActiveTooltip, {
    passive: true,
  });
};

/**
 * Positions a tooltip beside its trigger without crossing a viewport edge.
 * @param {HTMLElement} trigger Element that describes the tooltip relationship.
 * @param {HTMLElement} tooltip Tooltip panel to position.
 * @returns {void}
 */
export const positionTooltipPanel = (trigger, tooltip) => {
  const viewport = getViewportBounds();
  const triggerRect = trigger.getBoundingClientRect();

  Object.assign(tooltip.style, {
    bottom: "auto",
    left: "0px",
    margin: "0",
    maxHeight: `${Math.max(0, viewport.height - VIEWPORT_PADDING * 2)}px`,
    overflowY: "auto",
    position: "fixed",
    right: "auto",
    top: "0px",
    transform: "none",
  });

  const tooltipRect = tooltip.getBoundingClientRect();
  const availableAbove = triggerRect.top - viewport.top - TRIGGER_GAP - VIEWPORT_PADDING;
  const availableBelow = viewport.bottom - triggerRect.bottom - TRIGGER_GAP - VIEWPORT_PADDING;
  const placeBelow = tooltipRect.height > availableAbove && availableBelow > availableAbove;
  const availableHeight = Math.max(0, placeBelow ? availableBelow : availableAbove);
  const displayedHeight = Math.min(tooltipRect.height, availableHeight);
  const centeredLeft = triggerRect.left + triggerRect.width / 2 - tooltipRect.width / 2;
  const maximumLeft = viewport.right - VIEWPORT_PADDING - tooltipRect.width;

  tooltip.style.left = `${clamp(centeredLeft, viewport.left + VIEWPORT_PADDING, maximumLeft)}px`;
  tooltip.style.maxHeight = `${availableHeight}px`;
  tooltip.style.top = placeBelow
    ? `${triggerRect.bottom + TRIGGER_GAP}px`
    : `${triggerRect.top - TRIGGER_GAP - displayedHeight}px`;
};

/**
 * Keeps a value inside an inclusive range, including ranges narrower than the value.
 * @param {number} value Preferred value.
 * @param {number} minimum Minimum allowed value.
 * @param {number} maximum Maximum allowed value.
 * @returns {number} Clamped value.
 */
const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(value, maximum));

/**
 * Reads the visible viewport, including mobile visual viewport offsets.
 * @returns {{bottom: number, height: number, left: number, right: number, top: number}}
 */
const getViewportBounds = () => {
  const visualViewport = window.visualViewport;
  const height = visualViewport?.height || window.innerHeight;
  const left = visualViewport?.offsetLeft || 0;
  const top = visualViewport?.offsetTop || 0;
  const width = visualViewport?.width || window.innerWidth;

  return {
    bottom: top + height,
    height,
    left,
    right: left + width,
    top,
  };
};

/**
 * Resolves the shared tooltip referenced by a described-by trigger.
 * @param {EventTarget|null} target Event target inside a possible trigger.
 * @returns {{tooltip: HTMLElement, trigger: HTMLElement}|null} Tooltip relationship.
 */
const getTooltipRelationship = (target) => {
  const trigger = closestElement(target, "[aria-describedby]");
  if (!(trigger instanceof HTMLElement)) {
    return null;
  }

  const tooltip = trigger
    .getAttribute("aria-describedby")
    ?.split(/\s+/)
    .map((id) => document.getElementById(id))
    .find((element) => element?.matches(TOOLTIP_SELECTOR));

  return tooltip instanceof HTMLElement ? { tooltip, trigger } : null;
};

/**
 * Positions the tooltip associated with a delegated interaction event.
 * @param {Event} event Hover or focus event.
 * @returns {void}
 */
const positionTooltipFromEvent = (event) => {
  const relationship = getTooltipRelationship(event.target);
  if (!relationship) {
    return;
  }

  activeTooltip = relationship.tooltip;
  activeTrigger = relationship.trigger;
  positionTooltipPanel(activeTrigger, activeTooltip);
};

/**
 * Repositions the active tooltip after scrolling or resizing.
 * @returns {void}
 */
const repositionActiveTooltip = () => {
  if (!activeTooltip?.isConnected || !activeTrigger?.isConnected) {
    activeTooltip = null;
    activeTrigger = null;
    return;
  }

  positionTooltipPanel(activeTrigger, activeTooltip);
};

initializeTooltipPanels();
