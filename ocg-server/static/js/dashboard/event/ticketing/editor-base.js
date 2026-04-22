import { resolveEventTimezone, unlockBodyScroll } from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  resolveCurrencyInputPlaceholder,
  resolveCurrencyInputStep,
  resolveEventCurrencyCode,
} from "/static/js/dashboard/event/ticketing/currency.js";

/**
 * Shared base class for ticketing editors with external form dependencies.
 * @extends LitWrapper
 */
export class TicketingEditorBase extends LitWrapper {
  static properties = {
    disabled: { type: Boolean },
    _draftRow: { state: true },
    _editingRowId: { state: true },
    _isModalOpen: { state: true },
    _isNewRow: { state: true },
    _rows: { state: true },
  };

  constructor() {
    super();
    this.disabled = false;
    this._rows = [];
    this._draftRow = null;
    this._editingRowId = null;
    this._isModalOpen = false;
    this._isNewRow = false;
    this._nextId = 0;
    this._hasInitializedState = false;
    this.addButton = null;
    this.currencyInput = null;
    this.timezoneInput = null;

    this._boundHandleExternalAddClick = this._handleExternalAddClick.bind(this);
    this._boundHandleDependencyChange = this._handleDependencyChange.bind(this);
    this._boundHandleKeydown = this._handleKeydown.bind(this);
  }

  /**
   * Binds keyboard handling and shared form dependencies on connect.
   */
  connectedCallback() {
    super.connectedCallback();
    this._resolveDocument().addEventListener("keydown", this._boundHandleKeydown);
    this.configure();
  }

  /**
   * Rehydrates rows when the serialized editor attribute changes after mount.
   * @param {Map<string, *>} changedProperties Changed reactive properties
   * @returns {void}
   */
  willUpdate(changedProperties) {
    super.willUpdate?.(changedProperties);

    if (changedProperties.has(this._editorDataProperty) && this._hasInitializedState) {
      this._applyEditorData(this[this._editorDataProperty]);
    }
  }

  /**
   * Removes shared listeners and restores body scrolling when detached.
   */
  disconnectedCallback() {
    this._resolveDocument().removeEventListener("keydown", this._boundHandleKeydown);
    this._setAddButton(null);
    this._setCurrencyInput(null);
    this._setTimezoneInput(null);

    if (this._isModalOpen) {
      unlockBodyScroll();
    }

    super.disconnectedCallback?.();
  }

  /**
   * Resolves shared controls and synchronizes the editor with current form state.
   * @param {{
   *   addButton?: HTMLElement|null,
   *   currencyInput?: HTMLInputElement|HTMLSelectElement|null,
   *   timezoneInput?: HTMLInputElement|HTMLElement|null
   * }} [options={}] Explicit dependency overrides
   * @returns {void}
   */
  configure({ addButton = null, currencyInput = null, timezoneInput = null } = {}) {
    this.disabled = this.dataset.disabled === "true";
    this._setAddButton(addButton || this._resolveAddButton());
    this._setCurrencyInput(currencyInput || this._resolveCurrencyInput());
    this._setTimezoneInput(timezoneInput || this._resolveTimezoneInput());

    if (!this._hasInitializedState) {
      this._applyEditorData(this[this._editorDataProperty]);
      this._hasInitializedState = true;
    } else {
      this.requestUpdate();
    }
  }

  /**
   * Resolves the document that owns the editor.
   * @returns {Document}
   */
  _resolveDocument() {
    return this.ownerDocument || document;
  }

  /**
   * Finds the shared add button for the current page.
   * @returns {HTMLElement|null}
   */
  _resolveAddButton() {
    return this._resolveDocument().getElementById(this._addButtonId);
  }

  /**
   * Finds the event currency input for the current page.
   * @returns {HTMLInputElement|HTMLSelectElement|null}
   */
  _resolveCurrencyInput() {
    return this._resolveDocument().getElementById("payment_currency_code");
  }

  /**
   * Finds the event timezone input for the current page.
   * @returns {HTMLInputElement|HTMLElement|null}
   */
  _resolveTimezoneInput() {
    return this._resolveDocument().querySelector('[name="timezone"]');
  }

  /**
   * Wires a shared dependency target to the editor lifecycle.
   * @param {string} propertyName Element property to update
   * @param {HTMLElement|null} nextTarget Target element
   * @param {string[]} eventNames DOM events to bind
   * @param {Function} handler Shared event handler
   * @returns {void}
   */
  _setDependencyTarget(propertyName, nextTarget, eventNames, handler) {
    if (this[propertyName] === nextTarget) {
      return;
    }

    this[propertyName]?.removeEventListener?.(eventNames[0], handler);
    eventNames.slice(1).forEach((eventName) => {
      this[propertyName]?.removeEventListener?.(eventName, handler);
    });
    this[propertyName] = nextTarget;
    this[propertyName]?.addEventListener?.(eventNames[0], handler);
    eventNames.slice(1).forEach((eventName) => {
      this[propertyName]?.addEventListener?.(eventName, handler);
    });
  }

  /**
   * Updates the add button subscription.
   * @param {HTMLElement|null} addButton Button element
   * @returns {void}
   */
  _setAddButton(addButton) {
    this._setDependencyTarget("addButton", addButton, ["click"], this._boundHandleExternalAddClick);
  }

  /**
   * Updates the currency input subscriptions.
   * @param {HTMLInputElement|HTMLSelectElement|null} currencyInput Currency control
   * @returns {void}
   */
  _setCurrencyInput(currencyInput) {
    this._setDependencyTarget(
      "currencyInput",
      currencyInput,
      ["input", "change"],
      this._boundHandleDependencyChange,
    );
  }

  /**
   * Updates the timezone input subscriptions.
   * @param {HTMLInputElement|HTMLElement|null} timezoneInput Timezone control
   * @returns {void}
   */
  _setTimezoneInput(timezoneInput) {
    this._setDependencyTarget(
      "timezoneInput",
      timezoneInput,
      ["input", "change"],
      this._boundHandleDependencyChange,
    );
  }

  /**
   * Opens the editor modal from the external page button.
   * @returns {void}
   */
  _handleExternalAddClick() {
    this._openEditorModal();
  }

  /**
   * Refreshes computed labels when shared page dependencies change.
   * @returns {void}
   */
  _handleDependencyChange() {
    if (!this.isConnected) {
      return;
    }

    this.requestUpdate();
  }

  /**
   * Closes the modal when escape is pressed while it is open.
   * @param {KeyboardEvent} event Keyboard event
   * @returns {void}
   */
  _handleKeydown(event) {
    if (event.key === "Escape" && this._isModalOpen) {
      this._closeEditorModal();
    }
  }

  /**
   * Resolves the active event currency code.
   * @returns {string}
   */
  _currencyCode() {
    return resolveEventCurrencyCode(this.currencyInput);
  }

  /**
   * Resolves the active event timezone.
   * @returns {string}
   */
  _timezone() {
    return resolveEventTimezone(this.timezoneInput);
  }

  /**
   * Resolves the currency input placeholder for the active currency.
   * @returns {string}
   */
  _currencyInputPlaceholder() {
    return resolveCurrencyInputPlaceholder(this._currencyCode());
  }

  /**
   * Resolves the currency input step for the active currency.
   * @returns {string}
   */
  _currencyInputStep() {
    return resolveCurrencyInputStep(this._currencyCode());
  }

  /**
   * Renders a currency label suffix using the active currency code.
   * @returns {string}
   */
  _currencyLabelSuffix() {
    return `(${this._currencyCode()})`;
  }

  /**
   * Returns the next synthetic row id for draft and persisted rows.
   * @returns {number}
   */
  _nextRowId() {
    const rowId = this._nextId;
    this._nextId += 1;
    return rowId;
  }
}
