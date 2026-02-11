import { html, unsafeHTML } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { computeUserInitials, lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import "/static/js/common/logo-image.js";
import "/static/js/common/user-search-field.js";

const PROPOSAL_SECTION_TITLE_CLASS = "form-label uppercase text-xs text-stone-400";

/**
 * Modal component for creating, editing, and viewing session proposals.
 * Keeps HTMX submit behavior while centralizing UI state in a Lit component.
 */
export class SessionProposalModal extends LitWrapper {
  static FORM_MODE = {
    CREATE: "create",
    EDIT: "edit",
    VIEW: "view",
  };

  /**
   * Defines reactive properties and internal state tracked by Lit.
   * @property {number} titleMaxLength - Max length allowed for proposal title.
   * @property {number} descriptionMaxLength - Max length allowed for description text.
   * @property {number} durationMax - Max allowed value for duration in minutes.
   * @property {Array} _sessionProposalLevels - Available level options for the form.
   * @property {boolean} _isOpen - Internal visibility state for the modal.
   * @property {string} _mode - Active form mode (create, edit, or view).
   * @property {Object|null} _activeProposal - Proposal currently loaded in the form.
   * @property {Object|null} _selectedCoSpeaker - Selected co-speaker user, if any.
   */
  static properties = {
    titleMaxLength: { type: Number, attribute: "title-max-length" },
    descriptionMaxLength: { type: Number, attribute: "description-max-length" },
    durationMax: { type: Number, attribute: "duration-max" },
    _sessionProposalLevels: { type: Array, attribute: false },
    _isOpen: { type: Boolean, attribute: false },
    _mode: { type: String, attribute: false },
    _activeProposal: { type: Object, attribute: false },
    _selectedCoSpeaker: { type: Object, attribute: false },
  };

  /**
   * Initializes defaults for limits, form state, and event handlers.
   */
  constructor() {
    super();
    this.titleMaxLength = 255;
    this.descriptionMaxLength = 5000;
    this.durationMax = 600;
    this._sessionProposalLevels = [];
    this._isOpen = false;
    this._mode = SessionProposalModal.FORM_MODE.CREATE;
    this._activeProposal = null;
    this._selectedCoSpeaker = null;
    this._afterRequestHandler = null;
    this._onKeydown = this._onKeydown.bind(this);
  }

  /**
   * Loads static options and subscribes to keyboard events.
   */
  connectedCallback() {
    super.connectedCallback();
    this._loadLevelsFromAttribute();
    document.addEventListener("keydown", this._onKeydown);
  }

  /**
   * Cleans listeners and restores body scroll if the modal is still open.
   */
  disconnectedCallback() {
    super.disconnectedCallback();
    this._removeAfterRequestListener();
    document.removeEventListener("keydown", this._onKeydown);
    if (this._isOpen) {
      unlockBodyScroll();
    }
  }

  /**
   * Opens the modal in create mode.
   */
  openCreate() {
    this._open(SessionProposalModal.FORM_MODE.CREATE, null);
  }

  /**
   * Opens the modal in edit mode.
   * @param {Object} proposal
   */
  openEdit(proposal) {
    this._open(SessionProposalModal.FORM_MODE.EDIT, proposal);
  }

  /**
   * Opens the modal in view mode.
   * @param {Object} proposal
   */
  openView(proposal) {
    this._open(SessionProposalModal.FORM_MODE.VIEW, proposal);
  }

  /**
   * Closes the modal.
   */
  close() {
    if (!this._isOpen) {
      return;
    }

    this._isOpen = false;
    this._mode = SessionProposalModal.FORM_MODE.CREATE;
    this._activeProposal = null;
    this._selectedCoSpeaker = null;
    this._removeAfterRequestListener();
    unlockBodyScroll();
  }

  /**
   * Syncs form state and co-speaker options when modal state changes.
   * @param {Map<string, unknown>} changedProperties
   */
  updated(changedProperties) {
    const hasModeChange =
      changedProperties.has("_isOpen") ||
      changedProperties.has("_mode") ||
      changedProperties.has("_activeProposal");

    if (this._isOpen && hasModeChange) {
      this._syncFormForMode();
      this._bindFormAfterRequest();
      this._setDescriptionReadOnly(this._isReadOnly());
    }

    if (this._isOpen && (hasModeChange || changedProperties.has("_selectedCoSpeaker"))) {
      this._syncCoSpeakerSearch();
    }
  }

  /**
   * Opens the modal and initializes state for the selected mode.
   * @param {string} mode
   * @param {Object|null} proposal
   */
  _open(mode, proposal) {
    const shouldLockScroll = !this._isOpen;
    this._mode = mode;
    this._activeProposal = proposal || null;
    this._selectedCoSpeaker = proposal?.co_speaker || null;
    this._isOpen = true;
    if (shouldLockScroll) {
      lockBodyScroll();
    }
  }

  /**
   * Closes the modal when Escape is pressed.
   * @param {KeyboardEvent} event
   */
  _onKeydown(event) {
    if (event.key === "Escape" && this._isOpen) {
      this.close();
    }
  }

  /**
   * Returns whether the form is in view-only mode.
   * @returns {boolean}
   */
  _isReadOnly() {
    return this._mode === SessionProposalModal.FORM_MODE.VIEW;
  }

  /**
   * Reads and parses level options from the component attribute once.
   */
  _loadLevelsFromAttribute() {
    const levelsAttr = this.getAttribute("session-proposal-levels");
    if (!levelsAttr || this._sessionProposalLevels.length > 0) {
      return;
    }

    try {
      const parsedLevels = JSON.parse(levelsAttr);
      if (Array.isArray(parsedLevels)) {
        this._sessionProposalLevels = parsedLevels;
      }
    } catch (error) {
      console.error("Invalid session proposal levels payload", error);
    }
  }

  /**
   * Builds the update endpoint for the active proposal.
   * @returns {string}
   */
  _buildUpdateEndpoint() {
    const sessionProposalId = this._activeProposal?.session_proposal_id;
    if (!sessionProposalId) {
      return "";
    }
    return `/dashboard/user/session-proposals/${sessionProposalId}`;
  }

  /**
   * Applies the form values and HTMX attributes based on active mode.
   */
  _syncFormForMode() {
    const form = this.querySelector("#session-proposal-form");
    if (!form) {
      return;
    }

    const proposal = this._activeProposal;
    const isCreate = this._mode === SessionProposalModal.FORM_MODE.CREATE;
    const isEdit = this._mode === SessionProposalModal.FORM_MODE.EDIT;

    if (isCreate) {
      form.reset();
      form.setAttribute("hx-post", "/dashboard/user/session-proposals");
      form.removeAttribute("hx-put");
      this._setFormFieldValues({
        title: "",
        session_proposal_level_id: "",
        duration_minutes: "",
        description: "",
      });
      this._selectedCoSpeaker = null;
    } else if (isEdit && proposal) {
      form.setAttribute("hx-put", this._buildUpdateEndpoint());
      form.removeAttribute("hx-post");
      this._setFormFieldValues(proposal);
    } else if (this._isReadOnly() && proposal) {
      form.removeAttribute("hx-post");
      form.removeAttribute("hx-put");
      this._setFormFieldValues(proposal);
    }

    if (window.htmx && typeof window.htmx.process === "function") {
      window.htmx.process(form);
    }
  }

  /**
   * Writes proposal values into form controls.
   * @param {Object|null} proposal
   */
  _setFormFieldValues(proposal) {
    const titleInput = this.querySelector("#session-proposal-title");
    const levelSelect = this.querySelector("#session-proposal-level");
    const durationInput = this.querySelector("#session-proposal-duration");

    if (titleInput) {
      titleInput.value = proposal?.title || "";
    }
    if (levelSelect) {
      levelSelect.value = proposal?.session_proposal_level_id || "";
    }
    if (durationInput) {
      durationInput.value = proposal?.duration_minutes ?? "";
    }

    this._syncDescriptionContent(proposal?.description || "");
  }

  /**
   * Syncs markdown editor value across textarea and CodeMirror.
   * @param {string} content
   */
  _syncDescriptionContent(content) {
    const editor = this.querySelector("markdown-editor#session-proposal-description");
    if (!editor) {
      return;
    }

    const textarea = editor.querySelector("textarea");
    if (textarea) {
      textarea.value = content;
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
    }

    const codeMirrorElement = editor.querySelector(".CodeMirror");
    const codeMirror = codeMirrorElement?.CodeMirror;
    if (codeMirror && typeof codeMirror.setValue === "function") {
      codeMirror.setValue(content);
    }
  }

  /**
   * Toggles read-only behavior in markdown editor controls.
   * @param {boolean} isReadOnly
   */
  _setDescriptionReadOnly(isReadOnly) {
    const editor = this.querySelector("markdown-editor#session-proposal-description");
    if (!editor) {
      return;
    }

    editor.disabled = isReadOnly;

    const toolbar = editor.querySelector(".editor-toolbar");
    if (toolbar) {
      toolbar.classList.toggle("pointer-events-none", isReadOnly);
      toolbar.classList.toggle("opacity-50", isReadOnly);
    }

    const codeMirrorElement = editor.querySelector(".CodeMirror");
    const codeMirror = codeMirrorElement?.CodeMirror;
    if (codeMirror && typeof codeMirror.setOption === "function") {
      codeMirror.setOption("readOnly", isReadOnly ? "nocursor" : false);
    }
    if (codeMirrorElement) {
      codeMirrorElement.classList.toggle("bg-stone-100", isReadOnly);
    }
  }

  /**
   * Updates excluded usernames in the co-speaker search field.
   */
  _syncCoSpeakerSearch() {
    const coSpeakerSearch = this.querySelector("#session-proposal-co-speaker-search");
    if (!coSpeakerSearch) {
      return;
    }

    coSpeakerSearch.excludeUsernames = this._selectedCoSpeaker ? [this._selectedCoSpeaker.username] : [];
  }

  /**
   * Binds form submit response handling to close modal on success.
   */
  _bindFormAfterRequest() {
    const form = this.querySelector("#session-proposal-form");
    if (!form) {
      return;
    }

    this._removeAfterRequestListener();
    this._afterRequestHandler = (event) => {
      const ok = handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to save this proposal. Please try again later.",
      });
      if (ok) {
        this.close();
      }
    };
    form.addEventListener("htmx:afterRequest", this._afterRequestHandler);
  }

  /**
   * Removes the HTMX after-request listener from the form.
   */
  _removeAfterRequestListener() {
    const form = this.querySelector("#session-proposal-form");
    if (!form || !this._afterRequestHandler) {
      this._afterRequestHandler = null;
      return;
    }
    form.removeEventListener("htmx:afterRequest", this._afterRequestHandler);
    this._afterRequestHandler = null;
  }

  /**
   * Stores selected co-speaker from the search component event.
   * @param {CustomEvent} event
   */
  _handleCoSpeakerSelected(event) {
    if (this._isReadOnly() || this._isCoSpeakerLocked()) {
      return;
    }

    const user = event.detail?.user;
    if (!user) {
      return;
    }

    this._selectedCoSpeaker = user;
  }

  /**
   * Clears the selected co-speaker from the form state.
   */
  _clearCoSpeaker() {
    if (this._isCoSpeakerLocked()) {
      return;
    }
    this._selectedCoSpeaker = null;
  }

  /**
   * Returns whether co-speaker changes are locked for the current proposal.
   * @returns {boolean}
   */
  _isCoSpeakerLocked() {
    return (
      this._mode === SessionProposalModal.FORM_MODE.EDIT && Boolean(this._activeProposal?.has_submissions)
    );
  }

  /**
   * Renders selected co-speaker preview in editable or read-only mode.
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult}
   */
  _renderCoSpeakerPreview() {
    if (!this._selectedCoSpeaker) {
      return html``;
    }

    const displayName = this._selectedCoSpeaker.name || this._selectedCoSpeaker.username;
    const isReadOnly = this._isReadOnly();
    const isCoSpeakerLocked = this._isCoSpeakerLocked();

    if (isReadOnly || isCoSpeakerLocked) {
      return html`
        <div class="inline-flex items-center gap-2 bg-stone-100 rounded-full px-3 py-1">
          <span class="text-sm text-stone-700">${displayName}</span>
        </div>
      `;
    }

    return html`
      <div class="inline-flex items-center gap-2 bg-stone-100 rounded-full px-3 py-1">
        <span class="text-sm text-stone-700">${displayName}</span>
        <button
          type="button"
          class="p-1 hover:bg-stone-200 rounded-full"
          aria-label="Remove co-speaker"
          @click=${this._clearCoSpeaker}
        >
          <div class="svg-icon size-3 icon-close bg-stone-600"></div>
        </button>
      </div>
    `;
  }

  /**
   * Resolves modal heading from active mode.
   * @returns {string}
   */
  _getModalTitle() {
    if (this._mode === SessionProposalModal.FORM_MODE.EDIT) {
      return "Edit session proposal";
    }
    if (this._mode === SessionProposalModal.FORM_MODE.VIEW) {
      return "Session proposal details";
    }
    return "New session proposal";
  }

  /**
   * Resolves submit button label for current mode.
   * @returns {string}
   */
  _getSubmitLabel() {
    return this._mode === SessionProposalModal.FORM_MODE.EDIT ? "Update" : "Save";
  }

  /**
   * Renders a badge row for a person.
   * @param {Object} person
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult}
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
   * Renders proposal metadata blocks.
   * @param {Object} proposal
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult}
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
   * Renders read-only proposal details.
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult}
   */
  _renderViewContent() {
    const proposal = this._activeProposal || {};
    const coSpeaker = proposal?.co_speaker;

    return html`
      <div class="px-8 py-5">
        <div class="flex flex-col md:flex-row gap-6">
          <div class="flex-1 space-y-4 min-w-0">
            <div>
              <div class=${PROPOSAL_SECTION_TITLE_CLASS}>Title</div>
              <div class="mt-2 text-lg text-stone-800 font-medium">${proposal?.title || ""}</div>
            </div>
            <div>
              <div class=${PROPOSAL_SECTION_TITLE_CLASS}>Description</div>
              <div class="mt-2 text-stone-700 text-sm/6 markdown">
                ${proposal?.description_html
                  ? unsafeHTML(proposal.description_html)
                  : proposal?.description || ""}
              </div>
            </div>
          </div>
          <div class="w-full md:w-72 shrink-0 space-y-4 md:border-l md:border-stone-100 md:pl-6">
            ${this._renderProposalMeta(proposal)}
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
        <div class="flex items-center justify-end gap-3 pt-3 mt-4 border-t border-stone-100">
          <button id="session-proposal-cancel" type="button" class="btn-primary-outline" @click=${this.close}>
            Close
          </button>
        </div>
      </div>
    `;
  }

  /**
   * Renders editable proposal form.
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult}
   */
  _renderFormContent() {
    const isCoSpeakerLocked = this._isCoSpeakerLocked();
    const showDeclinedCoSpeakerWarning =
      this._mode === SessionProposalModal.FORM_MODE.EDIT &&
      this._activeProposal?.session_proposal_status_id === "declined-by-co-speaker";
    const showPendingCoSpeakerWarning =
      this._mode === SessionProposalModal.FORM_MODE.EDIT &&
      this._activeProposal?.session_proposal_status_id === "pending-co-speaker-response";

    return html`
      <div class="p-4 md:p-6">
        <form
          id="session-proposal-form"
          hx-swap="none"
          hx-indicator="#dashboard-spinner"
          hx-disabled-elt="#session-proposal-submit, #session-proposal-cancel"
        >
          <div class="space-y-5">
            ${isCoSpeakerLocked
              ? html`
                  <div
                    role="status"
                    class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
                  >
                    This proposal has already been submitted. Co-speaker changes are disabled.
                  </div>
                `
              : ""}
            ${showDeclinedCoSpeakerWarning
              ? html`
                  <div
                    role="alert"
                    class="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900"
                  >
                    The invited co-speaker declined this proposal. Please update it before submitting.
                  </div>
                `
              : ""}
            ${showPendingCoSpeakerWarning
              ? html`
                  <div
                    role="status"
                    class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
                  >
                    This proposal is awaiting co-speaker invitation response.
                  </div>
                `
              : ""}
            <div>
              <label for="session-proposal-title" class="form-label">
                Title <span class="asterisk">*</span>
              </label>
              <div class="mt-2">
                <input
                  type="text"
                  id="session-proposal-title"
                  name="title"
                  maxlength=${this.titleMaxLength}
                  class="input-primary"
                  required
                />
              </div>
            </div>

            <div class="grid grid-cols-1 gap-x-6 gap-y-5 md:grid-cols-6">
              <div class="col-span-full md:col-span-3">
                <label for="session-proposal-level" class="form-label">
                  Level <span class="asterisk">*</span>
                </label>
                <div class="mt-2">
                  <select
                    id="session-proposal-level"
                    name="session_proposal_level_id"
                    class="select-primary"
                    required
                  >
                    <option value="">Select level</option>
                    ${this._sessionProposalLevels.map(
                      (level) =>
                        html`<option value=${level.session_proposal_level_id}>${level.display_name}</option>`,
                    )}
                  </select>
                </div>
              </div>
              <div class="col-span-full md:col-span-3">
                <label for="session-proposal-duration" class="form-label">
                  Duration (minutes) <span class="asterisk">*</span>
                </label>
                <div class="mt-2">
                  <input
                    type="number"
                    id="session-proposal-duration"
                    name="duration_minutes"
                    min="1"
                    max=${this.durationMax}
                    class="input-primary"
                    required
                  />
                </div>
                <p class="form-legend">Enter the session length in minutes (e.g. 45).</p>
              </div>
            </div>

            <div>
              <label class="form-label">Co-speaker</label>
              <input
                type="hidden"
                id="session-proposal-co-speaker"
                name="co_speaker_user_id"
                value=${this._selectedCoSpeaker?.user_id || ""}
                ?disabled=${!this._selectedCoSpeaker}
              />
              <user-search-field
                id="session-proposal-co-speaker-search"
                dashboard-type="user"
                label="co-speaker"
                legend="Search by username to add an optional co-speaker."
                ?disabled=${isCoSpeakerLocked}
                @user-selected=${this._handleCoSpeakerSelected}
              ></user-search-field>
              <div id="session-proposal-co-speaker-preview" class="mt-3">
                ${this._renderCoSpeakerPreview()}
              </div>
            </div>

            <div>
              <label class="form-label"> Description <span class="asterisk">*</span> </label>
              <div class="mt-2">
                <markdown-editor
                  id="session-proposal-description"
                  name="description"
                  maxlength=${this.descriptionMaxLength}
                  required
                ></markdown-editor>
              </div>
            </div>

            <div class="flex items-center justify-end gap-3">
              <button
                id="session-proposal-cancel"
                type="button"
                class="btn-primary-outline"
                @click=${this.close}
              >
                Cancel
              </button>
              <button id="session-proposal-submit" type="submit" class="btn-primary">
                ${this._getSubmitLabel()}
              </button>
            </div>
          </div>
        </form>
      </div>
    `;
  }

  render() {
    const isReadOnly = this._isReadOnly();
    const modalVisibilityClass = this._isOpen ? "flex" : "hidden";
    const widthClass = isReadOnly ? "max-w-5xl" : "max-w-2xl";

    return html`
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="session-proposal-modal-title"
        class="overflow-y-auto overflow-x-hidden fixed top-0 right-0 left-0 z-[1000] justify-center items-center w-full md:inset-0 max-h-full ${modalVisibilityClass}"
      >
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35]"
          @click=${this.close}
        ></div>
        <div class="relative p-4 w-full ${widthClass} max-h-full">
          <div class="relative bg-white rounded-lg shadow">
            <div class="flex items-center justify-between p-4 md:p-5 border-b border-stone-200 rounded-t">
              <h3 id="session-proposal-modal-title" class="text-xl font-semibold text-stone-900">
                ${this._getModalTitle()}
              </h3>
              <button
                type="button"
                class="group text-stone-400 bg-transparent hover:bg-stone-200 hover:text-stone-900 transition-colors rounded-lg text-sm w-8 h-8 ms-auto inline-flex justify-center items-center"
                @click=${this.close}
              >
                <div
                  class="svg-icon w-5 h-5 bg-stone-500 group-hover:bg-stone-900 transition-colors icon-close"
                ></div>
                <span class="sr-only">Close modal</span>
              </button>
            </div>
            ${isReadOnly ? this._renderViewContent() : this._renderFormContent()}
          </div>
        </div>
      </div>
    `;
  }
}

if (!customElements.get("session-proposal-modal")) {
  customElements.define("session-proposal-modal", SessionProposalModal);
}
