import { closestElement, isOutsideElementEvent, markDatasetReady } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";

const DASHBOARD_TRIGGER_SELECTOR = "#dashboard-content [aria-describedby]";
const DATA_KEY = "tooltipPanelsReady";
const DISMISSED_ATTRIBUTE = "data-tooltip-dismissed";
const TOOLTIP_SELECTOR = "[data-tooltip-panel]";
const TRIGGER_GAP = 4;
const VIEWPORT_PADDING = 16;

let activeTooltip = null;
let activeTrigger = null;
let hoveredWrapper = null;

/**
 * Initializes viewport-aware positioning for shared tooltip panels, plus the
 * click, outside press and Escape behavior of dashboard tooltip triggers.
 * CSS hover and focus visibility stays the source of truth for what is shown.
 * @returns {void}
 */
export const initializeTooltipPanels = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("click", handleTriggerClick);
  document.addEventListener("focusin", positionTooltipFromEvent);
  document.addEventListener("focusout", handleFocusOut);
  document.addEventListener("htmx:beforeHistorySave", resetTooltipPanels);
  document.addEventListener("htmx:historyRestore", resetTooltipPanels);
  document.addEventListener("keydown", handleEscape);
  document.addEventListener("pointerdown", handleOutsidePointerDown);
  document.addEventListener("pointerout", handlePointerOut);
  document.addEventListener("pointerover", handlePointerOver);
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
  // Measuring at full height clamps the panel's scroll offset, so keep it.
  const scrollTop = tooltip.scrollTop;

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
    translate: "none",
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
  tooltip.scrollTop = scrollTop;
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
 * Resolves a dashboard tooltip trigger, its panel and the wrapper that holds both.
 * @param {EventTarget|null} target Event target inside a possible dashboard trigger.
 * @returns {{tooltip: HTMLElement, trigger: HTMLElement, wrapper: Element}|null}
 *   Dashboard tooltip relationship.
 */
const getDashboardTooltip = (target) => {
  const relationship = getTooltipRelationship(target, DASHBOARD_TRIGGER_SELECTOR);
  if (!relationship) {
    return null;
  }

  const wrapper = getTooltipWrapper(relationship.trigger, relationship.tooltip);
  return wrapper ? { ...relationship, wrapper } : null;
};

/**
 * Resolves the shared tooltip referenced by a described-by trigger.
 * @param {EventTarget|null} target Event target inside a possible trigger.
 * @param {string} [triggerSelector="[aria-describedby]"] Selector a trigger must match.
 * @returns {{tooltip: HTMLElement, trigger: HTMLElement}|null} Tooltip relationship.
 */
const getTooltipRelationship = (target, triggerSelector = "[aria-describedby]") => {
  const trigger = closestElement(target, triggerSelector);
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
 * Finds the element whose hover and focus state controls a tooltip's visibility:
 * the trigger when it contains its panel, otherwise the nearest ancestor of the
 * panel that also contains the trigger.
 * @param {HTMLElement} trigger Tooltip trigger.
 * @param {HTMLElement} tooltip Tooltip panel.
 * @returns {Element|null} Tooltip wrapper.
 */
const getTooltipWrapper = (trigger, tooltip) => {
  if (trigger.contains(tooltip)) {
    return trigger;
  }

  let wrapper = tooltip.parentElement;
  while (wrapper && !wrapper.contains(trigger)) {
    wrapper = wrapper.parentElement;
  }

  return wrapper;
};

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
 * Dismisses the focused and the hovered dashboard tooltips on Escape without
 * moving focus or stopping other Escape handlers.
 * @param {KeyboardEvent} event Keyboard event.
 * @returns {void}
 */
const handleEscape = (event) => {
  if (!isEscapeEvent(event)) {
    return;
  }

  getDashboardTooltip(document.activeElement)?.wrapper.setAttribute(DISMISSED_ATTRIBUTE, "");
  hoveredWrapper?.setAttribute(DISMISSED_ATTRIBUTE, "");
};

/**
 * Clears an Escape dismissal once focus leaves a wrapper the pointer isn't over.
 * @param {FocusEvent} event Focus event.
 * @returns {void}
 */
const handleFocusOut = (event) => {
  const wrapper = closestElement(event.target, `[${DISMISSED_ATTRIBUTE}]`);
  if (!wrapper || wrapper === hoveredWrapper || isInsideElement(wrapper, event.relatedTarget)) {
    return;
  }

  wrapper.removeAttribute(DISMISSED_ATTRIBUTE);
};

/**
 * Blurs a focused dashboard trigger when a press lands outside its wrapper, so
 * tapped tooltips close on touch devices. Never moves focus elsewhere.
 * @param {PointerEvent} event Pointer event.
 * @returns {void}
 */
const handleOutsidePointerDown = (event) => {
  const focusedTooltip = getDashboardTooltip(document.activeElement);
  if (!focusedTooltip || !isOutsideElementEvent(event, focusedTooltip.wrapper)) {
    return;
  }

  focusedTooltip.trigger.blur();
  focusedTooltip.wrapper.removeAttribute(DISMISSED_ATTRIBUTE);
};

/**
 * Forgets the hovered wrapper once the pointer leaves it, and clears its Escape
 * dismissal unless it still holds focus.
 * @param {PointerEvent} event Pointer event.
 * @returns {void}
 */
const handlePointerOut = (event) => {
  if (!hoveredWrapper || isInsideElement(hoveredWrapper, event.relatedTarget)) {
    return;
  }

  const wrapper = hoveredWrapper;
  hoveredWrapper = null;
  if (!wrapper.contains(document.activeElement)) {
    wrapper.removeAttribute(DISMISSED_ATTRIBUTE);
  }
};

/**
 * Positions the hovered tooltip and tracks the hovered dashboard wrapper.
 * @param {PointerEvent} event Pointer event.
 * @returns {void}
 */
const handlePointerOver = (event) => {
  positionTooltipFromEvent(event);

  const dashboardTooltip = getDashboardTooltip(event.target);
  if (dashboardTooltip) {
    hoveredWrapper = dashboardTooltip.wrapper;
  }
};

/**
 * Focuses a clicked dashboard trigger, because some browsers don't focus buttons
 * on click, and clears its Escape dismissal. Never closes the tooltip.
 * @param {MouseEvent} event Click event.
 * @returns {void}
 */
const handleTriggerClick = (event) => {
  const dashboardTooltip = getDashboardTooltip(event.target);
  if (!dashboardTooltip) {
    return;
  }

  dashboardTooltip.wrapper.removeAttribute(DISMISSED_ATTRIBUTE);
  if (!dashboardTooltip.trigger.contains(document.activeElement)) {
    dashboardTooltip.trigger.focus({ preventScroll: true });
  }
};

/**
 * Checks whether a related event target sits inside an element.
 * @param {Element} element Containing element.
 * @param {EventTarget|null} target Related event target.
 * @returns {boolean} True when the target is the element or one of its descendants.
 */
const isInsideElement = (element, target) => target instanceof Node && element.contains(target);

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
 * Repositions the active tooltip, and the focused one when it differs, after
 * scrolling or resizing. Scrolling inside a panel never moves a trigger, so it
 * is ignored.
 * @param {Event} [event] Scroll or resize event.
 * @returns {void}
 */
const repositionActiveTooltip = (event) => {
  if (event?.target instanceof Element && event.target.closest(TOOLTIP_SELECTOR)) {
    return;
  }

  const focusedRelationship = getTooltipRelationship(document.activeElement);
  if (focusedRelationship && focusedRelationship.trigger !== activeTrigger) {
    positionTooltipPanel(focusedRelationship.trigger, focusedRelationship.tooltip);
  }

  if (!activeTooltip?.isConnected || !activeTrigger?.isConnected) {
    activeTooltip = null;
    activeTrigger = null;
    return;
  }

  positionTooltipPanel(activeTrigger, activeTooltip);
};

/**
 * Clears Escape dismissals and tracked tooltips before HTMX saves or restores a
 * history snapshot, so a restored page never starts with a hidden tooltip.
 * @returns {void}
 */
const resetTooltipPanels = () => {
  document
    .querySelectorAll(`[${DISMISSED_ATTRIBUTE}]`)
    .forEach((element) => element.removeAttribute(DISMISSED_ATTRIBUTE));
  activeTooltip = null;
  activeTrigger = null;
  hoveredWrapper = null;
};

initializeTooltipPanels();
