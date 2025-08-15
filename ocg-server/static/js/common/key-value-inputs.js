import { html } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

export class KeyValueInputs extends LitWrapper {
  static properties = {
    items: { type: Object },
    fieldName: { type: String, attribute: "field-name" },
    keyPlaceholder: { type: String, attribute: "key-placeholder" },
    valuePlaceholder: { type: String, attribute: "value-placeholder" },
    label: { type: String },
    maxItems: { type: Number, attribute: "max-items" },
  };

  constructor() {
    super();
    this.items = {};
    this.fieldName = "";
    this.keyPlaceholder = "Key";
    this.valuePlaceholder = "Value";
    this.label = "";
    this.maxItems = 0; // 0 means no limit
  }

  connectedCallback() {
    super.connectedCallback();
    this._loadInitialData();
  }

  _loadInitialData() {
    // Convert to array format for internal use
    this._itemsArray = this._objectToArray(this.items);

    // Ensure we always have at least one empty input pair
    if (this._itemsArray.length === 0) {
      this._itemsArray = [{ key: "", value: "" }];
    }
  }

  _objectToArray(obj) {
    return Object.entries(obj || {}).map(([key, value]) => ({ key, value }));
  }

  _arrayToObject(arr) {
    const obj = {};
    arr.forEach(({ key, value }) => {
      if (key.trim() !== "" && value.trim() !== "") {
        obj[key.trim()] = value.trim();
      }
    });
    return obj;
  }

  _addItem() {
    if (this.maxItems > 0 && this._itemsArray.length >= this.maxItems) {
      return;
    }

    this._itemsArray = [...this._itemsArray, { key: "", value: "" }];
    this.items = this._arrayToObject(this._itemsArray);
  }

  _removeItem(index) {
    if (this._itemsArray.length <= 1) {
      // Don't allow removing the last item, just clear it
      this._itemsArray = [{ key: "", value: "" }];
    } else {
      this._itemsArray = this._itemsArray.filter((_, i) => i !== index);
    }
    this.items = this._arrayToObject(this._itemsArray);
  }

  _updateItem(index, field, value) {
    const newItems = [...this._itemsArray];
    newItems[index] = { ...newItems[index], [field]: value };
    this._itemsArray = newItems;
    this.items = this._arrayToObject(this._itemsArray);
  }

  _handleInputChange(index, field, event) {
    const value = event.target.value;
    this._updateItem(index, field, value);
  }

  _isAddButtonDisabled() {
    return this.maxItems > 0 && this._itemsArray.length >= this.maxItems;
  }

  reset() {
    this._itemsArray = [{ key: "", value: "" }];
    this.items = {};
    this.requestUpdate();
  }

  render() {
    return html`
      <div class="space-y-3">
        ${this._itemsArray.map(
          (item, index) => html`
            <div class="flex items-center gap-2">
              <div class="flex-1 grid grid-cols-3 gap-2">
                <input
                  type="text"
                  class="input-primary"
                  placeholder="${this.keyPlaceholder}"
                  value="${item.key}"
                  @input="${(e) => this._handleInputChange(index, "key", e)}"
                  autocomplete="off"
                  autocorrect="off"
                  autocapitalize="off"
                  spellcheck="false"
                />
                <input
                  type="text"
                  class="input-primary col-span-2"
                  placeholder="${this.valuePlaceholder}"
                  value="${item.value}"
                  @input="${(e) => this._handleInputChange(index, "value", e)}"
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
          Add ${this.label || "Link"}
        </button>

        <!-- Hidden inputs for form submission -->
        ${this.fieldName
          ? this._itemsArray.map((item, index) =>
              item.key.trim() !== "" && item.value.trim() !== ""
                ? html`
                    <input
                      type="hidden"
                      name="${this.fieldName}[${item.key.trim()}]"
                      value="${item.value.trim()}"
                    />
                  `
                : "",
            )
          : ""}
      </div>
    `;
  }
}

customElements.define("key-value-inputs", KeyValueInputs);
