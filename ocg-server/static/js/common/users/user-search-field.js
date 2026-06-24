import { html, repeat } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/media/logo-image.js";
import { computeUserInitials } from "/static/js/common/common.js";
import { clearTimeoutId, replaceTimeout } from "/static/js/common/timers.js";

/** Basic email format check used when inviting users by email address. */
const emailAddressPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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
   * @property {string} inputId - Input ID used by external labels
   * @property {string} placeholderText - Custom placeholder for search input
   * @property {boolean} emailActionEnabled - Show an email action for valid email queries
   * @property {string} emailActionText - Supporting text for the email action row
   * @property {boolean} persistQueryOnOutside - Keep the query when focus leaves
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
    inputId: { type: String, attribute: "input-id" },
    placeholderText: { type: String, attribute: "placeholder-text" },
    emailActionEnabled: { type: Boolean, attribute: "email-action-enabled" },
    emailActionText: { type: String, attribute: "email-action-text" },
    searchDelay: { type: Number, attribute: "search-delay" },
    disabledUserIds: { type: Array, attribute: false },
    excludeUsernames: { type: Array, attribute: false },
    wrapperClass: { type: String, attribute: "wrapper-class" },
    disabled: { type: Boolean },
    persistQueryOnOutside: { type: Boolean, attribute: "persist-query-on-outside" },
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
    this.inputId = "search-input";
    this.placeholderText = "";
    this.emailActionEnabled = false;
    this.emailActionText = "Invite by email";
    this.searchDelay = 400;
    this.disabledUserIds = [];
    this.excludeUsernames = [];
    this.disabled = false;
    this.persistQueryOnOutside = false;

    this._isSearching = false;
    this._searchResults = [];
    this._searchQuery = "";
    this._searchTimeoutId = 0;
    this._outsidePointerHandler = null;
  }

  connectedCallback() {
    super.connectedCallback();
    if (!this._outsidePointerHandler) {
      this._outsidePointerHandler = (event) => this._handleOutsidePointer(event);
    }
    document.addEventListener("pointerdown", this._outsidePointerHandler);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);
    if (this._outsidePointerHandler) {
      document.removeEventListener("pointerdown", this._outsidePointerHandler);
    }
  }

  /**
   * Programmatically focus the input element after the component is rendered.
   */
  focusInput() {
    if (this.disabled) return;
    this.updateComplete.then(() => {
      const input = this.renderRoot?.querySelector?.("[data-user-search-input]");
      if (input) input.focus();
    });
  }

  /**
   * Clears the current query and results and restores the focus to the input.
   * @param {Object} [options] Clear behavior options.
   * @param {boolean} [options.emitChange=true] Whether to emit the query event.
   * @param {boolean} [options.refocus=true] Whether to focus the input.
   * @returns {void}
   */
  clearSearch({ emitChange = true, refocus = true } = {}) {
    this._clearSearch({ emitChange, refocus });
  }

  /**
   * Emits the current search query for parent forms that derive values from it.
   * @param {string} query - Current search query.
   * @private
   */
  _emitSearchQueryChanged(query) {
    this.dispatchEvent(
      new CustomEvent("user-search-query-changed", {
        detail: { query },
        bubbles: true,
      }),
    );
  }

  /**
   * Checks whether the current query can be shown as an email action.
   * @returns {boolean} True when the email action row should be rendered.
   * @private
   */
  _hasEmailAction() {
    return this.emailActionEnabled && emailAddressPattern.test(this._searchQuery);
  }

  /**
   * Emits the email action event for parent components that need it.
   * @private
   */
  _selectEmailAction() {
    if (!this._hasEmailAction()) return;
    const email = this._searchQuery;
    this._emitSearchQueryChanged(email);
    this.dispatchEvent(
      new CustomEvent("email-action-selected", {
        detail: { email },
        bubbles: true,
      }),
    );
    this._clearSearch({ emitChange: false, refocus: false });
  }

  /**
   * Clears the current query and results and restores the focus to the input.
   * @param {Object} [options] Clear behavior options.
   * @param {boolean} [options.emitChange=true] Whether to emit the query event.
   * @param {boolean} [options.refocus=true] Whether to focus the input.
   * @private
   */
  _clearSearch({ emitChange = true, refocus = true } = {}) {
    if (this.disabled) return;
    this._searchQuery = "";
    this._searchResults = [];
    this._isSearching = false;
    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);
    if (emitChange) {
      this._emitSearchQueryChanged("");
    }
    if (refocus) {
      this.focusInput();
    }
  }

  /**
   * Handles input changes applying debounce and triggering the search.
   * @param {Event} event - Input event from the search field
   * @private
   */
  _handleSearchInput(event) {
    if (this.disabled) return;
    const query = event.target.value.trim();
    this._searchQuery = query;
    this._emitSearchQueryChanged(query);

    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);

    if (query === "") {
      this._searchResults = [];
      this._isSearching = false;
      return;
    }

    this._isSearching = true;
    this._searchTimeoutId = replaceTimeout(
      this._searchTimeoutId,
      () => {
        this._searchTimeoutId = 0;
        this._performSearch(query);
      },
      this.searchDelay,
    );
  }

  /**
   * Performs the search request to the dashboard API and updates results.
   * @param {string} query - The search query to send to the backend
   * @private
   */
  async _performSearch(query) {
    if (this.disabled) return;
    try {
      const response = await ocgFetch(
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
    if (this.disabled) return;
    // Emit event for parent components / forms to handle the selection.
    // The detail contains the whole user object as returned by the API.
    this.dispatchEvent(
      new CustomEvent("user-selected", {
        detail: { user },
        bubbles: true,
      }),
    );
    // Reset input after selection.
    this._clearSearch({ emitChange: false });
  }

  /**
   * Hides dropdown when clicking outside of the component.
   * @param {Event} event - Pointer event
   * @private
   */
  _handleOutsidePointer(event) {
    if (this.disabled) return;
    if (this.contains(event.target)) return;
    if (this.persistQueryOnOutside) return;
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
        class=${rowClass}
        aria-disabled=${disabled ? "true" : "false"}
        @click=${() => {
          if (!disabled) this._selectUser(user);
        }}
      >
        <logo-image image-url=${user.photo_url || ""} placeholder=${initials}></logo-image>
        <div class="flex-1 min-w-0">
          <h3 class="text-sm font-medium text-stone-900 truncate">${user.name || user.username}</h3>
          ${user.name ? html`<p class="text-xs text-stone-600 truncate">@${user.username}</p>` : ""}
        </div>
      </div>
    `;
  }

  /**
   * Renders the valid-email action row.
   * @returns {TemplateResult} Email action row template.
   * @private
   */
  _renderEmailAction() {
    return html`
      <button
        type="button"
        class="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-stone-50"
        aria-label=${`${this.emailActionText} ${this._searchQuery}`}
        @click=${() => this._selectEmailAction()}
      >
        <div class="svg-icon size-4 bg-stone-500 icon-email shrink-0"></div>
        <span class="flex-1 min-w-0 text-sm">
          <span class="font-medium text-stone-900">${this._searchQuery}</span>
          <span class="text-stone-600">${this.emailActionText}</span>
        </span>
        <div class="svg-icon size-5 bg-stone-500 icon-add-circle shrink-0" aria-hidden="true"></div>
      </button>
    `;
  }

  /**
   * Renders the full component (input, legend and dropdown results).
   * @returns {TemplateResult} Component template
   */
  render() {
    const hasEmailAction = this._hasEmailAction();

    return html`
      <div class="relative ${this.wrapperClass || ""}">
        <!-- Left search icon -->
        <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
          <div class="svg-icon size-4 icon-search bg-stone-300"></div>
        </div>

        <input
          id=${this.inputId}
          data-user-search-input
          type="text"
          class="input-primary peer ps-9 ${this.inputClass || ""} ${this.disabled
            ? "bg-stone-100 cursor-not-allowed"
            : ""}"
          placeholder=${this.placeholderText ||
          (this.label ? `Search ${this.label} by username` : "Search by username")}
          .value=${this._searchQuery}
          @input=${this._handleSearchInput}
          autocomplete="off"
          autocorrect="off"
          autocapitalize="off"
          spellcheck="false"
          ?disabled=${this.disabled}
        />

        <!-- Clear button -->
        <div class="absolute end-1.5 top-1.5 peer-placeholder-shown:hidden">
          <button
            type="button"
            class="cursor-pointer mt-0.5"
            @click=${() => this._clearSearch()}
            ?disabled=${this.disabled}
          >
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
                  : this._searchResults.length === 0 && hasEmailAction
                    ? this._renderEmailAction()
                    : this._searchResults.length === 0
                      ? html`
                          <div class="p-4 text-center text-stone-500">
                            <p class="text-sm">
                              No ${this.label || "users"} found for "${this._searchQuery}"
                            </p>
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

/**
 * Focuses the first user search field inside a root element.
 * @param {Document|Element} root Query root.
 * @returns {Element|null} Focused user search field when present.
 */
export const focusUserSearchField = (root) => {
  const field = root?.querySelector?.("user-search-field") || null;
  if (typeof field?.focusInput === "function") {
    field.focusInput();
  }
  return field;
};

customElements.define("user-search-field", UserSearchField);
