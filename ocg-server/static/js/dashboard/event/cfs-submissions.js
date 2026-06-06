import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { computeUserInitials } from "/static/js/common/common.js";
import { renderCfsDecisionPanel } from "/static/js/dashboard/event/cfs-submissions-decision.js";
import { renderCfsRatingsPanel } from "/static/js/dashboard/event/cfs-submissions-ratings.js";
import {
  closestElement,
  getElementById,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";
import {
  bindModalDismissListeners,
  closeModalBodyScroll,
  isModalEscapeEvent,
  openModalBodyScroll,
} from "/static/js/common/modal-lifecycle.js";
import { renderTrustedHtml } from "/static/js/common/trusted-lit-html.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import {
  buildApprovedSubmissionSummary,
  buildReviewModalOpenState,
  buildReviewFormStateSnapshot,
  findCurrentUserRating,
  isLinkedToSession,
  isStatusAllowed,
  normalizeLabels,
} from "/static/js/dashboard/event/cfs-submissions-review-utils.js";
import "/static/js/common/cfs-label-selector.js";
import "/static/js/common/logo-image.js";

const MODAL_ELEMENT_ID = "review-submission-modal";
const OPEN_ACTION = "open-cfs-submission-modal";
const DATA_KEY = "cfsSubmissionModalReady";
const APPROVED_SUBMISSIONS_EVENT = "event-approved-submissions-updated";
const SUBMISSIONS_CONTENT_ID = "submissions-content";
const SUBMISSIONS_FILTERS_FORM_ID = "submissions-filters-form";
const SUBMISSIONS_FILTER_ID = "submissions-label-filter";
const SUBMISSIONS_FILTERS_SORT_ID = "submissions-sort";
const SUBMISSIONS_FILTERS_BOUND_KEY = "submissionsFiltersBound";
const REVIEW_TABS = {
  DETAILS: "details",
  DECISION: "decision",
  RATINGS: "ratings",
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
    this.currentUserId = "";
    this.eventId = "";
    this.labels = [];
    this.messageMaxLength = 5000;
    this.statuses = [];
    this._hoverRatingStars = 0;
    this._isOpen = false;
    this._message = "";
    this._ratingComment = "";
    this._ratingStars = 0;
    this._activeTab = REVIEW_TABS.DETAILS;
    this._selectedLabelIds = [];
    this._statusId = "";
    this._submission = null;
    this._initialFormSnapshot = "";
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
    this._isOpen = false;
    this._submission = null;
    this._hoverRatingStars = 0;
    this._message = "";
    this._ratingComment = "";
    this._ratingStars = 0;
    this._activeTab = REVIEW_TABS.DETAILS;
    this._selectedLabelIds = [];
    this._statusId = "";
    this._initialFormSnapshot = "";
    this._removeAfterRequestListener();
    this._isOpen = closeModalBodyScroll(wasOpen);
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
    if (isModalEscapeEvent(event) && this._isOpen) {
      this.close();
    }
  }

  /**
   * Loads statuses from the statuses attribute.
   */
  _loadStatusesFromAttribute() {
    const statusesAttr = this.getAttribute("statuses");
    if (!statusesAttr || this.statuses.length > 0) {
      return;
    }
    const parsedStatuses = parseJsonAttribute(statusesAttr, []);
    if (Array.isArray(parsedStatuses)) {
      this.statuses = parsedStatuses;
    }
  }

  /**
   * Loads available labels from the labels attribute.
   */
  _loadLabelsFromAttribute() {
    const labelsAttr = this.getAttribute("labels");
    if (!labelsAttr || this.labels.length > 0) {
      return;
    }
    const parsedLabels = parseJsonAttribute(labelsAttr, []);
    if (Array.isArray(parsedLabels)) {
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

    this.labels = normalizeLabels(parseJsonAttribute(labelsAttr, []));
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
      const ok = handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to update this submission. Please try again later.",
      });
      if (ok) {
        this._emitApprovedSubmissionsUpdate();
        this.close();
      }
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

    const summary = buildApprovedSubmissionSummary(submission, this._statusId);

    this.dispatchEvent(
      new CustomEvent(APPROVED_SUBMISSIONS_EVENT, {
        bubbles: true,
        composed: true,
        detail: {
          approved: this._statusId === "approved",
          cfsSubmissionId: String(submission.cfs_submission_id),
          submission: summary,
        },
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
   * Renders a badge row for a person.
   * @param {Object} person
   * @returns {import("lit").TemplateResult}
   */
  _renderPersonRow(person) {
    const name = person?.name || person?.username || "";
    const photoUrl = person?.photo_url || "";
    const initials = computeUserInitials(name, person?.username || "", 2);

    return html`
      <div
        class="inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-2 py-1 max-w-full"
        title=${name}
      >
        <logo-image
          class="shrink-0"
          image-url=${photoUrl}
          placeholder=${initials}
          size="size-[24px]"
          font-size="text-xs"
          hide-border
        ></logo-image>
        <span class="text-sm text-stone-700 truncate">${name}</span>
      </div>
    `;
  }

  /**
   * Renders proposal metadata badges.
   * @param {Object} proposal
   * @returns {import("lit").TemplateResult}
   */
  _renderProposalMeta(proposal) {
    const level = proposal?.session_proposal_level_name;
    const duration = proposal?.duration_minutes;
    return html`
      ${level
        ? html`
            <div>
              <div class="proposal-section-title">Level</div>
              <div class="mt-1 text-sm text-stone-700">${level}</div>
            </div>
          `
        : ""}
      ${duration
        ? html`
            <div>
              <div class="proposal-section-title">Duration</div>
              <div class="mt-1 text-sm text-stone-700">${duration} min</div>
            </div>
          `
        : ""}
    `;
  }

  /**
   * Renders labels editor for the details tab.
   * @returns {import("lit").TemplateResult}
   */
  _renderDetailsLabels() {
    if (this.labels.length === 0) {
      return html``;
    }

    return html`
      <div>
        <label for="cfs-submission-labels" class="form-label">Labels</label>
        <div class="mt-2">
          <cfs-label-selector
            id="cfs-submission-labels"
            name="label_ids"
            .labels=${this.labels}
            .selected=${this._selectedLabelIds}
            close-on-select
            max-selected="10"
            legend="Add labels to categorize this submission for your review team."
            placeholder="Search labels"
            @change=${(event) => this._onLabelsChange(event)}
          ></cfs-label-selector>
        </div>
      </div>
    `;
  }

  /**
   * Renders submission details panel.
   * @returns {import("lit").TemplateResult}
   */
  _renderDetailsPanel() {
    const isActive = this._activeTab === REVIEW_TABS.DETAILS;
    const proposal = this._submission?.session_proposal || {};
    const coSpeaker = proposal?.co_speaker;

    return html`
      <section
        id="cfs-submission-tabpanel-details"
        role="tabpanel"
        class="pt-5 space-y-8"
        ?hidden=${!isActive}
      >
        <div class="flex flex-col md:flex-row gap-6">
          <div class="flex-1 space-y-4 min-w-0">
            <div>
              <div class="proposal-section-title">Title</div>
              <div class="mt-2 text-lg text-stone-800 font-medium">${proposal?.title || ""}</div>
            </div>

            <div>
              <div class="proposal-section-title">Description</div>
              <div class="mt-2 max-h-[200px] overflow-y-auto text-stone-700 text-sm/6 markdown">
                ${proposal?.description_html
                  ? renderTrustedHtml(proposal.description_html)
                  : proposal?.description || ""}
              </div>
            </div>
          </div>

          <div class="w-full md:w-72 shrink-0 space-y-4 md:border-l md:border-stone-100 md:pl-6">
            ${this._renderProposalMeta(proposal)}

            <div>
              <div class="proposal-section-title">Speaker</div>
              <div class="mt-2">
                ${this._submission?.speaker ? this._renderPersonRow(this._submission.speaker) : ""}
              </div>
            </div>

            ${coSpeaker
              ? html`
                  <div>
                    <div class="proposal-section-title">Co-speaker</div>
                    <div class="mt-2">${this._renderPersonRow(coSpeaker)}</div>
                  </div>
                `
              : ""}
          </div>
        </div>

        ${this.labels.length > 0
          ? html`<div class="border-t border-stone-200 pt-5">${this._renderDetailsLabels()}</div>`
          : ""}
      </section>
    `;
  }

  /**
   * Renders pending changes alert.
   * @returns {import("lit").TemplateResult}
   */
  _renderPendingChangesAlert() {
    if (!this._hasPendingChanges()) {
      return html``;
    }

    return html`
      <div
        class="inline-flex items-center gap-3 rounded-md border border-primary-200 bg-primary-50 px-3 py-2 text-primary-900"
      >
        <div class="svg-icon size-4 bg-primary-700 icon-clock shrink-0"></div>
        <p class="text-sm">You have pending changes. Click Save to apply these updates.</p>
      </div>
    `;
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
    if (tabId !== REVIEW_TABS.DETAILS && tabId !== REVIEW_TABS.DECISION && tabId !== REVIEW_TABS.RATINGS) {
      return;
    }
    this._activeTab = tabId;
  }

  /**
   * Renders the review tabs navigation.
   * @returns {import("lit").TemplateResult}
   */
  _renderReviewTabsNavigation() {
    const isDetailsActive = this._activeTab === REVIEW_TABS.DETAILS;
    const isDecisionActive = this._activeTab === REVIEW_TABS.DECISION;
    const isRatingsActive = this._activeTab === REVIEW_TABS.RATINGS;

    return html`
      <ul
        class="flex flex-wrap space-x-2 -mb-px text-sm font-medium text-center border-b border-stone-200"
        role="tablist"
        aria-label="Submission review tabs"
      >
        <li>
          <button
            type="button"
            role="tab"
            aria-controls="cfs-submission-tabpanel-details"
            aria-selected=${isDetailsActive ? "true" : "false"}
            data-active=${isDetailsActive ? "true" : "false"}
            class="cursor-pointer inline-flex items-center justify-center p-2 sm:p-3 border-b-2 border-transparent rounded-t-lg hover:text-stone-600 hover:border-stone-300 data-[active=true]:text-primary-500 data-[active=true]:border-primary-500 text-nowrap w-32"
            @click=${() => this._setActiveTab(REVIEW_TABS.DETAILS)}
          >
            Details
          </button>
        </li>
        <li>
          <button
            type="button"
            role="tab"
            aria-controls="cfs-submission-tabpanel-ratings"
            aria-selected=${isRatingsActive ? "true" : "false"}
            data-active=${isRatingsActive ? "true" : "false"}
            class="cursor-pointer inline-flex items-center justify-center p-2 sm:p-3 border-b-2 border-transparent rounded-t-lg hover:text-stone-600 hover:border-stone-300 data-[active=true]:text-primary-500 data-[active=true]:border-primary-500 text-nowrap w-32"
            @click=${() => this._setActiveTab(REVIEW_TABS.RATINGS)}
          >
            Ratings
          </button>
        </li>
        <li>
          <button
            type="button"
            role="tab"
            aria-controls="cfs-submission-tabpanel-decision"
            aria-selected=${isDecisionActive ? "true" : "false"}
            data-active=${isDecisionActive ? "true" : "false"}
            class="cursor-pointer inline-flex items-center justify-center p-2 sm:p-3 border-b-2 border-transparent rounded-t-lg hover:text-stone-600 hover:border-stone-300 data-[active=true]:text-primary-500 data-[active=true]:border-primary-500 text-nowrap w-32"
            @click=${() => this._setActiveTab(REVIEW_TABS.DECISION)}
          >
            Decision
          </button>
        </li>
      </ul>
    `;
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
      renderPersonRow: (person) => this._renderPersonRow(person),
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
              <div class="px-8 pt-5 shrink-0">${this._renderReviewTabsNavigation()}</div>

              <div class="px-8 py-5 min-h-0 flex-1 overflow-y-auto">
                ${this._renderDetailsPanel()} ${this._renderRatingsPanel()} ${this._renderDecisionPanel()}
              </div>

              <div class="px-8 pb-5 pt-3 border-t border-stone-100 shrink-0">
                <div class="flex items-center justify-between gap-3">
                  <div class="min-w-0">${this._renderPendingChangesAlert()}</div>
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

/**
 * Initializes auto-submit behavior for the submissions filters form.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
export const initializeSubmissionFilters = (root = document) => {
  const form = getElementById(root, SUBMISSIONS_FILTERS_FORM_ID);
  if (!markDatasetReady(form, SUBMISSIONS_FILTERS_BOUND_KEY)) {
    return;
  }

  const sort = getElementById(root, SUBMISSIONS_FILTERS_SORT_ID);
  const labelFilter = getElementById(root, SUBMISSIONS_FILTER_ID);
  const submitFilters = () => {
    window.requestAnimationFrame(() => form.requestSubmit());
  };

  sort?.addEventListener("change", submitFilters);
  labelFilter?.addEventListener("change", submitFilters);
};

const getReviewSubmissionModal = () => getElementById(document, MODAL_ELEMENT_ID);

const bindCfsSubmissionGlobalHandlers = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("htmx:afterSwap", (event) => {
    const target = event?.detail?.target || event?.detail?.elt;
    if (!(target instanceof Element) || target.id !== SUBMISSIONS_CONTENT_ID) {
      return;
    }

    initializeSubmissionFilters(target);

    const modal = getReviewSubmissionModal();
    if (!modal || typeof modal.syncLabelsFromFilter !== "function") {
      return;
    }

    modal.syncLabelsFromFilter();
  });

  document.addEventListener("click", (event) => {
    const button = closestElement(event.target, `[data-action="${OPEN_ACTION}"]`);
    if (!button) {
      return;
    }
    const payload = button.dataset.submission;
    if (!payload) {
      return;
    }
    const modal = getReviewSubmissionModal();
    if (!modal || typeof modal.open !== "function") {
      return;
    }
    const submission = parseJsonAttribute(payload, null);
    if (!submission || typeof submission !== "object" || Array.isArray(submission)) {
      console.error("Invalid submission payload");
      return;
    }
    const descriptionHtmlPayload = button.dataset.proposalDescriptionHtml;
    if (descriptionHtmlPayload && submission?.session_proposal) {
      const descriptionHtml = parseJsonAttribute(descriptionHtmlPayload, "");
      if (typeof descriptionHtml === "string") {
        submission.session_proposal.description_html = descriptionHtml;
      }
    }
    modal.open(submission);
  });
};

const initializeCfsSubmissions = (root = document) => {
  bindCfsSubmissionGlobalHandlers();
  initializeSubmissionFilters(root);
};

initializeOnReadyAndHtmxLoad(initializeCfsSubmissions);
