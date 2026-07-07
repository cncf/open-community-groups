import { html, repeat } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { showErrorAlert } from "/static/js/common/alerts.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { selectDashboardAndKeepTab } from "/static/js/common/dashboard-selection.js";
import { focusElementById } from "/static/js/common/dom.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * Base class for dashboard selectors that choose one item from a combobox.
 *
 * @property {boolean} _isSubmitting Whether the current selection is saving
 */
export class DashboardSelectorBase extends LitWrapper {
  static properties = {
    _isSubmitting: { state: true },
  };

  /**
   * @param {object} config Selector configuration.
   * @param {string} config.selectorName Stable selector prefix for DOM ids.
   * @param {string} config.itemsProperty Component property containing items.
   * @param {string} config.selectedIdProperty Property containing selected id.
   * @param {string} config.idField Item property containing the id.
   * @param {string} config.defaultLabel Button label when no item is selected.
   * @param {string} config.searchPlaceholder Search input placeholder.
   * @param {string} config.emptyLabel Empty filtered results label.
   * @param {string} config.errorLabel Entity label used in error messages.
   * @param {string|(() => string)} config.endpointBase Selection endpoint base.
   * @param {(item: object) => string} config.getItemLabel Item label getter.
   * @param {string} [config.optionHandlerName] Method used to select an option.
   * @param {boolean} [config.disableWhenEmpty=false] Disable button with no items.
   * @param {string} [config.disabledOpacityClass="opacity-80"] Disabled opacity.
   * @param {boolean} [config.debounceQuery=false] Debounce query assignment.
   * @param {string} [config.wrapperClass=""] Optional wrapper class.
   */
  constructor(config) {
    super();
    this._selectorConfig = config;
    this._isSubmitting = false;
    this._pendingQuery = "";
    this._combobox = new ComboboxController(this, {
      getItemCount: () => this._filteredItems.length,
      isInteractionBlocked: () => this._isSubmitting,
      canOpen: () => this._items.length > 0,
      resetQueryOnToggle: true,
      onOpen: () => {
        this._pendingQuery = "";
        this.updateComplete.then(() => {
          focusElementById(this, `${this._selectorConfig.selectorName}-search-input`);
        });
      },
      onClose: () => {
        this._pendingQuery = "";
      },
      onSelect: (index, event) => {
        const item = this._filteredItems[index];
        if (item && !this._isSelected(item)) {
          this._handleConfiguredItemClick(event, item);
        }
      },
    });
  }

  /**
   * Stores the current query and triggers filtering with simple debounce.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    const query = event.target.value || "";
    if (this._selectorConfig.debounceQuery) {
      this._pendingQuery = query;
      this._combobox.scheduleSearchUpdate(() => {
        this._combobox.setActiveIndex(null);
        this._combobox.setQuery(this._pendingQuery);
      }, 200);
      return;
    }

    this._combobox.setQuery(query);
    this._combobox.scheduleSearchUpdate(() => {
      this._combobox.setActiveIndex(null);
    }, 200);
  }

  /**
   * Gets filtered items based on current query.
   * @returns {Array<object>}
   */
  get _filteredItems() {
    const normalized = (this._combobox.query || "").trim().toLowerCase();
    if (!normalized) {
      return this._items;
    }
    return this._items.filter((item) => {
      return this._getItemLabel(item).toLowerCase().includes(normalized);
    });
  }

  /**
   * Triggers dashboard item selection and lets HTMX refresh the current URL.
   * @param {string|number} itemId Identifier of the item to select
   * @returns {Promise<void>}
   */
  async _selectDashboardItem(itemId) {
    const url = `${this._getEndpointBase()}/${itemId}/select`;
    await selectDashboardAndKeepTab(url);
  }

  /**
   * Handles clicks on an option and closes the dropdown.
   * @param {MouseEvent} event Option click event
   * @param {object} item Associated item data
   */
  async _handleItemClick(event, item) {
    if (this._isSelected(item) || this._isSubmitting) {
      event.preventDefault();
      return;
    }
    event.preventDefault();
    this._isSubmitting = true;
    this._combobox.close();
    try {
      await this._selectDashboardItem(this._getItemId(item));
    } catch (_) {
      showErrorAlert(
        `Something went wrong selecting the ${this._selectorConfig.errorLabel}. Please try again later.`,
      );
    } finally {
      this._isSubmitting = false;
    }
  }

  /**
   * Handles an option through the configured public selector method.
   * @param {MouseEvent|KeyboardEvent} event Option selection event
   * @param {object} item Associated item data
   */
  _handleConfiguredItemClick(event, item) {
    const optionHandlerName = this._selectorConfig.optionHandlerName;
    if (optionHandlerName && typeof this[optionHandlerName] === "function") {
      this[optionHandlerName](event, item);
      return;
    }
    this._handleItemClick(event, item);
  }

  /**
   * Returns the selected item object, or null when none is selected.
   * @returns {object|null}
   */
  _findSelectedItem() {
    if (this._items.length === 0) {
      return null;
    }
    const targetId = this._selectedId != null ? String(this._selectedId) : "";
    return this._items.find((item) => String(this._getItemId(item)) === targetId) || null;
  }

  /**
   * Checks whether the provided item matches the selected identifier.
   * @param {object} item Item metadata
   * @returns {boolean}
   */
  _isSelected(item) {
    return String(this._getItemId(item)) === String(this._selectedId || "");
  }

  /**
   * Renders optional content after the selector.
   * @param {object|null} _selectedItem Selected item
   * @returns {import("lit").TemplateResult|string}
   */
  _renderAfterSelector(_selectedItem) {
    return "";
  }

  /**
   * Gets all selector items from the configured property.
   * @returns {Array<object>}
   */
  get _items() {
    return this[this._selectorConfig.itemsProperty] || [];
  }

  /**
   * Gets the selected item identifier from the configured property.
   * @returns {string}
   */
  get _selectedId() {
    return this[this._selectorConfig.selectedIdProperty];
  }

  /**
   * Gets the configured label for an item.
   * @param {object} item Item metadata
   * @returns {string}
   */
  _getItemLabel(item) {
    return this._selectorConfig.getItemLabel(item) || "";
  }

  /**
   * Gets the configured id for an item.
   * @param {object} item Item metadata
   * @returns {string|number}
   */
  _getItemId(item) {
    return item[this._selectorConfig.idField];
  }

  /**
   * Gets the endpoint base used for selection requests.
   * @returns {string}
   */
  _getEndpointBase() {
    const endpointBase = this._selectorConfig.endpointBase;
    return typeof endpointBase === "function" ? endpointBase() : endpointBase;
  }

  /**
   * Checks whether the selector button should be disabled.
   * @returns {boolean}
   */
  _isSelectorDisabled() {
    return this._isSubmitting || (this._selectorConfig.disableWhenEmpty && this._items.length === 0);
  }

  /**
   * Gets the class applied to options for their current state.
   * @param {boolean} isDisabled Whether the option is disabled.
   * @param {boolean} isActive Whether the option is highlighted.
   * @returns {string}
   */
  _getOptionStatusClass(isDisabled, isActive) {
    if (isDisabled) {
      return "cursor-not-allowed bg-primary-50 text-primary-600 font-semibold opacity-100!";
    }
    if (isActive) {
      return "cursor-pointer text-stone-900 bg-stone-50";
    }
    return "cursor-pointer text-stone-900 hover:bg-stone-50";
  }

  render() {
    const selectedItem = this._findSelectedItem();
    const selector = this._renderSelector(selectedItem);

    return html`${this._selectorConfig.wrapperClass
      ? html`<div>
          <div class=${this._selectorConfig.wrapperClass}>${selector}</div>
        </div>`
      : selector}
    ${this._renderAfterSelector(selectedItem)}`;
  }

  /**
   * Renders the shared selector markup.
   * @param {object|null} selectedItem Selected item
   * @returns {import("lit").TemplateResult}
   */
  _renderSelector(selectedItem) {
    const isDisabled = this._isSelectorDisabled();
    const selectedLabel = selectedItem ? this._getItemLabel(selectedItem) : this._selectorConfig.defaultLabel;
    const disabledOpacityClass = this._selectorConfig.disabledOpacityClass || "opacity-80";

    return html`
      <div class="relative">
        <button
          id="${this._selectorConfig.selectorName}-selector-button"
          type="button"
          class="select select-primary relative text-left pe-9 ${isDisabled
            ? `${disabledOpacityClass} cursor-not-allowed`
            : "cursor-pointer"}"
          ?disabled=${isDisabled}
          aria-haspopup="listbox"
          aria-expanded=${this._combobox.isOpen ? "true" : "false"}
          @click=${() => this._combobox.toggle()}
        >
          <div class="flex flex-col justify-center min-h-10">
            <div class="text-xs/4 text-stone-900 line-clamp-2">${selectedLabel}</div>
          </div>
          <div class="absolute inset-y-0 end-0 flex items-center pe-3 pointer-events-none">
            <div class="svg-icon size-3 icon-caret-down bg-stone-600"></div>
          </div>
        </button>

        <div
          class="absolute top-14 left-0 right-0 z-10 bg-white rounded-lg shadow-sm border border-stone-200 ${this
            ._combobox.isOpen
            ? ""
            : "hidden"}"
        >
          <div class="p-3 border-b border-stone-200">
            <div class="relative">
              <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
                <div class="svg-icon size-4 icon-search bg-stone-300"></div>
              </div>
              <input
                id="${this._selectorConfig.selectorName}-search-input"
                type="search"
                class="input-primary w-full ps-9"
                placeholder=${this._selectorConfig.searchPlaceholder}
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                spellcheck="false"
                .value=${this._combobox.query}
                @input=${(event) => this._handleSearchInput(event)}
              />
            </div>
          </div>

          ${this._filteredItems.length > 0
            ? html`
                <ul
                  id="${this._selectorConfig.selectorName}-selector-list"
                  class="max-h-48 overflow-y-auto text-stone-700"
                  role="listbox"
                >
                  ${repeat(
                    this._filteredItems,
                    (item) => this._getItemId(item),
                    (item, index) => this._renderOption(item, index),
                  )}
                </ul>
              `
            : html`<div class="px-4 py-3 text-sm text-stone-500">${this._selectorConfig.emptyLabel}</div>`}
        </div>
      </div>
    `;
  }

  /**
   * Renders a single option inside the dropdown.
   * @param {object} item Item metadata
   * @param {number} index Item index
   * @returns {import("lit").TemplateResult}
   */
  _renderOption(item, index) {
    const itemId = this._getItemId(item);
    const isSelected = this._isSelected(item);
    const isActive = this._combobox.activeIndex === index;
    const isDisabled = isSelected || this._isSubmitting;

    return html`
      <li role="presentation" data-index=${index}>
        <button
          id="${this._selectorConfig.selectorName}-option-${itemId}"
          type="button"
          class="${this._selectorConfig
            .selectorName}-button w-full px-4 py-2 whitespace-normal min-h-10 flex flex-col justify-center text-left focus:outline-none ${this._getOptionStatusClass(
            isDisabled,
            isActive,
          )}"
          role="option"
          ?disabled=${isDisabled}
          @click=${(event) => this._handleConfiguredItemClick(event, item)}
          @mouseover=${() => this._combobox.setActiveIndex(index)}
        >
          <div class="text-xs/4 line-clamp-2">${this._getItemLabel(item)}</div>
        </button>
      </li>
    `;
  }
}
