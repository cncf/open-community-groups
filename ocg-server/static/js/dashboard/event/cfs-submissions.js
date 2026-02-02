import { html, unsafeHTML } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { computeUserInitials, lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import "/static/js/common/logo-image.js";

const MODAL_ELEMENT_ID = "review-submission-modal";
const OPEN_ACTION = "open-cfs-submission-modal";
const DATA_KEY = "cfsSubmissionModalReady";
const PROPOSAL_SECTION_TITLE_CLASS = "form-label uppercase text-xs text-stone-400";

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
      eventId: { type: String, attribute: "event-id" },
      messageMaxLength: { type: Number, attribute: "message-max-length" },
      statuses: { type: Array, attribute: false },
      _isOpen: { type: Boolean },
      _message: { type: String },
      _statusId: { type: String },
      _submission: { type: Object },
    };
  }

  constructor() {
    super();
    this.eventId = "";
    this.messageMaxLength = 5000;
    this.statuses = [];
    this._isOpen = false;
    this._message = "";
    this._statusId = "";
    this._submission = null;
    this._afterRequestHandler = null;
    this._onKeydown = this._onKeydown.bind(this);
  }

  connectedCallback() {
    super.connectedCallback();
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
    const shouldLockScroll = !this._isOpen;
    this._submission = submission;
    this._message = submission.action_required_message || "";
    this._statusId = String(submission.status_id || "");
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
    this._message = "";
    this._statusId = "";
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
        this.close();
        document.body?.dispatchEvent(new CustomEvent("refresh-event-submissions", { bubbles: true }));
      }
    };
    form.addEventListener("htmx:afterRequest", this._afterRequestHandler);
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
              <div class=${PROPOSAL_SECTION_TITLE_CLASS}>Level</div>
              <div class="mt-1 text-sm text-stone-700">${level}</div>
            </div>
          `
        : ""}
      ${duration
        ? html`
            <div>
              <div class=${PROPOSAL_SECTION_TITLE_CLASS}>Duration</div>
              <div class="mt-1 text-sm text-stone-700">${duration} min</div>
            </div>
          `
        : ""}
    `;
  }

  /**
   * Returns the color classes for a status.
   * @param {string} statusId
   * @returns {Object}
   */
  _getStatusColors(statusId) {
    switch (statusId) {
      case "rejected":
        return {
          bg: "bg-white",
          border: "border-stone-200",
          borderSelected: "border-red-600 ring-2 ring-red-200",
          text: "text-stone-700",
          dot: "bg-red-600",
        };
      case "information-requested":
        return {
          bg: "bg-white",
          border: "border-stone-200",
          borderSelected: "border-amber-600 ring-2 ring-amber-200",
          text: "text-stone-700",
          dot: "bg-amber-600",
        };
      case "approved":
        return {
          bg: "bg-white",
          border: "border-stone-200",
          borderSelected: "border-green-600 ring-2 ring-green-200",
          text: "text-stone-700",
          dot: "bg-green-600",
        };
      default:
        return {
          bg: "bg-white",
          border: "border-stone-200",
          borderSelected: "border-primary-500 ring-2 ring-primary-200",
          text: "text-stone-700",
          dot: "bg-primary-500",
        };
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
   * Handles status checkbox changes.
   * @param {Event} event
   * @param {string} statusId
   */
  _onStatusCheckChange(event, statusId) {
    if (event.target?.checked) {
      this._statusId = statusId;
    } else {
      this._statusId = "not-reviewed";
    }
  }

  /**
   * Renders status selection boxes.
   * @returns {import("lit").TemplateResult}
   */
  _renderStatusBoxes() {
    const reviewStatuses = this.statuses.filter((s) => s.cfs_submission_status_id !== "not-reviewed");

    return html`
      <div class="grid grid-cols-3 gap-3">
        ${reviewStatuses.map((status) => {
          const statusId = status?.cfs_submission_status_id || "";
          const isSelected = this._statusId === statusId;
          const colors = this._getStatusColors(statusId);

          return html`
            <label class="block cursor-pointer">
              <input
                type="checkbox"
                name="status_id"
                value=${statusId}
                class="sr-only"
                .checked=${isSelected}
                @change=${(e) => this._onStatusCheckChange(e, statusId)}
              />
              <div
                class="rounded-lg border p-3 transition ${colors.bg} ${isSelected
                  ? colors.borderSelected
                  : colors.border}"
              >
                <div class="flex items-center gap-2">
                  <span
                    class="relative flex h-4 w-4 items-center justify-center rounded border ${isSelected
                      ? colors.borderSelected.split(" ")[0]
                      : colors.border}"
                  >
                    ${isSelected ? html`<div class="svg-icon size-3 icon-check ${colors.dot}"></div>` : ""}
                  </span>
                  <span class="text-sm font-medium ${colors.text}"> ${status?.display_name || ""} </span>
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

    const proposal = this._submission.session_proposal || {};
    const submissionEndpoint = this._buildSubmissionEndpoint();
    const coSpeaker = proposal?.co_speaker;

    return html`
      <div
        class="fixed top-0 right-0 left-0 justify-center items-center w-full md:inset-0 max-h-full flex z-[1000]"
        role="dialog"
        aria-modal="true"
        aria-labelledby="cfs-submission-modal-title"
      >
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35]"
          @click=${() => this.close()}
        ></div>
        <div class="relative p-4 w-full max-w-5xl max-h-full">
          <div class="relative bg-white rounded-2xl shadow-lg">
            <div class="flex items-center justify-between p-5 border-b border-stone-200">
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

            <div class="px-8 py-5">
              <form
                id="cfs-submission-form"
                hx-put=${submissionEndpoint}
                hx-swap="none"
                hx-indicator="#dashboard-spinner"
                hx-disabled-elt="#cfs-submission-submit"
              >
                <div class="flex flex-col md:flex-row gap-6">
                  <div class="flex-1 space-y-4 min-w-0">
                    <div>
                      <div class=${PROPOSAL_SECTION_TITLE_CLASS}>Title</div>
                      <div class="mt-2 text-lg text-stone-800 font-medium">${proposal?.title || ""}</div>
                    </div>

                    <div>
                      <div class=${PROPOSAL_SECTION_TITLE_CLASS}>Description</div>
                      <div class="mt-2 max-h-[200px] overflow-y-auto text-stone-500 text-sm/6 markdown">
                        ${proposal?.description_html
                          ? unsafeHTML(proposal.description_html)
                          : proposal?.description || ""}
                      </div>
                    </div>
                  </div>

                  <div class="w-full md:w-72 shrink-0 space-y-4 md:border-l md:border-stone-100 md:pl-6">
                    ${this._renderProposalMeta(proposal)}

                    <div>
                      <div class=${PROPOSAL_SECTION_TITLE_CLASS}>Speaker</div>
                      <div class="mt-2">
                        ${this._submission?.speaker ? this._renderPersonRow(this._submission.speaker) : ""}
                      </div>
                    </div>

                    ${coSpeaker
                      ? html`
                          <div>
                            <div class=${PROPOSAL_SECTION_TITLE_CLASS}>Co-speaker</div>
                            <div class="mt-2">${this._renderPersonRow(coSpeaker)}</div>
                          </div>
                        `
                      : ""}
                  </div>
                </div>

                <div class="border-t border-stone-200 pt-5 mt-5">
                  <div class="space-y-5">
                    <div>
                      <label class="form-label">Decision</label>
                      <div class="mt-3">${this._renderStatusBoxes()}</div>
                    </div>

                    <div>
                      <label for="cfs-submission-message" class="form-label">
                        Message for speaker
                        ${this._isMessageRequired() ? html`<span class="asterisk">*</span>` : ""}
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
                          @input=${(e) => this._onMessageInput(e)}
                          ?required=${this._isMessageRequired()}
                        ></textarea>
                      </div>
                      <p class="form-legend">
                        Required when requesting changes. Explain what information or changes are needed.
                      </p>
                    </div>
                  </div>
                </div>

                <div class="flex items-center justify-end gap-3 pt-3 mt-4 border-t border-stone-100">
                  <button
                    id="cfs-submission-submit"
                    type="submit"
                    class="btn-primary"
                    ?disabled=${!submissionEndpoint}
                  >
                    Save
                  </button>
                </div>
              </form>
            </div>
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
