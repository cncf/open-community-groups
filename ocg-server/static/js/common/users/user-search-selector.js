import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/users/selected-user-pill.js";
import { focusUserSearchField } from "/static/js/common/users/user-search-field.js";

/**
 * UserSearchSelector component for searching and selecting users.
 * Displays an inline search panel and shows selected users with avatars.
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
   * @property {boolean} _isModalOpen - Internal state for inline search visibility
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
    disabled: { type: Boolean },
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
    this._isModalOpen = true; // always visible inline
    this.disabled = false;
  }

  /**
   * Opens the inline search panel.
   * @private
   */
  _openModal() {
    if (this.disabled) return;
    this._isModalOpen = true;

    // Focus search input after render
    this.updateComplete.then(() => {
      focusUserSearchField(this);
    });
  }

  /**
   * Closes the inline search panel.
   * @private
   */
  _closeModal() {
    this._isModalOpen = false;
  }

  /**
   * Adds a user to the selected users list.
   * @param {Object} user - The user object to add
   * @private
   */
  _addUser(user) {
    if (this.disabled) return;
    if (this.maxUsers > 0 && this.selectedUsers.length >= this.maxUsers) {
      return;
    }

    this.selectedUsers = [...this.selectedUsers, user];
  }

  /**
   * Removes a user from the selected users list.
   * @param {string} username - The username of the user to remove
   * @private
   */
  _removeUser(username) {
    if (this.disabled) return;
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
   * Renders a selected user item.
   * @param {Object} user - User object to render
   * @returns {TemplateResult} Selected user item template
   * @private
   */
  _renderSelectedUser(user) {
    return html`
      <selected-user-pill
        .user=${user}
        remove-label="Remove user"
        @remove=${() => this._removeUser(user.username)}
        ?disabled=${this.disabled}
      ></selected-user-pill>
    `;
  }

  _handleUserSelected(event) {
    if (this.disabled) return;
    const user = event.detail?.user;
    if (!user) return;
    this._addUser(user);
  }

  /**
   * Renders the inline search panel (keeps method name for minimal changes).
   * @returns {TemplateResult} Inline panel template
   * @private
   */
  _renderModal() {
    return html`
      <div class="mb-3">
        <user-search-field
          .excludeUsernames=${this.selectedUsers.map((u) => u.username)}
          dashboard-type=${this.dashboardType}
          label=${this.label || "user"}
          legend=${this.legend || ""}
          input-class="input-primary"
          wrapper-class="w-full xl:w-1/2"
          @user-selected=${(event) => this._handleUserSelected(event)}
          ?disabled=${this.disabled}
        ></user-search-field>
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
        <!-- Inline Search Panel (always visible) -->
        ${this._renderModal()}

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

        <!-- Hidden inputs for form submission -->
        ${this.fieldName
          ? this.selectedUsers.map(
              (user) => html` <input type="hidden" name="${this.fieldName}[]" value=${user.user_id} /> `,
            )
          : ""}
      </div>
    `;
  }
}

customElements.define("user-search-selector", UserSearchSelector);
