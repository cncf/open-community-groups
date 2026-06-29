import { html, repeat } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { focusElementById, getElementById } from "/static/js/common/dom.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * TimezoneSelector renders a searchable dropdown for selecting timezones.
 *
 * @property {string} name Form field name (default: "timezone")
 * @property {string} value Currently selected timezone (IANA identifier)
 * @property {Array<string>} timezones List of available timezone strings
 * @property {boolean} required Whether selection is required
 * @property {boolean} disabled Whether component is disabled
 */
export class TimezoneSelector extends LitWrapper {
  static properties = {
    name: { type: String, attribute: "name" },
    value: { type: String, attribute: "value" },
    timezones: { type: Array, attribute: "timezones" },
    required: { type: Boolean, attribute: "required" },
    disabled: { type: Boolean, attribute: "disabled" },
  };

  constructor() {
    super();
    this.name = "timezone";
    this.value = "";
    this.timezones = [];
    this.required = false;
    this.disabled = false;
    this._combobox = new ComboboxController(this, {
      getItemCount: () => this._filteredTimezones.length,
      isInteractionBlocked: () => this.disabled,
      canOpen: () => this.timezones.length > 0,
      resetQueryOnToggle: true,
      onOpen: () => {
        this.updateComplete.then(() => {
          focusElementById(this, "timezone-search-input");
        });
      },
      onActiveIndexMove: () => this._scrollActiveIntoView(),
      onSelect: (index, event) => {
        const timezone = this._filteredTimezones[index];
        if (timezone && !this._isSelected(timezone)) {
          this._handleTimezoneClick(event, timezone);
        }
      },
    });
  }

  /**
   * Stores the current query and triggers filtering with simple debounce.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    this._combobox.setQuery(event.target.value || "");
    this._combobox.scheduleSearchUpdate(() => {
      this._combobox.setActiveIndex(null);
    }, 200);
  }

  /**
   * Gets filtered timezones based on current query.
   * @returns {Array<string>}
   */
  get _filteredTimezones() {
    const normalized = (this._combobox.query || "").trim().toLowerCase();
    if (!normalized) {
      return this.timezones;
    }
    return this.timezones.filter((tz) => {
      return (tz || "").toLowerCase().includes(normalized);
    });
  }

  /**
   * Handles clicks on a timezone option and closes the dropdown.
   * @param {MouseEvent} event Option click event
   * @param {string} timezone The timezone value
   */
  _handleTimezoneClick(event, timezone) {
    if (this._isSelected(timezone) || this.disabled) {
      event.preventDefault();
      return;
    }
    event.preventDefault();
    this.value = timezone;
    this._combobox.close();
    this.dispatchEvent(new Event("change", { bubbles: true }));
  }

  /**
   * Scrolls the active option into view within the list.
   */
  _scrollActiveIntoView() {
    this.updateComplete.then(() => {
      if (this._combobox.activeIndex === null) {
        return;
      }
      const list = getElementById(this, "timezone-selector-list");
      const activeItem = list?.querySelector(`[data-index="${this._combobox.activeIndex}"]`);
      if (activeItem && list) {
        activeItem.scrollIntoView({ block: "nearest" });
      }
    });
  }

  /**
   * Checks whether the provided timezone matches the selected value.
   * @param {string} timezone Timezone string
   * @returns {boolean}
   */
  _isSelected(timezone) {
    return timezone === this.value;
  }

  render() {
    const isDisabled = this.timezones.length === 0 || this.disabled;
    const displayValue = this.value || "Select a timezone";

    return html`
      <div class="relative">
        <input
          type="text"
          class="absolute top-0 left-0 opacity-0 p-0"
          name=${this.name}
          .value=${this.value || ""}
          ?required=${this.required}
        />

        <button
          id="timezone-selector-button"
          type="button"
          class="select select-primary relative text-left pe-9 w-full ${
            isDisabled ? "cursor-not-allowed bg-stone-100 text-stone-500" : "cursor-pointer"
          }"
          ?disabled=${isDisabled}
          aria-haspopup="listbox"
          aria-expanded=${this._combobox.isOpen ? "true" : "false"}
          @click=${() => this._combobox.toggle()}
        >
          <div class="flex items-center min-h-6">
            <span class="${this.value ? "text-stone-900" : "text-stone-500"}">${displayValue}</span>
          </div>
          <div class="absolute inset-y-0 end-0 flex items-center pe-3 pointer-events-none">
            <div class="svg-icon size-3 icon-caret-down bg-stone-600"></div>
          </div>
        </button>

        <div
          class="absolute top-full mt-1 left-0 right-0 z-10 bg-white rounded-lg shadow-sm border border-stone-200 ${
            this._combobox.isOpen ? "" : "hidden"
          }"
        >
          <div class="p-3 border-b border-stone-200">
            <div class="relative">
              <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
                <div class="svg-icon size-4 icon-search bg-stone-300"></div>
              </div>
              <input
                id="timezone-search-input"
                type="search"
                class="input-primary w-full ps-9"
                placeholder="Search or select timezone..."
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                spellcheck="false"
                .value=${this._combobox.query}
                @input=${(event) => this._handleSearchInput(event)}
              />
            </div>
          </div>

          ${
            this._filteredTimezones.length > 0
              ? html`
                  <ul
                    id="timezone-selector-list"
                    class="max-h-48 overflow-y-auto text-stone-700"
                    role="listbox"
                  >
                    ${repeat(
                      this._filteredTimezones,
                      (tz) => tz,
                      (timezone, index) => {
                        const isSelected = this._isSelected(timezone);
                        const isActive = this._combobox.activeIndex === index;
                        const isItemDisabled = isSelected || this.disabled;

                        let statusClass = "";
                        if (isItemDisabled) {
                          statusClass =
                            "cursor-not-allowed bg-primary-50 text-primary-600 font-semibold opacity-100!";
                        } else if (isActive) {
                          statusClass = "cursor-pointer text-stone-900 bg-stone-50";
                        } else {
                          statusClass = "cursor-pointer text-stone-900 hover:bg-stone-50";
                        }

                        return html`
                          <li role="presentation" data-index=${index}>
                            <button
                              id="timezone-option-${index}"
                              type="button"
                              class="w-full px-4 py-2 whitespace-normal min-h-10 flex items-center text-left focus:outline-none text-sm ${statusClass}"
                              role="option"
                              aria-selected=${isSelected ? "true" : "false"}
                              ?disabled=${isItemDisabled}
                              @click=${(event) => this._handleTimezoneClick(event, timezone)}
                              @mouseover=${() => this._combobox.setActiveIndex(index)}
                            >
                              ${timezone}
                            </button>
                          </li>
                        `;
                      },
                    )}
                  </ul>
                `
              : html`<div class="px-4 py-3 text-sm text-stone-500">No timezones found.</div>`
          }
        </div>
      </div>
    `;
  }
}

customElements.define("timezone-selector", TimezoneSelector);
