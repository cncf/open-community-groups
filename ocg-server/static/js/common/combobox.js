import { bindOutsideClickListener } from "/static/js/common/dom.js";
import { getNextLoopedIndex, isEscapeEvent } from "/static/js/common/keyboard.js";
import { clearTimeoutId, replaceTimeout } from "/static/js/common/timers.js";

// Controls that open a closed dropdown with ArrowDown.
const COMBOBOX_CONTROL_SELECTOR = '[role="combobox"], [aria-haspopup="listbox"]';
// Native controls inside the host that keep their own Enter behavior.
const NATIVE_ENTER_SELECTOR = "a[href], button:not([aria-haspopup])";

/**
 * Shared reactive controller for searchable dropdown (combobox) components.
 *
 * The controller owns the open flag, search query and active option index, the
 * outside-click and focus-out handling and the shared keyboard interactions: Escape
 * closes the dropdown, ArrowDown opens it from its control, ArrowDown/ArrowUp move
 * the highlight with wraparound and Enter selects the highlighted option. Enter on
 * other buttons and links inside the host keeps its native behavior. Hosts keep their own data, filtering, rendering and
 * selection model and expose them through the callbacks below, so single-select
 * and multi-select components can share the same state machine.
 */
export class ComboboxController {
  /**
   * @param {import("lit").ReactiveControllerHost & HTMLElement} host Host component.
   * @param {object} options Controller options.
   * @param {() => number} options.getItemCount Number of currently filtered options.
   * @param {(index: number, event: KeyboardEvent) => void} options.onSelect Called when
   *   Enter is pressed with a highlighted option.
   * @param {() => boolean} [options.isInteractionBlocked] Guard for disabled/busy hosts.
   * @param {() => boolean} [options.canOpen] Extra guard checked before opening.
   * @param {() => void} [options.onOpen] Hook run right after the dropdown opens.
   * @param {() => void} [options.onClose] Hook run right after the dropdown closes.
   * @param {() => void} [options.onActiveIndexMove] Hook run after keyboard moves.
   * @param {boolean} [options.resetQueryOnToggle=false] Whether open/close clear the
   *   query (single-select style) instead of keeping it (multi-select style).
   */
  constructor(host, options) {
    this.host = host;
    this._options = options;
    this.isOpen = false;
    this.query = "";
    this.activeIndex = null;
    this._searchTimeoutId = 0;
    this._documentClickHandler = null;
    this._handleFocusout = this._handleFocusout.bind(this);
    this._handleKeydown = this._handleKeydown.bind(this);
    host.addController(this);
  }

  hostConnected() {
    this.host.addEventListener("focusout", this._handleFocusout);
    this.host.addEventListener("keydown", this._handleKeydown);
  }

  hostDisconnected() {
    this.host.removeEventListener("focusout", this._handleFocusout);
    this.host.removeEventListener("keydown", this._handleKeydown);
    this._removeDocumentListener();
    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);
  }

  /**
   * Opens the dropdown and starts listening for outside clicks.
   * @returns {void}
   */
  open() {
    if (this._isInteractionBlocked() || !(this._options.canOpen?.() ?? true)) {
      return;
    }
    this.isOpen = true;
    if (this._options.resetQueryOnToggle) {
      this.query = "";
    }
    this.activeIndex = null;
    this._addDocumentListener();
    this.host.requestUpdate();
    this._options.onOpen?.();
  }

  /**
   * Closes the dropdown and clears transient interaction state.
   * @returns {void}
   */
  close() {
    this.isOpen = false;
    if (this._options.resetQueryOnToggle) {
      this.query = "";
    }
    this.activeIndex = null;
    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);
    this._removeDocumentListener();
    this.host.requestUpdate();
    this._options.onClose?.();
  }

  /**
   * Toggles dropdown visibility unless host interactions are blocked.
   * @returns {void}
   */
  toggle() {
    if (this._isInteractionBlocked()) {
      return;
    }
    if (this.isOpen) {
      this.close();
    } else {
      this.open();
    }
  }

  /**
   * Updates the search query and re-renders the host.
   * @param {string} query New search query.
   * @returns {void}
   */
  setQuery(query) {
    this.query = query;
    this.host.requestUpdate();
  }

  /**
   * Updates the highlighted option index and re-renders the host.
   * @param {number|null} index New active index.
   * @returns {void}
   */
  setActiveIndex(index) {
    this.activeIndex = index;
    this.host.requestUpdate();
  }

  /**
   * Debounces a search-driven update, replacing any pending one.
   * @param {() => void} callback Update to run after the delay.
   * @param {number} delay Delay in milliseconds.
   * @returns {void}
   */
  scheduleSearchUpdate(callback, delay) {
    this._searchTimeoutId = replaceTimeout(
      this._searchTimeoutId,
      () => {
        this._searchTimeoutId = 0;
        callback();
      },
      delay,
    );
  }

  /**
   * Checks whether the host currently blocks dropdown interactions.
   * @returns {boolean} True when interactions are blocked.
   */
  _isInteractionBlocked() {
    return this._options.isInteractionBlocked?.() === true;
  }

  /**
   * Registers a click listener on document to detect outside clicks.
   * @returns {void}
   */
  _addDocumentListener() {
    if (this._documentClickHandler) {
      return;
    }
    this._documentClickHandler = bindOutsideClickListener(this.host, () => this.close());
  }

  /**
   * Removes the outside click listener if it exists.
   * @returns {void}
   */
  _removeDocumentListener() {
    if (!this._documentClickHandler) {
      return;
    }
    this._documentClickHandler();
    this._documentClickHandler = null;
  }

  /**
   * Closes the dropdown when focus moves to an element outside the host, such
   * as on Tab. Focus lost without a new target is left to the outside-click
   * listener, so clicks on options that do not take focus still land.
   * @param {FocusEvent} event Native focusout event.
   * @returns {void}
   */
  _handleFocusout(event) {
    const nextTarget = event.relatedTarget;
    if (!this.isOpen || !(nextTarget instanceof Node) || this.host.contains(nextTarget)) {
      return;
    }
    this.close();
  }

  /**
   * Handles the shared combobox keyboard interactions.
   * @param {KeyboardEvent} event Native keyboard event.
   * @returns {void}
   */
  _handleKeydown(event) {
    if (event.defaultPrevented || this._isInteractionBlocked()) {
      return;
    }

    // Open a closed dropdown from its control, as combobox users expect.
    if (!this.isOpen) {
      if (event.key === "ArrowDown" && isElementMatching(event.target, COMBOBOX_CONTROL_SELECTOR)) {
        event.preventDefault();
        this.open();
      }
      return;
    }

    if (isEscapeEvent(event)) {
      event.preventDefault();
      this.close();
      return;
    }

    const itemCount = this._options.getItemCount();
    if (itemCount === 0) {
      return;
    }

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this.setActiveIndex(getNextLoopedIndex(this.activeIndex, itemCount, 1));
        this._options.onActiveIndexMove?.();
        break;
      case "ArrowUp":
        event.preventDefault();
        this.setActiveIndex(getNextLoopedIndex(this.activeIndex, itemCount, -1));
        this._options.onActiveIndexMove?.();
        break;
      case "Enter":
        if (isElementMatching(event.target, NATIVE_ENTER_SELECTOR)) {
          break;
        }
        event.preventDefault();
        if (this.activeIndex !== null) {
          this._options.onSelect(this.activeIndex, event);
        }
        break;
      default:
        break;
    }
  }
}

/**
 * Checks whether an event target is an element matching a selector.
 * @param {EventTarget|null} target Event target.
 * @param {string} selector CSS selector.
 * @returns {boolean} True when the target matches.
 */
const isElementMatching = (target, selector) => target instanceof Element && target.matches(selector);
