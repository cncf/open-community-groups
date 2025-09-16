import { html, repeat } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/avatar-image.js";
import { computeUserInitials } from "/static/js/common/common.js";

/**
 * UserSearchField component for searching and selecting users.
 *
 * Displays an inline search input with a floating dropdown that shows
 * matching users. When a user is selected, it emits a custom
 * `user-selected` event including the selected user object in the
 * event detail.
 *
 * This component focuses only on search UX (input + dropdown) and does not
 * manage chips, hidden inputs, modals or action buttons. Use it as a
 * building block from other components (like `user-search-selector`) or
 * pages that need custom composition.
 */
export class UserSearchField extends LitWrapper {
  /**
   * Component properties definition
   * @property {string} dashboardType - Dashboard context type ("group" or
   *   "community")
   * @property {string} label - Label text used in placeholders and messages
   * @property {string} legend - Helper text displayed under the input
   * @property {number} searchDelay - Debounce delay for search (milliseconds)
   * @property {Array} excludeUsernames - Usernames to filter out from results
   * @property {boolean} _isSearching - Internal loading indicator state
   * @property {Array} _searchResults - Internal search results collection
   * @property {string} _searchQuery - Internal current search query string
   * @property {number} _searchTimeoutId - Internal debounce timeout id
   */
  static properties = {
    // Public props
    dashboardType: { type: String, attribute: "dashboard-type" },
    label: { type: String },
    legend: { type: String },
    inputClass: { type: String, attribute: "input-class" },
    searchDelay: { type: Number, attribute: "search-delay" },
    disabledUserIds: { type: Array, attribute: false },
    excludeUsernames: { type: Array, attribute: false },
    wrapperClass: { type: String, attribute: "wrapper-class" },
    _isSearching: { type: Boolean },
    _searchResults: { type: Array },
    _searchQuery: { type: String },
    _searchTimeoutId: { type: Number },
  };

  constructor() {
    super();
    this.dashboardType = "group";
    this.label = "";
    this.legend = "";
    this.inputClass = "";
    this.searchDelay = 300;
    this.disabledUserIds = [];
    this.excludeUsernames = [];

    this._isSearching = false;
    this._searchResults = [];
    this._searchQuery = "";
    this._searchTimeoutId = 0;
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    if (this._searchTimeoutId) {
      clearTimeout(this._searchTimeoutId);
    }
  }

  /**
   * Programmatically focus the input element after the component is rendered.
   */
  focusInput() {
    this.updateComplete.then(() => {
      const input = this.renderRoot?.querySelector?.("#search-input");
      if (input) input.focus();
    });
  }

  /**
   * Clears the current query and results and restores the focus to the input.
   * @private
   */
  _clearSearch() {
    this._searchQuery = "";
    this._searchResults = [];
    this._isSearching = false;
    if (this._searchTimeoutId) {
      clearTimeout(this._searchTimeoutId);
    }
    this.focusInput();
  }

  /**
   * Handles input changes applying debounce and triggering the search.
   * @param {Event} event - Input event from the search field
   * @private
   */
  _handleSearchInput(event) {
    const query = event.target.value.trim();
    this._searchQuery = query;

    if (this._searchTimeoutId) clearTimeout(this._searchTimeoutId);

    if (query === "") {
      this._searchResults = [];
      this._isSearching = false;
      return;
    }

    this._isSearching = true;
    this._searchTimeoutId = setTimeout(() => {
      this._performSearch(query);
    }, this.searchDelay);
  }

  /**
   * Performs the search request to the dashboard API and updates results.
   * @param {string} query - The search query to send to the backend
   * @private
   */
  async _performSearch(query) {
    try {
      const response = await fetch(
        `/dashboard/${this.dashboardType}/users/search?q=${encodeURIComponent(query)}`,
      );
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const users = await response.json();
      const available = users.filter((u) => !this.excludeUsernames?.some((x) => x === u.username));
      this._searchResults = available;
    } catch (err) {
      console.error("Error searching users:", err);
      this._searchResults = [];
    } finally {
      this._isSearching = false;
    }
  }

  /**
   * Emits the selection event with the selected user and resets the field.
   * @param {Object} user - Selected user object as returned by the API
   * @private
   */
  _selectUser(user) {
    // Emit event for parent components / forms to handle the selection.
    // The detail contains the whole user object as returned by the API.
    this.dispatchEvent(
      new CustomEvent("user-selected", {
        detail: { user },
        bubbles: true,
      }),
    );
    // Reset input after selection
    this._clearSearch();
  }

  /**
   * Checks whether a user should be disabled (non-selectable).
   * @param {Object} user - User object to check
   * @returns {boolean} True if disabled
   * @private
   */
  _isDisabled(user) {
    const ids = this.disabledUserIds || [];
    try {
      return ids.some((id) => String(id) === String(user.user_id));
    } catch (_) {
      return false;
    }
  }

  /**
   * Renders a single result item in the dropdown list.
   * @param {Object} user - User object to render
   * @returns {TemplateResult} The result row template
   * @private
   */
  _renderResult(user) {
    const initials = computeUserInitials(user.name, user.username, 2);
    const disabled = this._isDisabled(user);
    const rowClass = `flex items-center gap-3 px-4 py-2 ${
      disabled ? "opacity-50 cursor-not-allowed bg-stone-50" : "hover:bg-stone-50 cursor-pointer"
    }`;
    return html`
      <div
        class="${rowClass}"
        aria-disabled="${disabled ? "true" : "false"}"
        @click="${() => {
          if (!disabled) this._selectUser(user);
        }}"
      >
        <avatar-image image-url="${user.photo_url || ""}" placeholder="${initials}"></avatar-image>
        <div class="flex-1 min-w-0">
          <h3 class="text-sm font-medium text-stone-900 truncate">${user.name || user.username}</h3>
          ${user.name ? html`<p class="text-xs text-stone-600 truncate">@${user.username}</p>` : ""}
        </div>
      </div>
    `;
  }

  /**
   * Renders the full component (input, legend and dropdown results).
   * @returns {TemplateResult} Component template
   */
  render() {
    return html`
      <div class="relative ${this.wrapperClass || ""}">
        <!-- Left search icon -->
        <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
          <div class="svg-icon size-4 icon-search bg-stone-300"></div>
        </div>

        <input
          id="search-input"
          type="text"
          class="input-primary peer ps-9 ${this.inputClass || ""}"
          placeholder="Search ${this.label || ""} by username"
          .value="${this._searchQuery}"
          @input="${this._handleSearchInput}"
          autocomplete="off"
          autocorrect="off"
          autocapitalize="off"
          spellcheck="false"
        />

        <!-- Clear button -->
        <div class="absolute end-1.5 top-1.5 peer-placeholder-shown:hidden">
          <button type="button" class="cursor-pointer mt-[2px]" @click="${this._clearSearch}">
            <div class="svg-icon size-5 bg-stone-400 hover:bg-stone-700 icon-close"></div>
          </button>
        </div>

        ${this.legend ? html`<p class="form-legend mt-2">${this.legend}</p>` : ""}

        <!-- Dropdown results -->
        ${this._searchQuery !== ""
          ? html`
              <div
                class="absolute left-0 right-0 top-10 mt-1 bg-white rounded-lg shadow-lg border border-stone-200 z-10 ${this
                  ._isSearching || this._searchResults.length === 0
                  ? ""
                  : "max-h-80 overflow-y-auto"}"
              >
                ${this._isSearching
                  ? html`
                      <div class="p-4 text-center">
                        <div class="inline-flex items-center gap-2 text-stone-600">
                          <div
                            class="animate-spin w-4 h-4 border-2 border-stone-300 border-t-stone-600 rounded-full"
                          ></div>
                          Searching...
                        </div>
                      </div>
                    `
                  : this._searchResults.length === 0
                  ? html`
                      <div class="p-4 text-center text-stone-500">
                        <p class="text-sm">No ${this.label || "users"} found for "${this._searchQuery}"</p>
                      </div>
                    `
                  : html`<div class="py-1">
                      ${repeat(
                        this._searchResults,
                        (u) => u.username,
                        (u) => this._renderResult(u),
                      )}
                    </div>`}
              </div>
            `
          : ""}
      </div>
    `;
  }
}

customElements.define("user-search-field", UserSearchField);
