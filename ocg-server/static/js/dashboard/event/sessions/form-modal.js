import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  bindModalDismissListeners,
  closeModalBodyScroll,
  openModalBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import "/static/js/dashboard/event/sessions/item.js";
import { createEmptySession } from "/static/js/dashboard/event/sessions/schedule.js";

/**
 * Modal for adding/editing sessions.
 * @extends LitWrapper
 */
class SessionFormModal extends LitWrapper {
  /**
   * Component properties definition.
   * @property {Array} sessionKinds - Available session kinds.
   * @property {Array} approvedSubmissions - Approved CFS submissions.
   * @property {Array} usedSubmissionIds - Submission ids used by other sessions.
   * @property {Object} meetingMaxParticipants - Limits per meeting provider.
   * @property {boolean} meetingsEnabled - Whether meetings can be configured.
   * @property {number} descriptionMaxLength - Max session description length.
   * @property {number} sessionNameMaxLength - Max session title length.
   * @property {number} locationMaxLength - Max session location length.
   * @property {boolean} disabled - Whether editing controls are disabled.
   * @property {boolean} _isOpen - Whether the modal is visible.
   * @property {?Object} _session - Session being edited.
   * @property {string} _prefilledDate - Date used to pre-fill time fields.
   * @property {boolean} _isNewSession - Whether current session is new.
   */
  static properties = {
    sessionKinds: { type: Array },
    approvedSubmissions: { type: Array },
    usedSubmissionIds: { type: Array },
    meetingMaxParticipants: { type: Object },
    meetingsEnabled: { type: Boolean },
    descriptionMaxLength: { type: Number },
    sessionNameMaxLength: { type: Number },
    locationMaxLength: { type: Number },
    disabled: { type: Boolean },
    _isOpen: { type: Boolean },
    _session: { type: Object },
    _prefilledDate: { type: String },
    _isNewSession: { type: Boolean },
  };

  constructor() {
    super();
    this.sessionKinds = [];
    this.approvedSubmissions = [];
    this.usedSubmissionIds = [];
    this.meetingMaxParticipants = {};
    this.meetingsEnabled = false;
    this.descriptionMaxLength = undefined;
    this.sessionNameMaxLength = undefined;
    this.locationMaxLength = undefined;
    this.disabled = false;
    this._isOpen = false;
    this._session = null;
    this._prefilledDate = "";
    this._isNewSession = false;
    this._handleKeydown = this._handleKeydown.bind(this);
    this._onDataChange = this._onDataChange.bind(this);
    this._removeDismissListeners = null;
  }

  connectedCallback() {
    super.connectedCallback();
    this._removeDismissListeners = bindModalDismissListeners({ onKeydown: this._handleKeydown });
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._isOpen = closeModalBodyScroll(this._isOpen);
    this._removeDismissListeners?.();
    this._removeDismissListeners = null;
  }

  /**
   * Opens the modal for adding or editing a session.
   * @param {Object|null} session - Session to edit, or null for new session
   * @param {string} prefilledDate - Date to pre-fill for the session
   */
  open(session = null, prefilledDate = "") {
    this._isNewSession = !session;
    this._session = session ? { ...session } : createEmptySession(Date.now());
    this._prefilledDate = prefilledDate;
    this._isOpen = openModalBodyScroll(this._isOpen);
  }

  /**
   * Closes the modal.
   */
  close() {
    if (!this._isOpen) return;
    const wasOpen = this._isOpen;
    this._isOpen = false;
    this._session = null;
    this._prefilledDate = "";
    this._isOpen = closeModalBodyScroll(wasOpen);
  }

  /**
   * Handles Escape key to close modal.
   * @param {KeyboardEvent} event
   * @private
   */
  _handleKeydown(event) {
    if (isEscapeEvent(event) && this._isOpen) {
      this.close();
    }
  }

  /**
   * Handles session data changes from SessionItem.
   * @param {Object} data - Updated session data
   * @private
   */
  _onDataChange(data) {
    this._session = data;
  }

  /**
   * Saves the session and closes the modal.
   * @private
   */
  _onSave() {
    const sessionItem = this.querySelector("session-item");
    const invalidField = sessionItem
      ? Array.from(sessionItem.querySelectorAll("input, select, textarea")).find(
          (field) => typeof field.checkValidity === "function" && !field.checkValidity(),
        )
      : null;

    if (invalidField && typeof invalidField.reportValidity === "function") {
      invalidField.reportValidity();
      return;
    }

    if (!this._session?.name || !this._session?.starts_at) {
      return;
    }

    if (sessionItem) {
      const onlineEventDetails = sessionItem.querySelector("online-event-details");
      if (onlineEventDetails && typeof onlineEventDetails.getMeetingData === "function") {
        this._session = {
          ...this._session,
          ...onlineEventDetails.getMeetingData(),
        };
      }
    }

    this.dispatchEvent(
      new CustomEvent("session-saved", {
        detail: {
          session: this._session,
          isNew: this._isNewSession,
        },
        bubbles: true,
        composed: true,
      }),
    );
    this.close();
  }

  render() {
    if (!this._isOpen || !this._session) {
      return html``;
    }

    const modalTitle = this._isNewSession ? "Add session" : "Edit session";
    const currentUsedIds = this._isNewSession
      ? this.usedSubmissionIds
      : this.usedSubmissionIds.filter((id) => id !== this._session.cfs_submission_id);

    return html`
      <div
        class="fixed inset-0 flex items-center justify-center overflow-y-auto overflow-x-hidden z-[1000]"
        role="dialog"
        aria-modal="true"
        aria-labelledby="session-form-modal-title"
        data-pending-changes-ignore
      >
        <div class="absolute inset-0 bg-stone-950 opacity-35" @click=${() => this.close()}></div>
        <div class="modal-panel p-4 max-w-6xl">
          <div class="modal-card rounded-2xl">
            <div class="flex items-center justify-between p-5 border-b border-stone-200 shrink-0">
              <h3 id="session-form-modal-title" class="text-xl font-semibold text-stone-900">
                ${modalTitle}
              </h3>
              <button
                type="button"
                class="group text-stone-400 bg-transparent hover:bg-stone-100 transition-colors rounded-lg text-sm w-8 h-8 inline-flex justify-center items-center"
                @click=${() => this.close()}
              >
                <div
                  class="svg-icon w-4 h-4 bg-stone-400 group-hover:bg-stone-600 transition-colors icon-close"
                ></div>
                <span class="sr-only">Close modal</span>
              </button>
            </div>

            <div class="modal-body p-6 flex-1">
              <session-item
                .data=${this._session}
                .index=${0}
                .sessionKinds=${this.sessionKinds}
                .approvedSubmissions=${this.approvedSubmissions}
                .usedSubmissionIds=${currentUsedIds}
                .meetingMaxParticipants=${this.meetingMaxParticipants}
                .meetingsEnabled=${this.meetingsEnabled}
                .descriptionMaxLength=${this.descriptionMaxLength}
                .sessionNameMaxLength=${this.sessionNameMaxLength}
                .locationMaxLength=${this.locationMaxLength}
                .onDataChange=${this._onDataChange}
                .disabled=${this.disabled}
                .prefilledDate=${this._prefilledDate}
              ></session-item>
            </div>

            <div class="flex items-center justify-end gap-3 p-5 border-t border-stone-200 shrink-0">
              <button type="button" class="btn-secondary" @click=${() => this.close()}>Cancel</button>
              <button type="button" class="btn-primary" @click=${() => this._onSave()}>
                ${this._isNewSession ? "Add session" : "Save changes"}
              </button>
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

customElements.define("session-form-modal", SessionFormModal);
