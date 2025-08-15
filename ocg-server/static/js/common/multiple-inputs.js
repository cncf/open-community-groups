import { html } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { triggerChangeOnForm } from "/static/js/dashboard/common.js";

export class MultipleInputs extends LitWrapper {
  static properties = {
    items: { type: Array },
    fieldName: { type: String, attribute: "field-name" },
    inputType: { type: String, attribute: "input-type" },
    placeholder: { type: String },
    label: { type: String },
    required: { type: Boolean },
    maxItems: { type: Number, attribute: "max-items" },
  };

  constructor() {
    super();
    this.items = [""];
    this.fieldName = "";
    this.inputType = "text";
    this.placeholder = "";
    this.label = "";
    this.required = false;
    this.maxItems = 0; // 0 means no limit
  }

  connectedCallback() {
    super.connectedCallback();
    this._loadInitialData();
  }

  _loadInitialData() {
    // Ensure items is always an array
    if (!this.items) {
      this.items = [""];
    }
  }

  _addItem() {
    if (this.maxItems > 0 && this.items.length >= this.maxItems) {
      return;
    }

    this.items = [...this.items, ""];
  }

  _removeItem(index) {
    if (this.items.length <= 1 && this.required) {
      // Don't allow removing the last item if required
      return;
    }

    this.items = this.items.filter((_, i) => i !== index);

    // Ensure at least one empty item remains if list becomes empty
    if (this.items.length === 0) {
      this.items = [""];
    }
  }

  _updateItem(index, value) {
    const newItems = [...this.items];
    newItems[index] = value;
    this.items = newItems;
  }

  _handleInputChange(index, event) {
    const value = event.target.value;
    this._updateItem(index, value);
  }

  _isAddButtonDisabled() {
    return this.maxItems > 0 && this.items.length >= this.maxItems;
  }

  _getValidInputType() {
    const validTypes = ["text", "url", "email", "tel", "number"];
    return validTypes.includes(this.inputType) ? this.inputType : "text";
  }

  reset() {
    this.items = [""];
    this.requestUpdate();
  }

  render() {
    const validInputType = this._getValidInputType();

    return html`
      <div class="space-y-3">
        ${this.items.map(
          (item, index) => html`
            <div class="flex items-center gap-2">
              <div class="flex-1">
                <input
                  type="${validInputType}"
                  class="input-primary w-full"
                  placeholder="${this.placeholder}"
                  value="${item}"
                  @input="${(e) => this._handleInputChange(index, e)}"
                  autocomplete="off"
                  autocorrect="off"
                  autocapitalize="off"
                  spellcheck="false"
                />
              </div>
              <button
                type="button"
                class="cursor-pointer p-2 border border-stone-200 hover:bg-stone-100 rounded-full"
                title="Remove item"
                @click="${() => this._removeItem(index)}"
                ?disabled="${this.items.length <= 1 && this.required}"
              >
                <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
              </button>
            </div>
          `,
        )}

        <button
          type="button"
          class="btn-mini"
          @click="${this._addItem}"
          ?disabled="${this._isAddButtonDisabled()}"
        >
          Add ${this.label || "Item"}
        </button>

        <!-- Hidden inputs for form submission -->
        ${this.fieldName
          ? this.items.map((item, index) =>
              item.trim() !== ""
                ? html` <input type="hidden" name="${this.fieldName}[]" value="${item}" /> `
                : "",
            )
          : ""}
      </div>
    `;
  }
}

customElements.define("multiple-inputs", MultipleInputs);
