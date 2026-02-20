import { html, unsafeHTML } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { computeUserInitials, lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import "/static/js/common/cfs-label-selector.js";
import "/static/js/common/logo-image.js";
import "/static/js/common/rating-stars.js";

const MODAL_ELEMENT_ID = "review-submission-modal";
const OPEN_ACTION = "open-cfs-submission-modal";
const DATA_KEY = "cfsSubmissionModalReady";
const APPROVED_SUBMISSIONS_EVENT = "event-approved-submissions-updated";
const SUBMISSIONS_CONTENT_ID = "submissions-content";
const SUBMISSIONS_FILTER_ID = "submissions-label-filter";
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
  }

  connectedCallback() {
    super.connectedCallback();
    this._loadLabelsFromAttribute();
    this._loadStatusesFromAttribute();
    document.addEventListener("keydown", this._onKeydown);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    if (this._isOpen) {
      unlockBodyScroll();
    }
    this._removeAfterRequestListener();
    document.removeEventListener("keydown", this._onKeydown);
  }

  /**
   * Opens the modal and loads submission data.
   * @param {Object} submission
   */
  open(submission) {
    if (!submission) {
      return;
    }
    const currentUserRating = this._findCurrentUserRating(submission);
    const shouldLockScroll = !this._isOpen;
    this.syncLabelsFromFilter();
    this._submission = submission;
    this._hoverRatingStars = 0;
    this._message = submission.action_required_message || "";
    this._ratingComment = currentUserRating?.comments || "";
    this._ratingStars = Number(currentUserRating?.stars || 0);
    this._activeTab = REVIEW_TABS.DETAILS;
    this._selectedLabelIds = (submission.labels || [])
      .map((label) => String(label?.event_cfs_label_id || ""))
      .filter((eventCfsLabelId) => eventCfsLabelId.length > 0);
    this._statusId = submission.linked_session_id ? "approved" : String(submission.status_id || "");
    this._initialFormSnapshot = this._buildFormStateSnapshot();
    this._isOpen = true;
    if (shouldLockScroll) {
      lockBodyScroll();
    }
  }

  /**
   * Closes the modal and resets current submission state.
   */
  close() {
    if (!this._isOpen) {
      return;
    }
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
    unlockBodyScroll();
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
      const form = this.querySelector("#cfs-submission-form");
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
    if (event.key === "Escape" && this._isOpen) {
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
    try {
      const parsedStatuses = JSON.parse(statusesAttr);
      if (Array.isArray(parsedStatuses)) {
        this.statuses = parsedStatuses;
      }
    } catch (error) {
      console.error("Invalid statuses payload", error);
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
    try {
      const parsedLabels = JSON.parse(labelsAttr);
      if (Array.isArray(parsedLabels)) {
        this.labels = parsedLabels;
      }
    } catch (error) {
      console.error("Invalid labels payload", error);
    }
  }

  /**
   * Synchronizes labels from the submissions filter component.
   */
  syncLabelsFromFilter() {
    const labelsFilter = document.getElementById(SUBMISSIONS_FILTER_ID);
    if (!labelsFilter) {
      return;
    }

    if (Array.isArray(labelsFilter.labels)) {
      this.labels = this._normalizeLabels(labelsFilter.labels);
      return;
    }

    const labelsAttr = labelsFilter.getAttribute("labels");
    if (!labelsAttr) {
      this.labels = [];
      return;
    }

    try {
      const parsedLabels = JSON.parse(labelsAttr);
      this.labels = this._normalizeLabels(parsedLabels);
    } catch (error) {
      console.error("Invalid labels payload", error);
      this.labels = [];
    }
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
    const form = this.querySelector("#cfs-submission-form");
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
    if (typeof document === "undefined" || !document.body) {
      return;
    }

    const submission = this._submission;
    if (!submission?.cfs_submission_id) {
      return;
    }

    const proposal = submission.session_proposal || {};
    const speakerName = submission.speaker?.name || submission.speaker?.username || "";
    const summary =
      this._statusId === "approved" && proposal?.session_proposal_id && proposal?.title && speakerName
        ? {
            cfs_submission_id: String(submission.cfs_submission_id),
            session_proposal_id: String(proposal.session_proposal_id),
            title: proposal.title,
            speaker_name: speakerName,
          }
        : null;

    document.body.dispatchEvent(
      new CustomEvent(APPROVED_SUBMISSIONS_EVENT, {
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
    const form = this.querySelector("#cfs-submission-form");
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
   * Finds the rating created by the current user.
   * @param {Object} submission
   * @returns {Object|null}
   */
  _findCurrentUserRating(submission) {
    const ratings = Array.isArray(submission?.ratings) ? submission.ratings : [];
    const currentUserId = String(this.currentUserId || "");
    if (!currentUserId) {
      return null;
    }
    return ratings.find((rating) => String(rating?.reviewer?.user_id || "") === currentUserId) || null;
  }

  /**
   * Builds a stable snapshot for mutable form values.
   * @returns {string}
   */
  _buildFormStateSnapshot() {
    const selectedLabelIds = [...this._selectedLabelIds].sort();
    return JSON.stringify({
      message: this._message,
      ratingComment: this._ratingComment,
      ratingStars: this._ratingStars,
      selectedLabelIds,
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
   * Returns the ratings list for the current submission.
   * @returns {Array<Object>}
   */
  _getSubmissionRatings() {
    return Array.isArray(this._submission?.ratings) ? this._submission.ratings : [];
  }

  /**
   * Returns ratings created by other reviewers.
   * @returns {Array<Object>}
   */
  _getOtherTeamRatings() {
    const ratings = this._getSubmissionRatings();
    const currentUserId = String(this.currentUserId || "");
    if (!currentUserId) {
      return [];
    }
    return ratings.filter((rating) => String(rating?.reviewer?.user_id || "") !== currentUserId);
  }

  /**
   * Resolves ratings count for the current submission.
   * @returns {number}
   */
  _getRatingsCount() {
    const ratingsCount = Number(this._submission?.ratings_count);
    if (Number.isFinite(ratingsCount) && ratingsCount >= 0) {
      return ratingsCount;
    }
    return this._getSubmissionRatings().length;
  }

  /**
   * Resolves average rating for the current submission.
   * @returns {number}
   */
  _getAverageRating() {
    const averageRating = Number(this._submission?.average_rating);
    if (Number.isFinite(averageRating)) {
      return averageRating;
    }
    return 0;
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

  _renderStarIcon(size = "size-5", color = "bg-amber-500") {
    return html`<div class="svg-icon ${size} icon-star ${color} shrink-0" aria-hidden="true"></div>`;
  }

  /**
   * Renders the current user's rating editor.
   * @returns {import("lit").TemplateResult}
   */
  _renderRatingEditor() {
    const highlightedStars = this._hoverRatingStars || this._ratingStars;
    const hasRating = this._ratingStars > 0;

    return html`
      <div>
        <label class="form-label">Your rating</label>
        <div class="mt-2 flex flex-wrap items-center gap-2" @mouseleave=${() => this._onRatingStarsLeave()}>
          ${[1, 2, 3, 4, 5].map((star) => {
            const isFilled = star <= highlightedStars;
            return html`
              <button
                type="button"
                class="inline-flex items-center justify-center rounded p-0.5 transition hover:bg-amber-50 focus-visible:ring-2 focus-visible:ring-amber-400"
                title=${`${star} ${star === 1 ? "star" : "stars"}`}
                @click=${() => this._onRatingStarSelect(star)}
                @focus=${() => this._onRatingStarEnter(star)}
                @mouseenter=${() => this._onRatingStarEnter(star)}
              >
                <span class="sr-only">${star} ${star === 1 ? "star" : "stars"}</span>
                ${this._renderStarIcon("size-6", isFilled ? "bg-amber-500" : "bg-stone-300")}
              </button>
            `;
          })}
          <button
            type="button"
            class="btn-primary-outline btn-mini inline-flex items-center justify-center self-center ms-2"
            @click=${() => this._clearRating()}
            ?disabled=${!hasRating}
          >
            Clear
          </button>
          <input type="hidden" name="rating_stars" .value=${String(this._ratingStars)} />
        </div>
      </div>

      <div>
        <div>
          <textarea
            id="cfs-submission-rating-comment"
            name="rating_comment"
            class="input-primary"
            maxlength=${this.messageMaxLength}
            rows="3"
            placeholder=${hasRating ? "Add notes for other admins..." : "Select a star rating to add notes."}
            aria-label="Your rating notes"
            .value=${this._ratingComment}
            @input=${(event) => this._onRatingCommentInput(event)}
            ?disabled=${!hasRating}
          ></textarea>
        </div>
        <p class="form-legend mt-2">Ratings are internal only. Speakers never see ratings or rating notes.</p>
      </div>
    `;
  }

  /**
   * Renders all ratings for the current submission.
   * @returns {import("lit").TemplateResult}
   */
  _renderRatingsList() {
    const ratings = this._getOtherTeamRatings();
    if (!ratings.length) {
      return html`
        <div>
          <div class="form-label">Other team ratings</div>
          <p class="text-sm text-stone-500 mt-2">No ratings yet from other team members.</p>
        </div>
      `;
    }

    return html`
      <div>
        <div class="form-label">Other team ratings</div>
        <div class="mt-3 space-y-3">
          ${ratings.map((rating) => {
            const comments = String(rating?.comments || "").trim();
            const stars = Number(rating?.stars || 0);

            return html`
              <div class="rounded-lg border border-stone-200 bg-stone-50/50 px-4 py-3">
                <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                  <div class="min-w-0 flex-1">
                    ${rating?.reviewer
                      ? this._renderPersonRow(rating.reviewer)
                      : html`<div class="text-sm text-stone-500">Unknown reviewer</div>`}
                    ${comments
                      ? html`<p class="mt-3 text-sm text-stone-700 whitespace-pre-line">${comments}</p>`
                      : html`<p class="mt-3 text-sm text-stone-400">No notes provided.</p>`}
                  </div>
                  <div class="inline-flex items-center whitespace-nowrap md:shrink-0">
                    <rating-stars .averageRating=${stars} size="size-5"></rating-stars>
                  </div>
                </div>
              </div>
            `;
          })}
        </div>
      </div>
    `;
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
                  ? unsafeHTML(proposal.description_html)
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

        <div class="border-t border-stone-200 pt-5">${this._renderDetailsLabels()}</div>
      </section>
    `;
  }

  /**
   * Renders ratings summary card.
   * @returns {import("lit").TemplateResult}
   */
  _renderRatingsSummaryCard() {
    const ratingsCount = this._getRatingsCount();
    const averageRating = this._getAverageRating();
    const averageRatingText = Number.isInteger(averageRating)
      ? String(averageRating)
      : averageRating.toFixed(1);

    return html`
      <div class="rounded-lg border border-stone-200 bg-stone-50/70 px-4 py-3">
        <div class="flex flex-col gap-5 sm:flex-row sm:items-center">
          <div class="shrink-0">
            <div class="text-3xl font-semibold leading-none text-stone-800 text-center">
              ${ratingsCount > 0 ? averageRatingText : "-"}
            </div>
            <div class="text-xs text-stone-500 text-center">out of 5</div>
          </div>
          <div class="sm:border-l sm:border-stone-200 sm:pl-5 min-w-0 flex flex-col gap-1">
            <div class="form-label text-stone-700">Summary rating</div>
            <div>
              <rating-stars
                .averageRating=${ratingsCount > 0 ? averageRating : 0}
                size="size-5"
              ></rating-stars>
            </div>
            <div class="text-sm/6 mt-1 text-stone-600">
              (${ratingsCount} ${ratingsCount === 1 ? "rating" : "ratings"})
            </div>
          </div>
        </div>
      </div>
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
   * Returns the color classes for a status.
   * @param {string} statusId
   * @returns {Object}
   */
  _getStatusColor(statusId) {
    switch (statusId) {
      case "rejected":
        return { border: "border-red-600", ring: "ring-2 ring-red-200", dot: "bg-red-600" };
      case "information-requested":
        return { border: "border-orange-600", ring: "ring-2 ring-orange-200", dot: "bg-orange-600" };
      case "approved":
        return { border: "border-emerald-600", ring: "ring-2 ring-emerald-200", dot: "bg-emerald-600" };
      default:
        return { border: "border-primary-500", ring: "ring-2 ring-primary-200", dot: "bg-primary-500" };
    }
  }

  /**
   * Checks if the message textarea should be required.
   * @returns {boolean}
   */
  _isMessageRequired() {
    return this._statusId === "information-requested";
  }

  /**
   * Checks whether the submission is linked to an event session.
   * @returns {boolean}
   */
  _isLinkedToSession() {
    return Boolean(this._submission?.linked_session_id);
  }

  /**
   * Checks whether a status can be selected for the current submission.
   * @param {string} statusId
   * @returns {boolean}
   */
  _isStatusAllowed(statusId) {
    if (!this._isLinkedToSession()) {
      return true;
    }
    return statusId === "approved";
  }

  /**
   * Checks whether the current status selection can be submitted.
   * @returns {boolean}
   */
  _isStatusSelectionValid() {
    return this._isStatusAllowed(this._statusId);
  }

  /**
   * Normalizes available labels payload.
   * @param {Array<Object>} labels
   * @returns {Array<Object>}
   */
  _normalizeLabels(labels) {
    if (!Array.isArray(labels)) {
      return [];
    }

    return labels
      .map((label) => {
        return {
          color: String(label?.color || "").trim(),
          event_cfs_label_id: String(label?.event_cfs_label_id || "").trim(),
          name: String(label?.name || "").trim(),
        };
      })
      .filter((label) => label.event_cfs_label_id && label.name);
  }

  /**
   * Handles status checkbox changes.
   * @param {Event} event
   * @param {string} statusId
   */
  _onStatusCheckChange(event, statusId) {
    if (event.target?.checked) {
      if (!this._isStatusAllowed(statusId)) {
        return;
      }
      this._statusId = statusId;
    } else {
      this._statusId = this._isLinkedToSession() ? "approved" : "not-reviewed";
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

  /**
   * Renders decision fields panel.
   * @returns {import("lit").TemplateResult}
   */
  _renderDecisionPanel() {
    const isActive = this._activeTab === REVIEW_TABS.DECISION;
    return html`
      <section
        id="cfs-submission-tabpanel-decision"
        role="tabpanel"
        class="pt-5 space-y-8"
        ?hidden=${!isActive}
      >
        <div>
          <label class="form-label">Decision</label>
          <div class="mt-3">${this._renderStatusBoxes()}</div>
          ${this._isLinkedToSession()
            ? html`
                <p class="form-legend mt-2">
                  This submission is linked to a session. Unlink it from the session before choosing a
                  non-approved status.
                </p>
              `
            : ""}
        </div>

        <div>
          <label for="cfs-submission-message" class="form-label">
            Message for speaker ${this._isMessageRequired() ? html`<span class="asterisk">*</span>` : ""}
          </label>
          <div class="mt-2">
            <textarea
              id="cfs-submission-message"
              name="action_required_message"
              class="input-primary"
              maxlength=${this.messageMaxLength}
              rows="3"
              placeholder="Add a note for the speaker..."
              .value=${this._message}
              @input=${(event) => this._onMessageInput(event)}
              ?required=${this._isMessageRequired()}
            ></textarea>
          </div>
          <p class="form-legend">
            Required when requesting changes. Explain what information or changes are needed.
          </p>
        </div>
      </section>
    `;
  }

  /**
   * Renders ratings fields panel.
   * @returns {import("lit").TemplateResult}
   */
  _renderRatingsPanel() {
    const isActive = this._activeTab === REVIEW_TABS.RATINGS;
    return html`
      <section
        id="cfs-submission-tabpanel-ratings"
        role="tabpanel"
        class="pt-5 space-y-8"
        ?hidden=${!isActive}
      >
        ${this._renderRatingsSummaryCard()} ${this._renderRatingEditor()} ${this._renderRatingsList()}
      </section>
    `;
  }

  /**
   * Renders status selection boxes.
   * @returns {import("lit").TemplateResult}
   */
  _renderStatusBoxes() {
    const reviewStatuses = this.statuses.filter((s) => s.cfs_submission_status_id !== "not-reviewed");
    const isLinked = this._isLinkedToSession();

    return html`
      <div class="grid grid-cols-3 gap-3">
        ${reviewStatuses.map((status) => {
          const statusId = status?.cfs_submission_status_id || "";
          const isSelected = this._statusId === statusId;
          const color = this._getStatusColor(statusId);
          const isDisabled = isLinked && statusId !== "approved";

          return html`
            <label class="block ${isDisabled ? "cursor-not-allowed opacity-60" : "cursor-pointer"}">
              <input
                type="checkbox"
                value=${statusId}
                class="sr-only"
                .checked=${isSelected}
                @change=${(e) => this._onStatusCheckChange(e, statusId)}
                ?disabled=${isDisabled}
              />
              <div
                class="rounded-lg border p-3 transition bg-white ${isSelected
                  ? `${color.border} ${color.ring}`
                  : "border-stone-200"}"
              >
                <div class="flex items-center gap-2">
                  <span
                    class="relative flex h-4 w-4 items-center justify-center rounded border ${isSelected
                      ? color.border
                      : "border-stone-200"}"
                  >
                    ${isSelected ? html`<div class="svg-icon size-3 icon-check ${color.dot}"></div>` : ""}
                  </span>
                  <span class="text-sm font-medium text-stone-700">${status?.display_name || ""}</span>
                </div>
              </div>
            </label>
          `;
        })}
      </div>
      <input type="hidden" name="status_id" .value=${this._statusId} />
    `;
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
        class="fixed top-0 right-0 left-0 justify-center items-center w-full md:inset-0 max-h-full overflow-y-auto flex z-[1000]"
        role="dialog"
        aria-modal="true"
        aria-labelledby="cfs-submission-modal-title"
      >
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35]"
          @click=${() => this.close()}
        ></div>
        <div class="relative p-4 w-full max-w-5xl h-[90vh]">
          <div class="relative bg-white rounded-2xl shadow-lg h-full flex flex-col overflow-hidden">
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
                    ?disabled=${!submissionEndpoint || !this._isStatusSelectionValid()}
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

const initializeCfsSubmissions = () => {
  if (!document.body || document.body.dataset[DATA_KEY] === "true") {
    return;
  }
  document.body.dataset[DATA_KEY] = "true";
  document.body.addEventListener("htmx:afterSwap", (event) => {
    const target = event?.detail?.target || event?.detail?.elt;
    if (!(target instanceof Element) || target.id !== SUBMISSIONS_CONTENT_ID) {
      return;
    }

    const modal = document.getElementById(MODAL_ELEMENT_ID);
    if (!modal || typeof modal.syncLabelsFromFilter !== "function") {
      return;
    }

    modal.syncLabelsFromFilter();
  });

  document.body.addEventListener("click", (event) => {
    if (!(event.target instanceof Element)) {
      return;
    }
    const button = event.target.closest(`[data-action="${OPEN_ACTION}"]`);
    if (!button) {
      return;
    }
    const payload = button.dataset.submission;
    if (!payload) {
      return;
    }
    const modal = document.getElementById(MODAL_ELEMENT_ID);
    if (!modal || typeof modal.open !== "function") {
      return;
    }
    try {
      const submission = JSON.parse(payload);
      const descriptionHtmlPayload = button.dataset.proposalDescriptionHtml;
      if (descriptionHtmlPayload && submission?.session_proposal) {
        try {
          const descriptionHtml = JSON.parse(descriptionHtmlPayload);
          if (typeof descriptionHtml === "string") {
            submission.session_proposal.description_html = descriptionHtml;
          }
        } catch (error) {
          console.error("Invalid proposal description html payload", error);
        }
      }
      modal.open(submission);
    } catch (error) {
      console.error("Invalid submission payload", error);
    }
  });
};

initializeCfsSubmissions();
