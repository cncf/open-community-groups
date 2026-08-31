import { html } from "lit";
import { repeat } from "lit/directives/repeat.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  renderContributorActions,
  renderContributorIdentity,
} from "/static/js/common/users/contributor-row.js";
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
   * @property {string} awardButtonId - Optional external bulk award button id
   * @property {boolean} _isModalOpen - Internal state for inline search visibility
   */
  static properties = {
    awardButtonId: { type: String, attribute: "award-button-id" },
    selectedUsers: { type: Array, attribute: "selected-users" },
    fieldName: { type: String, attribute: "field-name" },
    dashboardType: { type: String, attribute: "dashboard-type" },
    label: { type: String },
    legend: { type: String },
    maxUsers: { type: Number, attribute: "max-users" },
    searchDelay: { type: Number, attribute: "search-delay" },
    _isModalOpen: { type: Boolean },
    awardsDisabled: { type: Boolean, attribute: "awards-disabled" },
    canAwardBadges: { type: Boolean, attribute: "can-award-badges" },
    disabled: { type: Boolean },
    displayMode: { type: String, attribute: "display-mode" },
    eventId: { type: String, attribute: "event-id" },
    showAwardAll: { type: Boolean, attribute: "show-award-all" },
  };

  constructor() {
    super();
    this.awardButtonId = "";
    this.selectedUsers = [];
    this.fieldName = "";
    this.dashboardType = "group";
    this.label = "";
    this.legend = "";
    this.maxUsers = 0; // 0 means no limit
    this.searchDelay = 300;
    this._isModalOpen = true; // always visible inline
    this.awardsDisabled = false;
    this.canAwardBadges = false;
    this.disabled = false;
    this.displayMode = "chips";
    this.eventId = "";
    this.showAwardAll = false;
  }

  /**
   * Synchronizes the optional external bulk award button after relevant updates.
   * @param {Map<string, unknown>} changedProperties - Updated reactive properties
   */
  updated(changedProperties) {
    if (
      changedProperties.has("awardButtonId") ||
      changedProperties.has("awardsDisabled") ||
      changedProperties.has("canAwardBadges") ||
      changedProperties.has("eventId") ||
      changedProperties.has("selectedUsers")
    ) {
      this._syncExternalAwardButton();
    }
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
    this._emitUsersChanged();
  }

  /**
   * Removes a user from the selected users list.
   * @param {string} username - The username of the user to remove
   * @private
   */
  _removeUser(username) {
    if (this.disabled) return;
    this.selectedUsers = this.selectedUsers.filter((user) => user.username !== username);
    this._emitUsersChanged();
  }

  /** Emits the current host selection for contributor coordination. */
  _emitUsersChanged() {
    this.dispatchEvent(
      new CustomEvent("users-changed", {
        detail: { users: this.selectedUsers },
        bubbles: true,
        composed: true,
      }),
    );
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

  /** Renders the selected users as a simple editable table. */
  _renderUserTable() {
    return html`
      <div class="mt-4 overflow-visible">
        <table class="w-full text-left text-sm text-stone-600" aria-label="Event hosts">
          <thead class="border-b border-stone-200 bg-stone-100 text-xs uppercase text-stone-700">
            <tr>
              <th scope="col" class="px-4 py-3">Host</th>
              <th scope="col" class="w-[72px] px-4 py-3"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody>
            ${
              this.selectedUsers.length === 0
                ? html`<tr class="border-b border-stone-200 bg-white">
                    <td class="px-8 py-12 text-center text-stone-500" colspan="2">No hosts added yet.</td>
                  </tr>`
                : repeat(
                    this.selectedUsers,
                    (user) => user.user_id || user.username,
                    (user) => {
                      return html`
                        <tr class="border-b border-stone-200 odd:bg-white even:bg-stone-50/50">
                          <td class="px-4 py-3">${renderContributorIdentity(user)}</td>
                          <td class="px-4 py-3 text-right">
                            ${renderContributorActions({
                              actionLabel: "host",
                              awardsDisabled: this.awardsDisabled,
                              canAwardBadges: this.canAwardBadges,
                              contributor: user,
                              deleteDisabled: this.disabled,
                              eventId: this.eventId,
                              onDelete: () => this._removeUser(user.username),
                            })}
                          </td>
                        </tr>
                      `;
                    },
                  )
            }
          </tbody>
        </table>
      </div>
    `;
  }

  /** Synchronizes recipients and disabled state for an external award button. */
  _syncExternalAwardButton() {
    if (!this.awardButtonId) {
      return;
    }
    const awardButton = this.ownerDocument?.getElementById(this.awardButtonId);
    if (!awardButton) {
      return;
    }
    const userIds = this.selectedUsers.map((user) => user.user_id).filter(Boolean);
    const awardsUnavailable = !this.canAwardBadges || !this.eventId;
    awardButton.dataset.eventId = this.eventId;
    awardButton.dataset.userIds = userIds.join(",");
    awardButton.disabled = awardsUnavailable || this.awardsDisabled || userIds.length === 0;
    awardButton.title = this.awardsDisabled ? "Save contributor changes before awarding badges." : "";
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
    const userIds = this.selectedUsers.map((user) => user.user_id).filter(Boolean);
    return html`
      <div class="space-y-4">
        ${
          this.showAwardAll && this.canAwardBadges && this.eventId
            ? html`<div class="flex justify-end">
                <button
                  type="button"
                  class="btn-primary-outline"
                  data-badge-award-open
                  data-event-id=${this.eventId}
                  data-user-ids=${userIds.join(",")}
                  title=${this.awardsDisabled ? "Save contributor changes before awarding badges." : ""}
                  ?disabled=${this.awardsDisabled || userIds.length === 0}
                >
                  Award badge
                </button>
              </div>`
            : ""
        }
        <!-- Inline Search Panel (always visible) -->
        ${this._renderModal()}

        <!-- Selected Users -->
        ${
          this.displayMode === "table"
            ? this._renderUserTable()
            : this.selectedUsers.length > 0
              ? html`
                  <div class="flex flex-wrap gap-2">
                    ${repeat(
                      this.selectedUsers,
                      (user) => user.username,
                      (user) => this._renderSelectedUser(user),
                    )}
                  </div>
                `
              : ""
        }

        <!-- Hidden inputs for form submission -->
        ${
          this.fieldName
            ? this.selectedUsers.map(
                (user) => html` <input type="hidden" name="${this.fieldName}[]" value=${user.user_id} /> `,
              )
            : ""
        }
      </div>
    `;
  }
}

customElements.define("user-search-selector", UserSearchSelector);
