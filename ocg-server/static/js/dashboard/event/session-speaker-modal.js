import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/user-search-field.js";
import "/static/js/common/avatar-image.js";
import {
  computeUserInitials,
  lockBodyScroll,
  unlockBodyScroll,
} from "/static/js/common/common.js";

/**
 * Modal component for selecting session speakers with featured flag support.
 * Emits a "speaker-selected" event containing the chosen user and featured state.
 * @extends LitWrapper
 */
export class SessionSpeakerModal extends LitWrapper {
  /**
   * Component properties definition.
   * @property {string} dashboardType - Dashboard context type ("group" or similar)
   * @property {Array} disabledUserIds - User IDs that should be disabled in the search
   * @property {boolean} _isOpen - Internal modal visibility state
   * @property {Object|null} _selectedUser - Currently selected user object
   * @property {boolean} _featured - Featured speaker toggle state
   */
  static properties = {
    dashboardType: { type: String, attribute: "dashboard-type" },
    disabledUserIds: { type: Array, attribute: false },
    _isOpen: { type: Boolean },
    _selectedUser: { type: Object },
    _featured: { type: Boolean },
  };

  constructor() {
    super();
    this.dashboardType = "group";
    this.disabledUserIds = [];
    this._isOpen = false;
    this._selectedUser = null;
    this._featured = false;
  }

  connectedCallback() {
    super.connectedCallback();
    this._onKeydown = this._onKeydown.bind(this);
    document.addEventListener("keydown", this._onKeydown);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    if (this._isOpen) {
      unlockBodyScroll();
    }
    document.removeEventListener("keydown", this._onKeydown);
  }

  open() {
    this._resetState();
    this._isOpen = true;
    lockBodyScroll();
    this.updateComplete.then(() => {
      const field = this.querySelector("user-search-field");
      if (field && typeof field.focusInput === "function") field.focusInput();
    });
  }

  close() {
    this._isOpen = false;
    unlockBodyScroll();
    this._resetState();
  }

  _resetState() {
    this._selectedUser = null;
    this._featured = false;
  }

  _onKeydown(event) {
    if (event.key === "Escape" && this._isOpen) {
      this.close();
    }
  }

  _handleUserSelected(event) {
    const user = event.detail?.user;
    if (!user) return;
    this._selectedUser = user;
  }

  _toggleFeatured(event) {
    this._featured = !!event.target?.checked;
  }

  _confirmSelection() {
    if (!this._selectedUser) return;
    this.dispatchEvent(
      new CustomEvent("speaker-selected", {
        detail: {
          user: this._selectedUser,
          featured: this._featured,
        },
        bubbles: true,
      }),
    );
    this.close();
  }

  _renderSelectedBadge() {
    const user = this._selectedUser;
    if (!user) return html``;
    const initials = computeUserInitials(user.name, user.username, 2);
    return html`
      <div class="inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-2 py-1">
        <avatar-image
          image-url="${user.photo_url || ""}"
          placeholder="${initials}"
          size="size-[24px]"
          hide-border
        ></avatar-image>
        ${this._featured ? html`<div class="svg-icon size-3 icon-star bg-amber-500"></div>` : ""}
        <span class="text-sm text-stone-700">${user.name || user.username}</span>
      </div>
    `;
  }

  _renderModal() {
    if (!this._isOpen) return html``;

    return html`
      <div
        class="fixed top-0 right-0 left-0 z-50 justify-center items-center w-full h-full flex overflow-visible"
      >
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[.35]"
          @click="${() => this.close()}"
        ></div>
        <div class="relative px-4 py-8 w-full max-w-2xl overflow-visible">
          <div class="relative bg-white rounded-lg shadow overflow-visible">
            <div class="flex items-center justify-between p-4 md:p-5 border-b border-stone-200 rounded-t">
              <h3 class="text-xl font-semibold text-stone-900">Add speaker</h3>
              <button
                type="button"
                class="group bg-transparent hover:bg-stone-200 rounded-full text-sm size-8 ms-auto inline-flex justify-center items-center cursor-pointer"
                @click="${() => this.close()}"
              >
                <div class="svg-icon size-5 bg-stone-400 group-hover:bg-stone-700 icon-close"></div>
                <span class="sr-only">Close modal</span>
              </button>
            </div>
            <div class="p-4 md:p-8 space-y-6">
              <div>
                <user-search-field
                  dashboard-type="${this.dashboardType}"
                  label="speaker"
                  legend="Search by name or username to add a speaker to this session."
                  .disabledUserIds="${this.disabledUserIds || []}"
                  @user-selected="${(event) => this._handleUserSelected(event)}"
                ></user-search-field>
              </div>

              <div class="flex items-center justify-between gap-4 flex-wrap">
                <div>${this._renderSelectedBadge()}</div>
                <label class="inline-flex items-center cursor-pointer ms-auto">
                  <input
                    type="checkbox"
                    class="sr-only peer"
                    ?disabled=${!this._selectedUser}
                    .checked=${this._featured}
                    @change="${(event) => this._toggleFeatured(event)}"
                  />
                  <div
                    class="relative w-11 h-6 bg-stone-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-0.5 after:start-0.5 after:bg-white after:border after:border-stone-200 after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-500"
                  ></div>
                  <span class="ms-3 text-sm font-medium text-stone-900">Featured speaker</span>
                </label>
              </div>

              <div class="flex justify-end gap-3">
                <button type="button" class="btn-secondary" @click="${() => this.close()}">Cancel</button>
                <button
                  type="button"
                  class="btn-primary"
                  ?disabled=${!this._selectedUser}
                  @click="${() => this._confirmSelection()}"
                >
                  Add speaker
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  render() {
    return html`${this._renderModal()}`;
  }
}

customElements.define("session-speaker-modal", SessionSpeakerModal);
