import { html, nothing } from "lit";
import { repeat } from "lit/directives/repeat.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * MultipleInputs component for managing a dynamic list of text inputs.
 * Allows users to add/remove multiple values for array-type form fields like tags.
 * Automatically generates hidden form inputs with array notation (field-name[]).
 * @extends LitWrapper
 */
export class MultipleInputs extends LitWrapper {
  /**
   * Component properties definition
   * @property {Array} items - Array of string values to display in the inputs
   * @property {string} fieldName - Name attribute for the hidden form inputs (will append [])
   * @property {string} inputType - Input type (text, url, email, tel, number)
   * @property {string} placeholder - Placeholder text for the input fields
   * @property {string} label - Label for the "Add" button (e.g., "Add Tag")
   * @property {string} legend - Optional legend text displayed below the inputs
   * @property {boolean} required - If true, prevents removing the last input
   * @property {number} maxItems - Maximum number of items allowed (0 = unlimited)
   * @property {number} maxLength - Maximum length allowed for each input value
   * @property {string} pattern - Optional pattern each non-empty value must fully match
   * @property {string} patternMessage - Validation message for values not matching the pattern
   * @property {boolean} unique - If true, rejects values repeated in the list
   * @property {Array<string>} excludedValues - Values that cannot be added to the list
   * @property {string} excludedMessage - Validation message for excluded values
   */
  static properties = {
    items: { type: Array },
    fieldName: { type: String, attribute: "field-name" },
    inputType: { type: String, attribute: "input-type" },
    placeholder: { type: String },
    label: { type: String },
    legend: { type: String },
    required: { type: Boolean },
    maxItems: { type: Number, attribute: "max-items" },
    maxLength: { type: Number, attribute: "max-length" },
    pattern: { type: String },
    patternMessage: { type: String, attribute: "pattern-message" },
    unique: { type: Boolean },
    excludedValues: { type: Array, attribute: "excluded-values" },
    excludedMessage: { type: String, attribute: "excluded-message" },
  };

  constructor() {
    super();
    this.items = null;
    this.fieldName = "";
    this.inputType = "text";
    this.placeholder = "";
    this.label = "";
    this.legend = "";
    this.required = false;
    this.maxItems = 0; // 0 means no limit
    this.maxLength = 0; // 0 means no limit
    this.pattern = "";
    this.patternMessage = "";
    this.unique = false;
    this.excludedValues = [];
    this.excludedMessage = "";
    this._nextId = 0;
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
   * Normalizes item updates applied after the component is connected.
   * @param {Map<PropertyKey, unknown>} changedProperties Changed reactive properties.
   */
  willUpdate(changedProperties) {
    if (changedProperties.has("items") && !this.items?.every?.((item) => typeof item?.value === "string")) {
      this._loadInitialData();
    }
  }

  /**
   * Synchronizes the validity of the rendered inputs with their values.
   */
  updated() {
    this._syncValidity();
  }

  /**
   * Normalizes the items array structure on component initialization.
   * Ensures each item has both 'id' and 'value' properties by mapping over
   * existing items and assigning stable unique IDs. Initializes the _nextId
   * counter to prevent ID collisions in future operations.
   * @private
   */
  _loadInitialData() {
    if (this.items && this.items.length > 0) {
      this.items = this.items.map((item, index) => {
        const itemValue = typeof item === "object" && item !== null ? item.value : item;
        return {
          id: index,
          value: typeof itemValue === "string" ? itemValue : "",
        };
      });
      // Set _nextId to prevent future ID collisions
      this._nextId = this.items.length;
    } else {
      this.items = [{ id: 0, value: "" }];
      // Set _nextId to 1 to prevent ID collision with the initial item
      this._nextId = 1;
    }
  }

  /**
   * Adds a new empty input field to the list.
   * Respects maxItems limit if set.
   * @private
   */
  _addItem() {
    if (this.maxItems > 0 && this.items.length >= this.maxItems) {
      return;
    }

    this.items = [...this.items, { id: this._nextId++, value: "" }];
  }

  /**
   * Removes an item from the list by its ID.
   * Prevents removing the last item if required is true.
   * Ensures at least one empty item remains in the list.
   * @param {string} itemId - The ID of the item to remove
   * @private
   */
  _removeItem(itemId) {
    if (this.items.length <= 1 && this.required) {
      // Don't allow removing the last item if required
      return;
    }

    this.items = this.items.filter((item) => item.id !== itemId);

    // Ensure at least one empty item remains if list becomes empty
    if (this.items.length === 0) {
      this.items = [{ id: this._nextId++, value: "" }];
    }
  }

  /**
   * Updates the value of an item by its ID.
   * @param {string} itemId - The ID of the item to update
   * @param {string} value - The new value for the item
   * @private
   */
  _updateItem(itemId, value) {
    this.items = this.items.map((item) => (item.id === itemId ? { ...item, value } : item));
  }

  /**
   * Handles input change events.
   * Updates the item value based on user input.
   * @param {string} itemId - The ID of the changed input
   * @param {Event} event - The input change event
   * @private
   */
  _handleInputChange(itemId, event) {
    const value = event.target.value;
    this._updateItem(itemId, value);
  }

  /**
   * Determines if the add button should be disabled.
   * Button is disabled when maxItems limit is reached.
   * @returns {boolean} True if add button should be disabled
   * @private
   */
  _isAddButtonDisabled() {
    return this.maxItems > 0 && this.items.length >= this.maxItems;
  }

  /**
   * Returns the validation message for an item value, or an empty string when valid.
   * Blank values are valid, as they are not submitted.
   * @param {string} value - The item value
   * @param {Set<string>} previousValues - Submitted values of the preceding items
   * @returns {string} Validation message
   * @private
   */
  _getValidationMessage(value, previousValues) {
    if (value.trim() === "") {
      return "";
    }

    if (this.pattern && !new RegExp(`^(?:${this.pattern})$`).test(value)) {
      return this.patternMessage || "Please match the requested format.";
    }

    if (this.excludedValues?.includes(value)) {
      return this.excludedMessage || "This value is not allowed.";
    }

    if (this.unique && previousValues.has(value)) {
      return "This value is already in the list.";
    }

    return "";
  }

  /**
   * Applies the pattern, exclusion, and uniqueness rules to the rendered inputs,
   * so the form cannot be submitted while any value breaks them.
   * @private
   */
  _syncValidity() {
    const inputs = this.querySelectorAll("input[data-item-input]");
    const previousValues = new Set();

    this.items.forEach((item, index) => {
      inputs[index]?.setCustomValidity(this._getValidationMessage(item.value, previousValues));
      if (item.value.trim() !== "") {
        previousValues.add(item.value);
      }
    });
  }

  /**
   * Validates and returns a valid input type.
   * Falls back to "text" if the specified type is not supported.
   * @returns {string} Valid HTML input type
   * @private
   */
  _getValidInputType() {
    const validTypes = ["text", "url", "email", "tel", "number"];
    return validTypes.includes(this.inputType) ? this.inputType : "text";
  }

  /**
   * Resets the component to initial state.
   * Clears all items and adds a single empty input.
   * @public
   */
  reset() {
    this.items = [{ id: 0, value: "" }];
    this._nextId = 1;
    this.requestUpdate();
  }

  /**
   * Renders the multiple inputs component.
   * Displays a list of input fields with add/remove buttons.
   * Generates hidden form inputs for non-empty values.
   * @returns {TemplateResult} Lit HTML template
   */
  render() {
    const validInputType = this._getValidInputType();

    return html`
      <div class="space-y-3">
        ${repeat(
          this.items,
          (item) => item.id,
          (item) => {
            const isItemEmpty = item.value.trim() === "";
            const isRemoveDisabled = isItemEmpty || (this.items.length <= 1 && this.required);

            return html`
              <div class="flex items-center gap-2">
                <div class="flex-1">
                  <input
                    type=${validInputType}
                    class="input-primary w-full"
                    placeholder=${this.placeholder}
                    value=${item.value}
                    @input=${(event) => this._handleInputChange(item.id, event)}
                    autocomplete="off"
                    autocorrect="off"
                    autocapitalize="off"
                    spellcheck="false"
                    maxlength=${this.maxLength > 0 ? this.maxLength : nothing}
                    data-item-input
                  />
                </div>
                <button
                  type="button"
                  class=${`p-2 border border-stone-200 rounded-full ${
                    isRemoveDisabled ? "" : "cursor-pointer hover:bg-stone-100"
                  }`}
                  title="Remove item"
                  @click=${() => this._removeItem(item.id)}
                  ?disabled=${isRemoveDisabled}
                >
                  <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
                </button>
              </div>
            `;
          },
        )}

        <!-- Legend text -->
        ${this.legend && this.legend.trim() !== "" ? html`<p class="form-legend">${this.legend}</p>` : ""}

        <button
          type="button"
          class="btn-primary-outline btn-mini"
          @click=${this._addItem}
          ?disabled=${this._isAddButtonDisabled()}
        >
          Add ${this.label || "Item"}
        </button>
      </div>
      <!-- Hidden inputs for form submission -->
      <div class="hidden">
        ${
          this.fieldName
            ? this.items.map((item) =>
                item.value.trim() !== ""
                  ? html` <input type="hidden" name="${this.fieldName}[]" value=${item.value} /> `
                  : "",
              )
            : ""
        }
      </div>
    `;
  }
}

customElements.define("multiple-inputs", MultipleInputs);
