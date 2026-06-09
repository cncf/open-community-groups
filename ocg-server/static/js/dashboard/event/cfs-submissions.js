import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { renderCfsDecisionPanel } from "/static/js/dashboard/event/cfs-submissions-decision.js";
import {
  renderCfsDetailsPanel,
  renderCfsPersonRow,
} from "/static/js/dashboard/event/cfs-submissions-details.js";
import { renderCfsRatingsPanel } from "/static/js/dashboard/event/cfs-submissions-ratings.js";
import {
  renderCfsPendingChangesAlert,
  renderCfsReviewTabsNavigation,
} from "/static/js/dashboard/event/cfs-submissions-shell.js";
import { getElementById } from "/static/js/common/dom.js";
import {
  bindModalDismissListeners,
  closeModalBodyScroll,
  openModalBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import {
  buildApprovedSubmissionEventDetail,
  buildReviewModalOpenState,
  buildReviewFormStateSnapshot,
  findCurrentUserRating,
  getReviewModalClosedState,
  getReviewModalDefaultProperties,
  getReviewModalDefaultState,
  handleReviewAfterRequest,
  isKnownReviewTab,
  isLinkedToSession,
  isStatusAllowed,
  normalizeLabels,
  parseReviewAttributeList,
} from "/static/js/dashboard/event/cfs-submissions-review-utils.js";
import "/static/js/common/cfs-label-selector.js";
import "/static/js/common/media/logo-image.js";

const APPROVED_SUBMISSIONS_EVENT = "event-approved-submissions-updated";
const SUBMISSIONS_FILTER_ID = "submissions-label-filter";
const REVIEW_TABS = {
  DETAILS: "details",
  DECISION: "decision",
  RATINGS: "ratings",
};
const MODAL_STATE_KEYS = {
  activeTab: "_activeTab",
  hoverRatingStars: "_hoverRatingStars",
  initialFormSnapshot: "_initialFormSnapshot",
  isOpen: "_isOpen",
  message: "_message",
  ratingComment: "_ratingComment",
  ratingStars: "_ratingStars",
  selectedLabelIds: "_selectedLabelIds",
  statusId: "_statusId",
  submission: "_submission",
};

/**
 * ReviewSubmissionModal renders and handles the CFS submission review modal.
 * @extends LitWrapper
 */
export class ReviewSubmissionModal extends LitWrapper {
  /**
   * Lit reactive properties.
   * @returns {Object}
   */
  static get properties() {
    return {
      currentUserId: { type: String, attribute: "current-user-id" },
      eventId: { type: String, attribute: "event-id" },
      labels: { type: Array, attribute: false },
      messageMaxLength: { type: Number, attribute: "message-max-length" },
      statuses: { type: Array, attribute: false },
      _hoverRatingStars: { type: Number },
      _isOpen: { type: Boolean },
      _message: { type: String },
      _ratingComment: { type: String },
      _ratingStars: { type: Number },
      _activeTab: { type: String },
      _selectedLabelIds: { type: Array },
      _statusId: { type: String },
      _submission: { type: Object },
    };
  }

  constructor() {
    super();
    Object.assign(this, getReviewModalDefaultProperties());
    this._applyModalState(getReviewModalDefaultState());
    this._activeTab = REVIEW_TABS.DETAILS;
    this._afterRequestHandler = null;
    this._onKeydown = this._onKeydown.bind(this);
    this._removeDismissListeners = null;
  }

  connectedCallback() {
    super.connectedCallback();
    this._loadLabelsFromAttribute();
    this._loadStatusesFromAttribute();
    this._removeDismissListeners = bindModalDismissListeners({ onKeydown: this._onKeydown });
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._isOpen = closeModalBodyScroll(this._isOpen);
    this._removeAfterRequestListener();
    this._removeDismissListeners?.();
    this._removeDismissListeners = null;
  }

  /**
   * Opens the modal and loads submission data.
   * @param {Object} submission
   */
  open(submission) {
    if (!submission) {
      return;
    }
    const currentUserRating = findCurrentUserRating(submission, this.currentUserId);
    const openState = buildReviewModalOpenState(submission, currentUserRating);
    this.syncLabelsFromFilter();
    this._submission = submission;
    this._hoverRatingStars = 0;
    this._message = openState.message;
    this._ratingComment = openState.ratingComment;
    this._ratingStars = openState.ratingStars;
    this._activeTab = REVIEW_TABS.DETAILS;
    this._selectedLabelIds = openState.selectedLabelIds;
    this._statusId = openState.statusId;
    this._initialFormSnapshot = this._buildFormStateSnapshot();
    this._isOpen = openModalBodyScroll(this._isOpen);
  }

  /**
   * Closes the modal and resets current submission state.
   */
  close() {
    if (!this._isOpen) {
      return;
    }
    const wasOpen = this._isOpen;
    this._removeAfterRequestListener();
    this._applyModalState(getReviewModalClosedState(REVIEW_TABS.DETAILS));
    this._isOpen = closeModalBodyScroll(wasOpen);
  }

  /**
   * Applies normalized modal state.
   * @param {Object} state Modal state patch.
   */
  _applyModalState(state) {
    Object.entries(MODAL_STATE_KEYS).forEach(([stateKey, propertyKey]) => {
      if (Object.prototype.hasOwnProperty.call(state, stateKey)) {
        this[propertyKey] = state[stateKey];
      }
    });
  }

  /**
   * Handles updates when modal state changes.
   * @param {Map} changedProperties
   */
  updated(changedProperties) {
    if (!this._isOpen) {
      return;
    }
    if (changedProperties.has("_isOpen") || changedProperties.has("_submission")) {
      this._bindFormAfterRequest();
      const form = getElementById(this, "cfs-submission-form");
      if (form && window.htmx && typeof window.htmx.process === "function") {
        window.htmx.process(form);
      }
    }
  }

  /**
   * Handles Escape key to close modal.
   * @param {KeyboardEvent} event
   */
  _onKeydown(event) {
    if (isEscapeEvent(event) && this._isOpen) {
      this.close();
    }
  }

  /**
   * Loads statuses from the statuses attribute.
   */
  _loadStatusesFromAttribute() {
    const parsedStatuses = parseReviewAttributeList(this, "statuses", this.statuses);
    if (parsedStatuses) {
      this.statuses = parsedStatuses;
    }
  }

  /**
   * Loads available labels from the labels attribute.
   */
  _loadLabelsFromAttribute() {
    const parsedLabels = parseReviewAttributeList(this, "labels", this.labels);
    if (parsedLabels) {
      this.labels = parsedLabels;
    }
  }

  /**
   * Synchronizes labels from the submissions filter component.
   */
  syncLabelsFromFilter() {
    const labelsFilter = getElementById(document, SUBMISSIONS_FILTER_ID);
    if (!labelsFilter) {
      return;
    }

    if (Array.isArray(labelsFilter.labels)) {
      this.labels = normalizeLabels(labelsFilter.labels);
      return;
    }

    const labelsAttr = labelsFilter.getAttribute("labels");
    if (!labelsAttr) {
      this.labels = [];
      return;
    }

    this.labels = normalizeLabels(parseReviewAttributeList(labelsFilter, "labels", []) || []);
  }

  /**
   * Builds the update endpoint for the current submission.
   * @returns {string}
   */
  _buildSubmissionEndpoint() {
    const submissionId = this._submission?.cfs_submission_id;
    if (!this.eventId || !submissionId) {
      return "";
    }
    return `/dashboard/group/events/${this.eventId}/submissions/${submissionId}`;
  }

  /**
   * Binds htmx:afterRequest to the modal form.
   */
  _bindFormAfterRequest() {
    const form = getElementById(this, "cfs-submission-form");
    if (!form) {
      return;
    }
    this._removeAfterRequestListener();
    this._afterRequestHandler = (event) => {
      handleReviewAfterRequest({
        event,
        handleResponse: handleHtmxResponse,
        onSuccess: () => {
          this._emitApprovedSubmissionsUpdate();
          this.close();
        },
      });
    };
    form.addEventListener("htmx:afterRequest", this._afterRequestHandler);
  }

  /**
   * Emits approved submissions updates for sessions synchronization.
   */
  _emitApprovedSubmissionsUpdate() {
    if (!this.isConnected) {
      return;
    }

    const submission = this._submission;
    if (!submission?.cfs_submission_id) {
      return;
    }

    this.dispatchEvent(
      new CustomEvent(APPROVED_SUBMISSIONS_EVENT, {
        bubbles: true,
        composed: true,
        detail: buildApprovedSubmissionEventDetail(submission, this._statusId),
      }),
    );
  }

  /**
   * Removes htmx:afterRequest listener from the modal form.
   */
  _removeAfterRequestListener() {
    const form = getElementById(this, "cfs-submission-form");
    if (!form || !this._afterRequestHandler) {
      this._afterRequestHandler = null;
      return;
    }
    form.removeEventListener("htmx:afterRequest", this._afterRequestHandler);
    this._afterRequestHandler = null;
  }

  /**
   * Handles message input changes.
   * @param {Event} event
   */
  _onMessageInput(event) {
    this._message = event.target?.value || "";
  }

  /**
   * Handles status selection changes.
   * @param {Event} event
   */
  _onStatusChange(event) {
    this._statusId = String(event.target?.value || "");
  }

  /**
   * Handles label selection changes from cfs-label-selector.
   * @param {Event} event
   */
  _onLabelsChange(event) {
    const selected = event.target?.selected;
    this._selectedLabelIds = Array.isArray(selected) ? [...selected] : [];
  }

  /**
   * Builds a stable snapshot for mutable form values.
   * @returns {string}
   */
  _buildFormStateSnapshot() {
    return buildReviewFormStateSnapshot({
      message: this._message,
      ratingComment: this._ratingComment,
      ratingStars: this._ratingStars,
      selectedLabelIds: this._selectedLabelIds,
      statusId: this._statusId,
    });
  }

  /**
   * Checks whether there are pending changes that require saving.
   * @returns {boolean}
   */
  _hasPendingChanges() {
    if (!this._isOpen || !this._submission) {
      return false;
    }
    return this._buildFormStateSnapshot() !== this._initialFormSnapshot;
  }

  /**
   * Clears the selected rating and rating comment.
   */
  _clearRating() {
    this._hoverRatingStars = 0;
    this._ratingComment = "";
    this._ratingStars = 0;
  }

  /**
   * Handles rating comment updates.
   * @param {Event} event
   */
  _onRatingCommentInput(event) {
    this._ratingComment = event.target?.value || "";
  }

  /**
   * Handles rating star hover.
   * @param {number} stars
   */
  _onRatingStarEnter(stars) {
    this._hoverRatingStars = stars;
  }

  /**
   * Handles rating star selection.
   * @param {number} stars
   */
  _onRatingStarSelect(stars) {
    this._hoverRatingStars = 0;
    this._ratingStars = stars;
  }

  /**
   * Resets hover state for the star selector.
   */
  _onRatingStarsLeave() {
    this._hoverRatingStars = 0;
  }

  /**
   * Renders submission details panel.
   * @returns {import("lit").TemplateResult}
   */
  _renderDetailsPanel() {
    return renderCfsDetailsPanel({
      isActive: this._activeTab === REVIEW_TABS.DETAILS,
      labels: this.labels,
      onLabelsChange: (event) => this._onLabelsChange(event),
      selectedLabelIds: this._selectedLabelIds,
      submission: this._submission,
    });
  }

  /**
   * Handles status checkbox changes.
   * @param {Event} event
   * @param {string} statusId
   */
  _onStatusCheckChange(event, statusId) {
    if (event.target?.checked) {
      if (!isStatusAllowed(this._submission, statusId)) {
        return;
      }
      this._statusId = statusId;
    } else {
      this._statusId = isLinkedToSession(this._submission) ? "approved" : "not-reviewed";
    }
  }

  /**
   * Sets the active review tab.
   * @param {string} tabId
   */
  _setActiveTab(tabId) {
    if (!isKnownReviewTab(tabId, REVIEW_TABS)) {
      return;
    }
    this._activeTab = tabId;
  }

  _renderDecisionPanel() {
    return renderCfsDecisionPanel({
      isActive: this._activeTab === REVIEW_TABS.DECISION,
      message: this._message,
      messageMaxLength: this.messageMaxLength,
      onMessageInput: (event) => this._onMessageInput(event),
      onStatusCheckChange: (event, statusId) => this._onStatusCheckChange(event, statusId),
      statusId: this._statusId,
      statuses: this.statuses,
      submission: this._submission,
    });
  }

  /**
   * Renders ratings fields panel.
   * @returns {import("lit").TemplateResult}
   */
  _renderRatingsPanel() {
    return renderCfsRatingsPanel({
      currentUserId: this.currentUserId,
      hoverRatingStars: this._hoverRatingStars,
      isActive: this._activeTab === REVIEW_TABS.RATINGS,
      messageMaxLength: this.messageMaxLength,
      onClearRating: () => this._clearRating(),
      onRatingCommentInput: (event) => this._onRatingCommentInput(event),
      onRatingStarEnter: (stars) => this._onRatingStarEnter(stars),
      onRatingStarSelect: (stars) => this._onRatingStarSelect(stars),
      onRatingStarsLeave: () => this._onRatingStarsLeave(),
      ratingComment: this._ratingComment,
      ratingStars: this._ratingStars,
      renderPersonRow: renderCfsPersonRow,
      submission: this._submission,
    });
  }

  /**
   * Renders the modal when open.
   * @returns {import("lit").TemplateResult}
   */
  _renderModal() {
    if (!this._isOpen || !this._submission) {
      return html``;
    }

    const submissionEndpoint = this._buildSubmissionEndpoint();

    return html`
      <div
        class="fixed top-0 right-0 left-0 justify-center items-center w-full md:inset-0 overflow-y-auto overflow-x-hidden flex z-[1000]"
        role="dialog"
        aria-modal="true"
        aria-labelledby="cfs-submission-modal-title"
      >
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35]"
          @click=${() => this.close()}
        ></div>
        <div class="modal-panel p-4 max-w-5xl">
          <div class="modal-card rounded-2xl">
            <div class="flex items-center justify-between p-5 border-b border-stone-200 shrink-0">
              <h3 id="cfs-submission-modal-title" class="text-xl font-semibold text-stone-900">
                Review submission
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

            <form
              id="cfs-submission-form"
              class="flex min-h-0 flex-1 flex-col"
              hx-put=${submissionEndpoint}
              hx-swap="none"
              hx-indicator="#dashboard-spinner"
              hx-disabled-elt="#cfs-submission-submit"
            >
              <div class="px-8 pt-5 shrink-0">
                ${renderCfsReviewTabsNavigation({
                  activeTab: this._activeTab,
                  onSelect: (tabId) => this._setActiveTab(tabId),
                  tabs: REVIEW_TABS,
                })}
              </div>

              <div class="px-8 py-5 min-h-0 flex-1 overflow-y-auto">
                ${this._renderDetailsPanel()} ${this._renderRatingsPanel()} ${this._renderDecisionPanel()}
              </div>

              <div class="px-8 pb-5 pt-3 border-t border-stone-100 shrink-0">
                <div class="flex items-center justify-between gap-3">
                  <div class="min-w-0">${renderCfsPendingChangesAlert(this._hasPendingChanges())}</div>
                  <button
                    id="cfs-submission-submit"
                    type="submit"
                    class="btn-primary"
                    ?disabled=${!submissionEndpoint || !isStatusAllowed(this._submission, this._statusId)}
                  >
                    Save
                  </button>
                </div>
              </div>
            </form>
          </div>
        </div>
      </div>
    `;
  }

  /**
   * Main render method.
   * @returns {import("lit").TemplateResult}
   */
  render() {
    return html`${this._renderModal()}`;
  }
}

if (!customElements.get("review-submission-modal")) {
  customElements.define("review-submission-modal", ReviewSubmissionModal);
}
