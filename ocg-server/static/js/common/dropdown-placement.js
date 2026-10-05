// Overflow values that make an ancestor clip its descendants.
const CLIPPING_OVERFLOW_VALUES = new Set(["auto", "clip", "hidden", "scroll"]);

// Space kept between a dropdown and the visible edge.
const VIEWPORT_GAP = 8;

/**
 * Reactive controller that keeps an anchored dropdown inside the visible area.
 *
 * After every host render the controller fits the dropdown when it is rendered,
 * capping its height to the space left before the visible edge and opening it
 * above its anchor when that side has more room. While the dropdown is visible
 * it also refits on window resize and ancestor scroll.
 */
export class DropdownPlacementController {
  /**
   * @param {import("lit").ReactiveControllerHost & HTMLElement} host Host component.
   * @param {object} options Controller options.
   * @param {() => Element|null} options.getAnchor Returns the element the dropdown opens from.
   * @param {() => Element|null} options.getDropdown Returns the positioned dropdown element.
   */
  constructor(host, options) {
    this.host = host;
    this._options = options;
    this._isListening = false;
    this._pendingFrameId = 0;
    this._handleViewportChange = this._handleViewportChange.bind(this);
    host.addController(this);
  }

  hostUpdated() {
    this.update();
  }

  hostDisconnected() {
    this._removeListeners();
  }

  /**
   * Fits the dropdown when it is rendered and tracks viewport changes meanwhile.
   * @returns {void}
   */
  update() {
    this._cancelPendingFit();
    const anchor = this._options.getAnchor();
    const dropdown = this._options.getDropdown();
    if (!isRenderedElement(anchor) || !isRenderedElement(dropdown)) {
      this._removeListeners();
      return;
    }

    placeDropdown(anchor, dropdown);
    this._addListeners();
  }

  /**
   * Starts refitting the dropdown on resize and scroll.
   * @returns {void}
   */
  _addListeners() {
    if (this._isListening) {
      return;
    }
    this._isListening = true;
    window.addEventListener("resize", this._handleViewportChange, { passive: true });
    document.addEventListener("scroll", this._handleViewportChange, { capture: true, passive: true });
  }

  /**
   * Refits the dropdown unless the scroll happened inside the dropdown itself.
   *
   * Placement reads layout, so refits are coalesced into the next animation
   * frame to keep scrolling cheap when several dropdowns are mounted.
   * @param {Event} event Resize or scroll event.
   * @returns {void}
   */
  _handleViewportChange(event) {
    const dropdown = this._options.getDropdown();
    if (event.type === "scroll" && event.target instanceof Node && dropdown?.contains(event.target)) {
      return;
    }
    if (this._pendingFrameId !== 0) {
      return;
    }
    this._pendingFrameId = window.requestAnimationFrame(() => {
      this._pendingFrameId = 0;
      this.update();
    });
  }

  /**
   * Stops refitting the dropdown on resize and scroll.
   * @returns {void}
   */
  _removeListeners() {
    this._cancelPendingFit();
    if (!this._isListening) {
      return;
    }
    this._isListening = false;
    window.removeEventListener("resize", this._handleViewportChange, { passive: true });
    document.removeEventListener("scroll", this._handleViewportChange, { capture: true, passive: true });
  }

  /**
   * Drops a refit that has not run yet.
   * @returns {void}
   */
  _cancelPendingFit() {
    if (this._pendingFrameId === 0) {
      return;
    }
    window.cancelAnimationFrame(this._pendingFrameId);
    this._pendingFrameId = 0;
  }
}

/**
 * Finds the visible vertical bounds imposed by the viewport and clipping ancestors.
 * @param {Element} element Element whose ancestors may clip overflowing content.
 * @param {number} [viewportGap=VIEWPORT_GAP] Space kept from each visible edge.
 * @returns {{top: number, bottom: number}} Visible vertical bounds.
 */
export const getVisibleVerticalBounds = (element, viewportGap = VIEWPORT_GAP) => {
  const bounds = {
    top: viewportGap,
    bottom: window.innerHeight - viewportGap,
  };
  let ancestor = element.parentElement;

  while (ancestor) {
    const styles = window.getComputedStyle(ancestor);
    if (CLIPPING_OVERFLOW_VALUES.has(styles.overflowY) || CLIPPING_OVERFLOW_VALUES.has(styles.overflow)) {
      const ancestorBounds = ancestor.getBoundingClientRect();
      bounds.top = Math.max(bounds.top, ancestorBounds.top + viewportGap);
      bounds.bottom = Math.min(bounds.bottom, ancestorBounds.bottom - viewportGap);
    }
    ancestor = ancestor.parentElement;
  }

  return bounds;
};

/**
 * Fits an absolutely positioned dropdown inside the visible area.
 *
 * The dropdown keeps its template position below the anchor unless it does not
 * fit there and the space above is larger. Its height is capped to the space
 * available on the chosen side, never exceeding its stylesheet max height, so
 * every option stays reachable without scrolling the page.
 * @param {HTMLElement} anchor Element the dropdown opens from.
 * @param {HTMLElement} dropdown Visible, absolutely positioned dropdown.
 * @returns {void}
 */
export const placeDropdown = (anchor, dropdown) => {
  // Measure the template placement, keeping the list scroll position
  const scrollTop = dropdown.scrollTop;
  clearDropdownPlacement(dropdown);

  const styles = window.getComputedStyle(dropdown);
  const gap = Number.parseFloat(styles.marginTop) || 0;
  const styleMaxHeight = Number.parseFloat(styles.maxHeight);
  const desiredHeight = Number.isNaN(styleMaxHeight)
    ? dropdown.scrollHeight
    : Math.min(dropdown.scrollHeight, styleMaxHeight);
  const anchorBounds = anchor.getBoundingClientRect();
  const visibleBounds = getVisibleVerticalBounds(anchor);
  const availableBelow = visibleBounds.bottom - dropdown.getBoundingClientRect().top;
  const availableAbove = anchorBounds.top - gap - visibleBounds.top;
  const container = getPositionedContainer(dropdown);
  const placeAbove = container !== null && desiredHeight > availableBelow && availableAbove > availableBelow;

  // Anchor the dropdown bottom edge just above the anchor
  if (placeAbove) {
    const containerBounds = container.getBoundingClientRect();
    const containerBottom = containerBounds.top + container.clientTop + container.clientHeight;
    dropdown.style.insetBlockStart = "auto";
    dropdown.style.insetBlockEnd = `${containerBottom - anchorBounds.top + gap}px`;
  }

  // Cap the height to the room left on the chosen side
  const availableHeight = Math.max(0, placeAbove ? availableAbove : availableBelow);
  if (desiredHeight > availableHeight) {
    dropdown.style.maxHeight = `${availableHeight}px`;
  }

  dropdown.scrollTop = scrollTop;
};

/**
 * Clears inline placement so a dropdown uses its template position.
 * @param {HTMLElement} dropdown Dropdown element.
 * @returns {void}
 */
const clearDropdownPlacement = (dropdown) => {
  dropdown.style.insetBlockStart = "";
  dropdown.style.insetBlockEnd = "";
  dropdown.style.maxHeight = "";
};

/**
 * Returns the positioned ancestor that absolutely positioned offsets refer to.
 * @param {HTMLElement} dropdown Dropdown element.
 * @returns {HTMLElement|null} Positioned container, or null when there is none.
 */
const getPositionedContainer = (dropdown) => {
  const container = dropdown.offsetParent;
  if (!(container instanceof HTMLElement) || window.getComputedStyle(container).position === "static") {
    return null;
  }
  return container;
};

/**
 * Checks whether a value is an element that currently generates layout boxes.
 * @param {unknown} element Value to inspect.
 * @returns {boolean} True when the element is rendered.
 */
const isRenderedElement = (element) => element instanceof HTMLElement && element.getClientRects().length > 0;
