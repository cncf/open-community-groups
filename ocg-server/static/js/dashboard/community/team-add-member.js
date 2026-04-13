import { html } from "/static/vendor/js/lit-all.v3.3.2.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/user-search-field.js";
import "/static/js/common/logo-image.js";
import { computeUserInitials, lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";

/**
 * TeamAddMember component for inviting team members.
 *
 * Displays a compact "Add member" control. Clicking it opens a modal that
 * contains a search field to find users. Selecting a user shows a confirmation
 * badge and enables submission. Submits via HTMX to keep server flow and
 * auto-refresh the team table using the backend HX-Trigger.
 *
 * Uses light DOM (via LitWrapper) so Tailwind and HTMX selectors apply to the
 * elements rendered by the component.
 * @extends LitWrapper
 */
export class TeamAddMember extends LitWrapper {
  /**
   * Component properties definition
   * @property {string} dashboardType - Dashboard context ("community").
   * @property {boolean} _isOpen - Internal modal visibility state.
   * @property {Object|null} _selectedUser - Selected user object.
   */
  static properties = {
    dashboardType: { type: String, attribute: "dashboard-type" },
    canManageTeam: { type: Boolean, attribute: "can-manage-team", reflect: true },
    selectedUsers: { type: Array, attribute: false },
    roleOptions: { type: Array, attribute: false },
    disabledUserIds: { type: Array, attribute: false },
    _isOpen: { type: Boolean },
    _selectedRole: { type: String },
    _selectedUser: { type: Object },
  };

  constructor() {
    super();
    this.canManageTeam = true;
    this.dashboardType = "community";
    this.selectedUsers = [];
    this.roleOptions = [];
    this.disabledUserIds = [];
    this._isOpen = false;
    this._selectedRole = "";
    this._selectedUser = null;
  }

  connectedCallback() {
    // Add ESC key listener to close the modal
    super.connectedCallback();
    this._onKeydown = this._onKeydown.bind(this);
    document.addEventListener("keydown", this._onKeydown);

    // Parse selected-users attribute (JSON array of user objects)
    const selectedAttr = this.getAttribute("selected-users");
    if (selectedAttr && typeof selectedAttr === "string") {
      try {
        const parsed = JSON.parse(selectedAttr);
        if (Array.isArray(parsed)) {
          this.selectedUsers = parsed;
          this.disabledUserIds = parsed.map((u) => String(u.user_id));
        }
      } catch (_) {
        // ignore parsing errors
      }
    }

    // Parse role-options attribute (JSON array)
    const roleOptionsAttr = this.getAttribute("role-options");
    if (roleOptionsAttr && typeof roleOptionsAttr === "string") {
      try {
        const parsed = JSON.parse(roleOptionsAttr);
        if (Array.isArray(parsed)) {
          this.roleOptions = parsed.map((role) => ({
            label: role.display_name,
            value: role.community_role_id || role.group_role_id,
          }));
        }
      } catch (_) {
        // ignore parsing errors
      }
    }
  }

  disconnectedCallback() {
    // Clean up ESC key listener
    super.disconnectedCallback();
    if (this._isOpen) {
      unlockBodyScroll();
    }
    document.removeEventListener("keydown", this._onKeydown);
  }

  /**
   * Handles ESC key to close the modal.
   * @param {KeyboardEvent} e - Keyboard event
   * @private
   */
  _onKeydown(e) {
    if (e.key === "Escape" && this._isOpen) {
      this._close();
    }
  }

  /**
   * Opens the modal and focuses the search field after rendering.
   * @private
   */
  _open() {
    if (!this.canManageTeam) return;
    this._isOpen = true;
    lockBodyScroll();
    this.updateComplete.then(() => {
      const field = this.querySelector("user-search-field");
      if (field && typeof field.focusInput === "function") field.focusInput();
    });
  }

  /**
   * Closes the modal.
   * @private
   */
  _close() {
    this._isOpen = false;
    unlockBodyScroll();
  }

  /**
   * Receives selected user and updates hidden input + submit button state.
   * @param {CustomEvent} e - Event with detail.user
   * @private
   */
  _onUserSelected(e) {
    const user = e.detail?.user;
    if (!user) return;
    this._selectedUser = user;
    const userIdInput = this.querySelector("#team-add-user-id");
    const submitBtn = this.querySelector("#team-add-submit");
    if (userIdInput) userIdInput.value = user.user_id;
    if (submitBtn) submitBtn.disabled = !(this._selectedRole && this._selectedUser);
  }

  /**
   * Handles role selection changes and updates button state.
   * @param {Event} e - Change event
   * @private
   */
  _onRoleChanged(e) {
    this._selectedRole = e.target?.value || "";
    const submitBtn = this.querySelector("#team-add-submit");
    if (submitBtn) submitBtn.disabled = !(this._selectedRole && this._selectedUser);
  }

  /**
   * Processes HTMX for dynamically rendered form and binds the
   * htmx:afterRequest listener on open. Cleans up on close.
   * @param {Map} changed - Changed properties
   */
  updated(changed) {
    // When modal opens, process HTMX on the newly rendered form and bind events
    if (changed.has("_isOpen")) {
      const justOpened = this._isOpen === true;
      const form = this.querySelector("#team-add-form");

      if (justOpened && form) {
        if (window.htmx && typeof window.htmx.process === "function") {
          window.htmx.process(form);
        }

        // Rebind listener to avoid duplicates across opens
        if (this._afterRequestHandler) {
          form.removeEventListener("htmx:afterRequest", this._afterRequestHandler);
        }
        this._afterRequestHandler = (e) => {
          const xhr = e.detail?.xhr;
          const ok = handleHtmxResponse({
            xhr,
            successMessage: "Invitation sent to the selected user.",
            errorMessage: "Something went wrong adding this team member. Please try again later.",
          });
          if (ok) {
            this._close();
            this._resetSelection();
          }
        };
        form.addEventListener("htmx:afterRequest", this._afterRequestHandler);
      }

      // When closing, clean up listener if it exists
      if (!this._isOpen && form && this._afterRequestHandler) {
        form.removeEventListener("htmx:afterRequest", this._afterRequestHandler);
        this._afterRequestHandler = null;
      }
    }
  }

  /**
   * Clears the selection and disables submit.
   * @private
   */
  _resetSelection() {
    this._selectedUser = null;
    this._selectedRole = "";
    const userIdInput = this.querySelector("#team-add-user-id");
    const roleSelect = this.querySelector("#team-add-role");
    const submitBtn = this.querySelector("#team-add-submit");
    if (userIdInput) userIdInput.value = "";
    if (roleSelect) roleSelect.value = "";
    if (submitBtn) submitBtn.disabled = !(this._selectedRole && this._selectedUser);
  }

  /**
   * Renders the selected user badge next to actions.
   * @returns {TemplateResult} Badge template or empty when none selected
   * @private
   */
  _renderSelectedBadge() {
    const u = this._selectedUser;
    if (!u) return html``;
    const initials = computeUserInitials(u.name, u.username, 2);
    return html`
      <div class="inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-2 py-1">
        <logo-image
          image-url=${u.photo_url || ""}
          placeholder=${initials}
          size="size-[24px]"
          hide-border
        ></logo-image>
        <span class="text-sm text-stone-700">${u.name || u.username}</span>
      </div>
    `;
  }

  _renderModal() {
    if (!this._isOpen) return html``;
    return html`
      <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto overflow-x-hidden">
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[.35]"
          @click=${() => this._close()}
        ></div>
        <div class="modal-panel p-4 max-w-3xl">
          <div class="modal-card rounded-lg">
            <div class="flex items-center justify-between p-4 md:p-5 border-b border-stone-200 rounded-t">
              <h3 class="text-xl font-semibold text-stone-900">Add member</h3>
              <button
                type="button"
                class="group bg-transparent hover:bg-stone-200 rounded-full text-sm size-8 ms-auto inline-flex justify-center items-center cursor-pointer"
                @click=${() => this._close()}
              >
                <div class="svg-icon size-5 bg-stone-400 group-hover:bg-stone-700 icon-close"></div>
                <span class="sr-only">Close modal</span>
              </button>
            </div>
            <div class="modal-body p-4 md:p-8">
              <form
                id="team-add-form"
                hx-post="/dashboard/${this.dashboardType}/team/add"
                hx-target="#dashboard-content"
                hx-indicator="#dashboard-spinner"
                hx-disabled-elt="#team-add-submit"
              >
                <div class="mb-6">
                  <user-search-field
                    dashboard-type=${this.dashboardType}
                    label="team member"
                    legend="Search for users by their name or username"
                    .disabledUserIds=${this.disabledUserIds || []}
                    @user-selected=${(e) => this._onUserSelected(e)}
                  ></user-search-field>
                  <input type="hidden" name="user_id" id="team-add-user-id" />
                </div>
                <div class="mb-6">
                  <label for="team-add-role" class="form-label">Role</label>
                  <select
                    id="team-add-role"
                    name="role"
                    class="input-primary"
                    required
                    @change=${(e) => this._onRoleChanged(e)}
                  >
                    <option value="" selected disabled>Select a role</option>
                    ${this.roleOptions.map((o) => html`<option value=${o.value}>${o.label}</option>`)}
                  </select>
                </div>
                <div class="flex items-center justify-between gap-4">
                  <div>${this._renderSelectedBadge()}</div>
                  <button
                    id="team-add-submit"
                    type="submit"
                    class="btn-primary"
                    ?disabled=${!this._selectedUser || !this._selectedRole}
                  >
                    Add
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  render() {
    if (!this.canManageTeam) {
      return html`
        <div class="inline-flex items-center gap-3">
          <button class="btn-primary" disabled title="Your role cannot invite team members.">
            Add member
          </button>
        </div>
      `;
    }

    return html`
      <div class="inline-flex items-center gap-3">
        <button class="btn-primary" @click=${() => this._open()}>Add member</button>
      </div>
      ${this._renderModal()}
    `;
  }
}

customElements.define("team-add-member", TeamAddMember);
