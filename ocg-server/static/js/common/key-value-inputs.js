import { html, repeat } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * KeyValueInputs component for managing key-value pairs in forms.
 * Allows users to add/remove multiple key-value pairs dynamically.
 * Automatically generates hidden form inputs with bracket notation (field-name[key]).
 * @extends LitWrapper
 */
export class KeyValueInputs extends LitWrapper {
  /**
   * Component properties definition
   * @property {Object} items - Object containing key-value pairs to display
   * @property {string} fieldName - Name attribute for hidden form inputs (will use field-name[key])
   * @property {string} keyPlaceholder - Placeholder text for key input fields
   * @property {string} valuePlaceholder - Placeholder text for value input fields
   * @property {string} label - Label for the "Add" button (e.g., "Add Link")
   * @property {number} maxItems - Maximum number of key-value pairs allowed (0 = unlimited)
   */
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

  /**
   * Lifecycle callback when component is added to DOM.
   * Initializes the component and loads initial data.
   */
  connectedCallback() {
    super.connectedCallback();
    this._loadInitialData();
  }

  /**
   * Loads and converts initial data from object format to internal array format.
   * Ensures at least one empty key-value pair exists for user input.
   * @private
   */
  _loadInitialData() {
    // Convert to array format for internal use
    this._itemsArray = this._objectToArray(this.items);

    // Ensure we always have at least one empty input pair
    if (this._itemsArray.length === 0) {
      this._itemsArray = [{ key: "", value: "" }];
    }
  }

  /**
   * Converts an object to an array of key-value pair objects.
   * @param {Object} obj - Object to convert
   * @returns {Array<{key: string, value: string}>} Array of key-value pairs
   * @private
   */
  _objectToArray(obj) {
    return Object.entries(obj || {}).map(([key, value]) => ({ key, value }));
  }

  /**
   * Converts an array of key-value pairs to an object.
   * Filters out empty keys and values.
   * @param {Array<{key: string, value: string}>} arr - Array of key-value pairs
   * @returns {Object} Object with key-value pairs
   * @private
   */
  _arrayToObject(arr) {
    const obj = {};
    arr.forEach(({ key, value }) => {
      if (key.trim() !== "" && value.trim() !== "") {
        obj[key.trim()] = value.trim();
      }
    });
    return obj;
  }

  /**
   * Adds a new empty key-value pair to the list.
   * Respects maxItems limit if set.
   * @private
   */
  _addItem() {
    if (this.maxItems > 0 && this._itemsArray.length >= this.maxItems) {
      return;
    }

    this._itemsArray = [...this._itemsArray, { key: "", value: "" }];
    this.items = this._arrayToObject(this._itemsArray);
  }

  /**
   * Removes a key-value pair at the specified index.
   * Ensures at least one empty pair remains for user input.
   * @param {number} index - The index of the pair to remove
   * @private
   */
  _removeItem(index) {
    if (this._itemsArray.length <= 1) {
      // Don't allow removing the last item, just clear it
      this._itemsArray = [{ key: "", value: "" }];
    } else {
      this._itemsArray = this._itemsArray.filter((_, i) => i !== index);
    }
    this.items = this._arrayToObject(this._itemsArray);
  }

  /**
   * Updates a specific field (key or value) of a pair at the given index.
   * @param {number} index - The index of the pair to update
   * @param {string} field - The field to update ('key' or 'value')
   * @param {string} value - The new value for the field
   * @private
   */
  _updateItem(index, field, value) {
    const newItems = [...this._itemsArray];
    newItems[index] = { ...newItems[index], [field]: value };
    this._itemsArray = newItems;
    this.items = this._arrayToObject(this._itemsArray);
  }

  /**
   * Handles input change events for key or value fields.
   * @param {number} index - The index of the changed pair
   * @param {string} field - The field that changed ('key' or 'value')
   * @param {Event} event - The input change event
   * @private
   */
  _handleInputChange(index, field, event) {
    const value = event.target.value;
    this._updateItem(index, field, value);
  }

  /**
   * Determines if the add button should be disabled.
   * Button is disabled when maxItems limit is reached.
   * @returns {boolean} True if add button should be disabled
   * @private
   */
  _isAddButtonDisabled() {
    return this.maxItems > 0 && this._itemsArray.length >= this.maxItems;
  }

  /**
   * Resets the component to initial state.
   * Clears all pairs and adds a single empty pair.
   * @public
   */
  reset() {
    this._itemsArray = [{ key: "", value: "" }];
    this.items = {};
    this.requestUpdate();
  }

  /**
   * Renders the key-value inputs component.
   * Displays pairs of input fields with remove buttons.
   * Generates hidden form inputs for non-empty pairs.
   * @returns {TemplateResult} Lit HTML template
   */
  render() {
    return html`
      <div class="space-y-3">
        ${repeat(
          this._itemsArray,
          (item, index) => index,
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
          class="btn-primary-outline btn-mini"
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
