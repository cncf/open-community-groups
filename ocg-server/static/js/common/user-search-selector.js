import { html, repeat } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { computeUserInitials } from "/static/js/dashboard/common.js";
import "/static/js/common/avatar-image.js";
import "/static/js/common/user-search-field.js";

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
  }

  /**
   * Opens the search modal.
   * @private
   */
  _openModal() {
    this._isModalOpen = true;

    // Focus search input after render
    this.updateComplete.then(() => {
      const field = this.querySelector("user-search-field");
      if (field && typeof field.focusInput === "function") field.focusInput();
    });
  }

  /**
   * Closes the search modal.
   * @private
   */
  _closeModal() {
    this._isModalOpen = false;
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

  // Search logic moved to <user-search-field>

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
   * Renders avatar component for a user.
   * @param {Object} user - User object with photo_url and name/username
   * @param {boolean} small - Whether to render a small avatar for badges
   * @returns {TemplateResult} Avatar component template
   * @private
   */
  _renderAvatar(user, small = false) {
    const initials = computeUserInitials(user.name, user.username, 2);
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

  _handleUserSelected(e) {
    const user = e.detail?.user;
    if (!user) return;
    this._addUser(user);
  }

  // Rendering of search results handled in <user-search-field>

  /**
   * Renders the search modal.
   * @returns {TemplateResult} Modal template
   * @private
   */
  _renderModal() {
    if (!this._isModalOpen) return html``;

    return html`
      <div
        class="modal ${this._isModalOpen
          ? ""
          : "opacity-0 pointer-events-none"} fixed w-full h-full top-0 left-0 flex items-center justify-center z-1000"
      >
        <!-- Modal overlay -->
        <div
          class="modal-overlay absolute w-full h-full bg-black opacity-75"
          @click="${this._handleOverlayClick}"
        ></div>
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
              <h2 class="text-lg font-semibold text-stone-900 pr-10">Search ${this.label || "users"}</h2>
              <!-- Search Field -->
              <div class="mt-4">
                <user-search-field
                  .excludeUsernames="${this.selectedUsers.map((u) => u.username)}"
                  dashboard-type="${this.dashboardType}"
                  label="${this.label || "user"}"
                  legend="${this.legend || ""}"
                  @user-selected="${(e) => this._handleUserSelected(e)}"
                ></user-search-field>
              </div>
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
