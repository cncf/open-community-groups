import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
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
    _isOpen: { state: true },
    _query: { state: true },
    _activeIndex: { state: true },
  };

  constructor() {
    super();
    this.name = "timezone";
    this.value = "";
    this.timezones = [];
    this.required = false;
    this.disabled = false;
    this._isOpen = false;
    this._query = "";
    this._activeIndex = null;
    this._searchTimeoutId = 0;
    this._documentClickHandler = null;
  }

  connectedCallback() {
    super.connectedCallback();
    this.addEventListener("keydown", this._handleKeydown.bind(this));
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._removeDocumentListener();
    if (this._searchTimeoutId) {
      window.clearTimeout(this._searchTimeoutId);
    }
  }

  /**
   * Stores the current query and triggers filtering with simple debounce.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    const value = event.target.value || "";
    this._query = value;
    if (this._searchTimeoutId) {
      window.clearTimeout(this._searchTimeoutId);
    }
    this._searchTimeoutId = window.setTimeout(() => {
      this._activeIndex = null;
      this.requestUpdate();
    }, 200);
  }

  /**
   * Gets filtered timezones based on current query.
   * @returns {Array<string>}
   */
  get _filteredTimezones() {
    const normalized = (this._query || "").trim().toLowerCase();
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
    this._closeDropdown();
    this.dispatchEvent(new Event("change", { bubbles: true }));
  }

  /**
   * Toggles dropdown visibility.
   */
  _toggleDropdown() {
    if (this.disabled) {
      return;
    }
    if (this._isOpen) {
      this._closeDropdown();
    } else {
      this._openDropdown();
    }
  }

  /**
   * Opens the dropdown and resets search.
   */
  _openDropdown() {
    if (this.timezones.length === 0 || this.disabled) {
      return;
    }
    this._isOpen = true;
    this._query = "";
    this._activeIndex = null;
    this._addDocumentListener();
    this.updateComplete.then(() => {
      const input = this.querySelector("#timezone-search-input");
      if (input) {
        input.focus();
      }
    });
  }

  /**
   * Closes the dropdown and clears search state.
   */
  _closeDropdown() {
    this._isOpen = false;
    this._query = "";
    this._activeIndex = null;
    this._removeDocumentListener();
  }

  /**
   * Registers a click listener on document to detect outside clicks.
   */
  _addDocumentListener() {
    if (this._documentClickHandler) {
      return;
    }
    this._documentClickHandler = (event) => {
      if (!this.contains(event.target)) {
        this._closeDropdown();
      }
    };
    document.addEventListener("click", this._documentClickHandler);
  }

  /**
   * Removes the outside click listener if it exists.
   */
  _removeDocumentListener() {
    if (!this._documentClickHandler) {
      return;
    }
    document.removeEventListener("click", this._documentClickHandler);
    this._documentClickHandler = null;
  }

  /**
   * Handles keyboard navigation and shortcuts.
   * @param {KeyboardEvent} event Native keyboard event
   */
  _handleKeydown(event) {
    if (event.defaultPrevented || this.disabled) {
      return;
    }

    const filteredTimezones = this._filteredTimezones;
    if (!this._isOpen || filteredTimezones.length === 0) {
      if (this._isOpen && event.key === "Escape") {
        event.preventDefault();
        this._closeDropdown();
      }
      return;
    }

    const moveActiveIndex = (delta) => {
      if (this._activeIndex === null) {
        this._activeIndex = 0;
      } else {
        this._activeIndex = (this._activeIndex + delta + filteredTimezones.length) % filteredTimezones.length;
      }
      this._scrollActiveIntoView();
    };

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        moveActiveIndex(1);
        break;
      case "ArrowUp":
        event.preventDefault();
        moveActiveIndex(-1);
        break;
      case "Enter":
        event.preventDefault();
        if (this._activeIndex !== null) {
          const timezone = filteredTimezones[this._activeIndex];
          if (timezone && !this._isSelected(timezone)) {
            this._handleTimezoneClick(event, timezone);
          }
        }
        break;
      case "Escape":
        event.preventDefault();
        this._closeDropdown();
        break;
      default:
        break;
    }
  }

  /**
   * Scrolls the active option into view within the list.
   */
  _scrollActiveIntoView() {
    this.updateComplete.then(() => {
      if (this._activeIndex === null) {
        return;
      }
      const list = this.querySelector("#timezone-selector-list");
      const activeItem = list?.querySelector(`[data-index="${this._activeIndex}"]`);
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
          class="select select-primary relative text-left pe-9 w-full ${isDisabled
            ? "cursor-not-allowed bg-stone-100 text-stone-500"
            : "cursor-pointer"}"
          ?disabled=${isDisabled}
          aria-haspopup="listbox"
          aria-expanded=${this._isOpen ? "true" : "false"}
          @click=${() => this._toggleDropdown()}
        >
          <div class="flex items-center min-h-6">
            <span class="${this.value ? "text-stone-900" : "text-stone-500"}">${displayValue}</span>
          </div>
          <div class="absolute inset-y-0 end-0 flex items-center pe-3 pointer-events-none">
            <div class="svg-icon size-3 icon-caret-down bg-stone-600"></div>
          </div>
        </button>

        <div
          class="absolute top-full mt-1 left-0 right-0 z-10 bg-white rounded-lg shadow-sm border border-stone-200 ${this
            ._isOpen
            ? ""
            : "hidden"}"
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
                .value=${this._query}
                @input=${(event) => this._handleSearchInput(event)}
              />
            </div>
          </div>

          ${this._filteredTimezones.length > 0
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
                      const isActive = this._activeIndex === index;
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
                            @mouseover=${() => (this._activeIndex = index)}
                          >
                            ${timezone}
                          </button>
                        </li>
                      `;
                    },
                  )}
                </ul>
              `
            : html`<div class="px-4 py-3 text-sm text-stone-500">No timezones found.</div>`}
        </div>
      </div>
    `;
  }
}

customElements.define("timezone-selector", TimezoneSelector);
