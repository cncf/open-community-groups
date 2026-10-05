import { html } from "lit";
import { repeat } from "lit/directives/repeat.js";
import { DropdownPlacementController } from "/static/js/common/dropdown-placement.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/media/logo-image.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";
import { clearTimeoutId, replaceTimeout } from "/static/js/common/timers.js";

/** Basic email format check used when inviting users by email address. */
const emailAddressPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Minimum search query length, in Unicode code points after trimming. Mirrors
 * `USER_SEARCH_MIN_QUERY_CHARS` in `ocg-server/src/handlers/dashboard/common.rs`.
 */
const MIN_SEARCH_QUERY_LENGTH = 2;

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
   * @property {number} _searchRequestId - Internal id of the latest search request
   * @property {AbortController|null} _searchAbortController - Internal in-flight search controller
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
    this._searchRequestId = 0;
    this._searchAbortController = null;
    this._outsidePointerHandler = null;
    this._dropdownPlacement = new DropdownPlacementController(this, {
      getAnchor: () => this.querySelector("[data-user-search-input]"),
      getDropdown: () => this.querySelector("[data-user-search-dropdown]"),
    });
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
    this._cancelPendingSearch();
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
   * Invalidates the latest search request and aborts it when in flight.
   * @private
   */
  _cancelPendingSearch() {
    this._searchRequestId += 1;
    this._searchAbortController?.abort();
    this._searchAbortController = null;
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
    this._cancelPendingSearch();
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
    this._cancelPendingSearch();

    // Skip empty queries and queries too short to be selective
    if (query === "" || this._isQueryTooShort(query)) {
      this._searchResults = [];
      this._isSearching = false;
      return;
    }

    this._isSearching = true;
    const requestId = this._searchRequestId;
    this._searchTimeoutId = replaceTimeout(
      this._searchTimeoutId,
      () => {
        this._searchTimeoutId = 0;
        return this._performSearch(query, requestId);
      },
      this.searchDelay,
    );
  }

  /**
   * Checks whether a search request is still the latest one.
   * @param {number} requestId - Id of the request to check
   * @param {AbortController} controller - Controller of the request to check
   * @returns {boolean} True when the request results can be applied
   * @private
   */
  _isActiveSearch(requestId, controller) {
    return requestId === this._searchRequestId && this._searchAbortController === controller;
  }

  /**
   * Checks whether a query is shorter than the minimum search length.
   * @param {string} query - Trimmed search query
   * @returns {boolean} True when the query is too short to search
   * @private
   */
  _isQueryTooShort(query) {
    return Array.from(query).length < MIN_SEARCH_QUERY_LENGTH;
  }

  /**
   * Performs the search request to the dashboard API and updates results.
   * Results of superseded or aborted requests are ignored.
   * @param {string} query - The search query to send to the backend
   * @param {number} [requestId] - Id of the search request, defaults to the latest
   * @private
   */
  async _performSearch(query, requestId = this._searchRequestId) {
    if (this.disabled) return;
    this._searchAbortController?.abort();
    const controller = new AbortController();
    this._searchAbortController = controller;
    try {
      const response = await ocgFetch(
        `/dashboard/${this.dashboardType}/users/search?q=${encodeURIComponent(query)}`,
        { signal: controller.signal },
      );
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const users = await response.json();
      if (!this._isActiveSearch(requestId, controller)) return;
      const available = users.filter((u) => !this.excludeUsernames?.some((x) => x === u.username));
      this._searchResults = available;
    } catch (err) {
      if (err?.name === "AbortError" || !this._isActiveSearch(requestId, controller)) return;
      console.error("Error searching users:", err);
      this._searchResults = [];
    } finally {
      if (this._isActiveSearch(requestId, controller)) {
        this._isSearching = false;
        this._searchAbortController = null;
      }
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
   * Focus stays on the element the user pointed at; refocusing the input here
   * would scroll it into view mid-click and swallow the click elsewhere.
   * @param {Event} event - Pointer event
   * @private
   */
  _handleOutsidePointer(event) {
    if (this.disabled) return;
    if (this.contains(event.target)) return;
    if (this.persistQueryOnOutside) return;
    this._clearSearch({ refocus: false });
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
   * Renders the dropdown content for the current search state.
   * @returns {TemplateResult} Searching, email action, hint, empty or results template.
   * @private
   */
  _renderDropdownContent() {
    if (this._isSearching) {
      return html`
        <div class="p-4 text-center">
          <div class="inline-flex items-center gap-2 text-stone-600">
            <div class="animate-spin w-4 h-4 border-2 border-stone-300 border-t-stone-600 rounded-full"></div>
            Searching...
          </div>
        </div>
      `;
    }

    if (this._searchResults.length === 0 && this._hasEmailAction()) {
      return this._renderEmailAction();
    }

    // Short queries never search, so their results are always empty
    if (this._isQueryTooShort(this._searchQuery)) {
      return html`
        <div class="p-4 text-center text-stone-500">
          <p class="text-sm">Type at least ${MIN_SEARCH_QUERY_LENGTH} characters</p>
        </div>
      `;
    }

    if (this._searchResults.length === 0) {
      return html`
        <div class="p-4 text-center text-stone-500">
          <p class="text-sm">No ${this.label || "users"} found for "${this._searchQuery}"</p>
        </div>
      `;
    }

    return html`<div class="py-1">
      ${repeat(
        this._searchResults,
        (u) => u.username,
        (u) => this._renderResult(u),
      )}
    </div>`;
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
          class="input-primary peer ps-9 ${this.inputClass || ""} ${
            this.disabled ? "bg-stone-100 cursor-not-allowed" : ""
          }"
          placeholder=${
            this.placeholderText || (this.label ? `Search ${this.label} by username` : "Search by username")
          }
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
        ${
          this._searchQuery !== ""
            ? html`
                <div
                  data-user-search-dropdown
                  class="absolute left-0 right-0 top-10 mt-1 max-h-80 overflow-y-auto bg-white rounded-lg shadow-lg border border-stone-200 z-10"
                >
                  ${this._renderDropdownContent()}
                </div>
              `
            : ""
        }
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
