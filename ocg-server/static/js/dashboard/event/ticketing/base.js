import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  resolveCurrencyInputPlaceholder,
  resolveCurrencyInputStep,
  resolveEventCurrencyCode,
} from "/static/js/dashboard/event/ticketing/money.js";

/**
 * Shared base for ticketing editors.
 * @extends LitWrapper
 */
export class TicketingEditorBase extends LitWrapper {
  static properties = {
    disabled: { type: Boolean, reflect: true },
  };

  constructor() {
    super();
    this.disabled = false;
    this.fieldNamePrefix = "";
    this.presenceFieldName = "";
    this._handleCurrencyFieldChange = this._handleCurrencyFieldChange.bind(this);
    this._nextId = 0;
  }

  connectedCallback() {
    super.connectedCallback();
    document
      .getElementById("payment_currency_code")
      ?.addEventListener("input", this._handleCurrencyFieldChange);
  }

  disconnectedCallback() {
    document
      .getElementById("payment_currency_code")
      ?.removeEventListener("input", this._handleCurrencyFieldChange);
    super.disconnectedCallback();
  }

  /**
   * Returns the active event currency code.
   * @returns {string}
   */
  _currencyCode() {
    return resolveEventCurrencyCode();
  }

  /**
   * Returns the currency input placeholder for the event currency.
   * @returns {string}
   */
  _currencyInputPlaceholder() {
    return resolveCurrencyInputPlaceholder(this._currencyCode());
  }

  /**
   * Returns the currency input step for the event currency.
   * @returns {string}
   */
  _currencyInputStep() {
    return resolveCurrencyInputStep(this._currencyCode());
  }

  /**
   * Returns a label suffix for the event currency.
   * @returns {string}
   */
  _currencyLabelSuffix() {
    return `(${this._currencyCode()})`;
  }

  /**
   * Emits a change event for dependent UI like waitlist controls.
   * @param {string} eventName Event name
   * @param {object} detail Event detail
   */
  _emitChange(eventName, detail) {
    this.dispatchEvent(
      new CustomEvent(eventName, {
        bubbles: true,
        composed: true,
        detail,
      }),
    );
  }

  /**
   * Handles changes to the shared event currency input.
   */
  _handleCurrencyFieldChange() {
    this.requestUpdate();
  }

  /**
   * Returns a new local row id.
   * @returns {number}
   */
  _nextRowId() {
    const rowId = this._nextId;
    this._nextId += 1;
    return rowId;
  }

  /**
   * Renders a hidden input field.
   * @param {string} name Input name
   * @param {string} value Input value
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult}
   */
  _renderHiddenInput(name, value) {
    return html`<input type="hidden" name="${name}" .value=${value} />`;
  }

  /**
   * Renders the presence flag for the current editor.
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult|string}
   */
  _renderPresenceField() {
    if (this.disabled || !this.presenceFieldName) {
      return "";
    }

    return this._renderHiddenInput(this.presenceFieldName, "true");
  }
}
