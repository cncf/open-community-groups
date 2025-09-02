import { html, repeat } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/avatar-image.js";

/**
 * UserSearchSelector component for searching and selecting users.
 * Displays a modal with search functionality and shows selected users with avatars.
 * Generates hidden form inputs with username values for form submission.
 * @extends LitWrapper
 */
export class UserSearchSelector extends LitWrapper {
  /**
   * Component properties definition
   * @property {Array} selectedUsers - Array of selected user objects
   * @property {string} fieldName - Name attribute for the hidden form inputs and button label
   * @property {string} dashboardType - Dashboard context type ("group" or "community")
   * @property {string} label - Label text for the placeholder in search input
   * @property {number} maxUsers - Maximum number of users allowed (0 = unlimited)
   * @property {number} searchDelay - Debounce delay for search in milliseconds
   * @property {boolean} _isModalOpen - Internal state for modal visibility
   * @property {Array} _searchResults - Internal state for search results
   * @property {boolean} _isSearching - Internal state for loading indicator
   * @property {string} _searchQuery - Internal state for current search query
   * @property {number} _searchTimeoutId - Internal state for debounce timeout ID
   */
  static properties = {
    selectedUsers: { type: Array, attribute: "selected-users" },
    fieldName: { type: String, attribute: "field-name" },
    dashboardType: { type: String, attribute: "dashboard-type" },
    label: { type: String },
    legend: { type: String },
    maxUsers: { type: Number, attribute: "max-users" },
    searchDelay: { type: Number, attribute: "search-delay" },
    _isModalOpen: { type: Boolean },
    _searchResults: { type: Array },
    _isSearching: { type: Boolean },
    _searchQuery: { type: String },
    _searchTimeoutId: { type: Number },
  };

  constructor() {
    super();
    this.selectedUsers = [];
    this.fieldName = "";
    this.dashboardType = "group";
    this.label = "";
    this.legend = "";
    this.maxUsers = 0; // 0 means no limit
    this.searchDelay = 300;
    this._isModalOpen = false;
    this._searchResults = [];
    this._isSearching = false;
    this._searchQuery = "";
    this._searchTimeoutId = 0;
  }

  /**
   * Lifecycle callback when component is added to DOM.
   * Adds keyboard event listeners for modal.
   */
  connectedCallback() {
    super.connectedCallback();
    this._handleKeydown = this._handleKeydown.bind(this);
    document.addEventListener("keydown", this._handleKeydown);
  }

  /**
   * Lifecycle callback when component is removed from DOM.
   * Removes keyboard event listeners.
   */
  disconnectedCallback() {
    super.disconnectedCallback();
    document.removeEventListener("keydown", this._handleKeydown);
    if (this._searchTimeoutId) {
      clearTimeout(this._searchTimeoutId);
    }
  }

  /**
   * Opens the search modal.
   * @private
   */
  _openModal() {
    this._isModalOpen = true;
    this._searchQuery = "";
    this._searchResults = [];
    this._isSearching = false;

    // Focus search input after render
    this.updateComplete.then(() => {
      const searchInput = this.querySelector("#search-input");
      if (searchInput) {
        searchInput.focus();
      }
    });
  }

  /**
   * Closes the search modal.
   * @private
   */
  _closeModal() {
    this._isModalOpen = false;
    this._searchQuery = "";
    this._searchResults = [];
    this._isSearching = false;
    if (this._searchTimeoutId) {
      clearTimeout(this._searchTimeoutId);
    }
  }

  /**
   * Handles keyboard events, specifically ESC key to close modal.
   * @param {KeyboardEvent} event - The keyboard event
   * @private
   */
  _handleKeydown(event) {
    if (event.key === "Escape" && this._isModalOpen) {
      this._closeModal();
    }
  }

  /**
   * Handles click on modal overlay to close modal.
   * @param {Event} event - The click event
   * @private
   */
  _handleOverlayClick(event) {
    if (event.target === event.currentTarget) {
      this._closeModal();
    }
  }

  /**
   * Clears the search input and results.
   * @private
   */
  _clearSearch() {
    this._searchQuery = "";
    this._searchResults = [];
    this._isSearching = false;

    // Clear the timeout if one is active
    if (this._searchTimeoutId) {
      clearTimeout(this._searchTimeoutId);
    }

    // Focus back to search input after clearing
    this.updateComplete.then(() => {
      const searchInput = this.querySelector("#search-input");
      if (searchInput) {
        searchInput.focus();
      }
    });
  }

  /**
   * Handles search input changes with debouncing.
   * @param {Event} event - The input event
   * @private
   */
  _handleSearchInput(event) {
    const query = event.target.value.trim();
    this._searchQuery = query;

    // Clear previous timeout
    if (this._searchTimeoutId) {
      clearTimeout(this._searchTimeoutId);
    }

    // Clear results if query is empty
    if (query === "") {
      this._searchResults = [];
      this._isSearching = false;
      return;
    }

    // Set searching state immediately
    this._isSearching = true;

    // Debounce the search
    this._searchTimeoutId = setTimeout(() => {
      this._performSearch(query);
    }, this.searchDelay);
  }

  /**
   * Performs the actual search by calling the API.
   * @param {string} query - The search query
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
      console.log("Search results:", users);

      // Filter out already selected users
      const availableUsers = users.filter(
        (user) => !this.selectedUsers.some((selected) => selected.username === user.username),
      );

      this._searchResults = availableUsers;
    } catch (error) {
      console.error("Error searching users:", error);
      this._searchResults = [];
    } finally {
      this._isSearching = false;
    }
  }

  /**
   * Adds a user to the selected users list.
   * @param {Object} user - The user object to add
   * @private
   */
  _addUser(user) {
    if (this.maxUsers > 0 && this.selectedUsers.length >= this.maxUsers) {
      return;
    }

    this.selectedUsers = [...this.selectedUsers, user];

    // Remove user from search results
    this._searchResults = this._searchResults.filter((u) => u.username !== user.username);

    // Close modal after adding user
    this._closeModal();
  }

  /**
   * Removes a user from the selected users list.
   * @param {string} username - The username of the user to remove
   * @private
   */
  _removeUser(username) {
    this.selectedUsers = this.selectedUsers.filter((user) => user.username !== username);
  }

  /**
   * Determines if the add button should be disabled.
   * @returns {boolean} True if add button should be disabled
   * @private
   */
  _isAddButtonDisabled() {
    return this.maxUsers > 0 && this.selectedUsers.length >= this.maxUsers;
  }

  /**
   * Generates initials from a user's name.
   * @param {Object} user - The user object
   * @returns {string} User initials or username first letter
   * @private
   */
  _getUserInitials(user) {
    if (user.name) {
      const nameParts = user.name.trim().split(/\s+/);
      const firstName = nameParts[0] || "";
      const lastName = nameParts.length > 1 ? nameParts[nameParts.length - 1] : "";

      const firstInitial = firstName.charAt(0).toUpperCase();
      const lastInitial = lastName.charAt(0).toUpperCase();

      if (firstInitial && lastInitial) {
        return `${firstInitial}${lastInitial}`;
      } else if (firstInitial) {
        return firstInitial;
      }
    }

    // Fall back to username first letter
    return user.username.charAt(0).toUpperCase();
  }

  /**
   * Renders avatar component for a user.
   * @param {Object} user - User object with photo_url and name/username
   * @param {boolean} small - Whether to render a small avatar for badges
   * @returns {TemplateResult} Avatar component template
   * @private
   */
  _renderAvatar(user, small = false) {
    const initials = this._getUserInitials(user);
    if (small) {
      return html`
        <avatar-image
          image-url="${user.photo_url || ""}"
          placeholder="${initials}"
          size="size-[24px]"
          hide-border="true"
        >
        </avatar-image>
      `;
    }
    return html`
      <avatar-image image-url="${user.photo_url || ""}" placeholder="${initials}"></avatar-image>
    `;
  }

  /**
   * Renders a selected user item.
   * @param {Object} user - User object to render
   * @returns {TemplateResult} Selected user item template
   * @private
   */
  _renderSelectedUser(user) {
    return html`
      <div class="inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-1 py-1">
        ${this._renderAvatar(user, true)}
        <span class="text-sm text-stone-700 pe-2"> ${user.name || user.username} </span>
        <button
          type="button"
          class="p-1 hover:bg-stone-200 rounded-full transition-colors"
          title="Remove user"
          @click="${() => this._removeUser(user.username)}"
        >
          <div class="svg-icon size-3 icon-close bg-stone-600"></div>
        </button>
      </div>
    `;
  }

  /**
   * Renders a search result item.
   * @param {Object} user - User object to render
   * @returns {TemplateResult} Search result item template
   * @private
   */
  _renderSearchResult(user) {
    return html`
      <div
        class="flex items-center gap-3 px-4 py-2 hover:bg-stone-50 cursor-pointer"
        @click="${() => this._addUser(user)}"
      >
        ${this._renderAvatar(user)}
        <div class="flex-1 min-w-0">
          <h3 class="text-sm font-medium text-stone-900 truncate">${user.name || user.username}</h3>
          ${user.name ? html` <p class="text-xs text-stone-600 truncate">@${user.username}</p> ` : ""}
        </div>
      </div>
    `;
  }

  /**
   * Renders the search modal.
   * @returns {TemplateResult} Modal template
   * @private
   */
  _renderModal() {
    if (!this._isModalOpen) return html``;

    return html`
      <div
        class="modal ${this._isModalOpen ? "" : "opacity-0 pointer-events-none"} fixed w-full h-full top-0 left-0 flex items-center justify-center z-1000"
      >
        <!-- Modal overlay -->
        <div class="modal-overlay absolute w-full h-full bg-black opacity-75" @click="${this._handleOverlayClick}"></div>
        <!-- End modal overlay -->

        <div class="modal-container fixed z-50 max-w-md w-full mx-4">
          <div class="modal-content bg-white rounded-lg shadow-xl max-h-[80vh] flex flex-col">
            <!-- Modal Header -->
            <div class="p-6 relative">
              <button
                type="button"
                class="absolute top-4 right-4 p-2 rounded-full hover:bg-stone-300/30"
                @click="${this._closeModal}"
              >
                <div class="svg-icon size-6 icon-close bg-stone-600"></div>
              </button>
              <h2 class="text-lg font-semibold text-stone-900 pr-10">
                Search ${this.label || "users"}
              </h2>

            <!-- Search Input -->
            <div class="mt-4 relative">
              <input
                id="search-input"
                type="text"
                class="peer w-full rounded-full border border-stone-200 text-stone-900 placeholder-stone-400 focus:ring-transparent focus:border-stone-400 focus:ring block flex-1 min-w-0 text-md p-2.5 ps-4 pe-14"
                placeholder="Search ${this.label || ""} by username"
                value="${this._searchQuery}"
                @input="${this._handleSearchInput}"
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                spellcheck="false"
              />

              <!-- Clear button (shows when input has value) -->
              <div class="absolute right-[40px] top-[10px] ${this._searchQuery ? "block" : "hidden"}">
                <button
                  type="button"
                  class="mr-2 mt-[2px]"
                  @click="${this._clearSearch}"
                >
                  <div class="svg-icon h-5 w-5 bg-stone-400 hover:bg-stone-700 transition-colors icon-close"></div>
                </button>
              </div>

              <!-- Search icon button -->
              <div class="absolute right-[6px] top-[5px]">
                <div class="btn-secondary group p-1.5 h-[30px] w-[30px] mt-[3px] mr-[3px] pointer-events-none">
                  <div class="svg-icon h-4 w-4 mx-auto bg-primary-500 icon-magnifying-glass"></div>
                </div>
              </div>

              ${this.legend ? html` <p class="form-legend mt-2">${this.legend}</p> ` : ""}
            </div>
          </div>


              <!-- Floating dropdown for results -->
              ${
                this._searchQuery !== ""
                  ? html`
                      <div
                        class="absolute left-0 right-0 top-full mt-1 bg-white rounded-lg shadow-lg border border-stone-200 z-10 ${this
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
                                  <p class="text-sm">
                                    No ${this.fieldName || "users"} found for "${this._searchQuery}"
                                  </p>
                                </div>
                              `
                            : html`
                                <div class="py-1">
                                  ${repeat(
                                    this._searchResults,
                                    (user) => user.username,
                                    (user) => this._renderSearchResult(user),
                                  )}
                                </div>
                              `}
                      </div>
                    `
                  : ""
              }
            </div>
          </div>

          <!-- Welcome/instruction text -->
          <div class="p-6 text-center text-stone-500">
            <div class="svg-icon size-8 icon-search bg-stone-300 mx-auto mb-2"></div>
            <p>Start typing to search for ${this.label || "users"}</p>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  /**
   * Main render method for the component.
   * @returns {TemplateResult} Complete component template
   */
  render() {
    return html`
      <div class="space-y-4">
        <!-- Selected Users -->
        ${this.selectedUsers.length > 0
          ? html`
              <div class="flex flex-wrap gap-2">
                ${repeat(
                  this.selectedUsers,
                  (user) => user.username,
                  (user) => this._renderSelectedUser(user),
                )}
              </div>
            `
          : ""}

        <!-- Add Button -->
        <button
          type="button"
          class="btn-primary-outline btn-mini"
          @click="${this._openModal}"
          ?disabled="${this._isAddButtonDisabled()}"
        >
          Add ${this.label || "user"}
        </button>

        <!-- Hidden inputs for form submission -->
        ${this.fieldName
          ? this.selectedUsers.map(
              (user) => html` <input type="hidden" name="${this.fieldName}[]" value="${user.user_id}" /> `,
            )
          : ""}

        <!-- Search Modal -->
        ${this._renderModal()}
      </div>
    `;
  }
}

customElements.define("user-search-selector", UserSearchSelector);
