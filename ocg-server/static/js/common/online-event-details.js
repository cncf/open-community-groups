import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  validateMeetingRequest,
  MIN_MEETING_MINUTES,
  MAX_MEETING_MINUTES,
} from "/static/js/dashboard/group/meeting-validations.js";
import { showErrorAlert, showInfoAlert } from "/static/js/common/alerts.js";

/**
 * Online event details component for managing meeting information. Supports
 * manual URL entry and automatic meeting creation modes.
 * @extends LitWrapper
 */
export class OnlineEventDetails extends LitWrapper {
  static properties = {
    kind: { type: String },
    meetingJoinUrl: { type: String, attribute: "meeting-join-url" },
    meetingRecordingUrl: { type: String, attribute: "meeting-recording-url" },
    meetingRequested: { type: Boolean, attribute: "meeting-requested" },
    meetingRequiresPassword: {
      type: Boolean,
      attribute: "meeting-requires-password",
    },
    startsAt: { type: String, attribute: "starts-at" },
    endsAt: { type: String, attribute: "ends-at" },
    meetingInSync: { type: Boolean, attribute: "meeting-in-sync" },
    meetingPassword: { type: String, attribute: "meeting-password" },
    meetingError: { type: String, attribute: "meeting-error" },
    fieldNamePrefix: { type: String, attribute: "field-name-prefix" },
    meetingProviderId: { type: String, attribute: "meeting-provider-id" },

    _mode: { type: String, state: true },
    _joinUrl: { type: String, state: true },
    _recordingUrl: { type: String, state: true },
    _createMeeting: { type: Boolean, state: true },
    _requirePassword: { type: Boolean, state: true },
    _providerId: { type: String, state: true },
  };

  constructor() {
    super();
    this.kind = "virtual";
    this.meetingJoinUrl = "";
    this.meetingRecordingUrl = "";
    this.meetingRequested = false;
    this.meetingRequiresPassword = false;
    this.startsAt = "";
    this.endsAt = "";
    this.meetingInSync = false;
    this.meetingPassword = "";
    this.meetingError = "";
    this.fieldNamePrefix = "";
    this.meetingProviderId = "zoom";

    this._mode = "manual";
    this._joinUrl = "";
    this._recordingUrl = "";
    this._createMeeting = false;
    this._requirePassword = false;
    this._providerId = "zoom";
  }

  connectedCallback() {
    super.connectedCallback();

    if (this.meetingRequested) {
      this._mode = "automatic";
    } else if (this.meetingJoinUrl || this.meetingRecordingUrl) {
      this._mode = "manual";
    } else {
      this._mode = "manual";
    }

    this._joinUrl = this.meetingJoinUrl || "";
    this._recordingUrl = this.meetingRecordingUrl || "";
    this._createMeeting = this.meetingRequested || false;
    this._requirePassword = this.meetingRequiresPassword || false;
    this._providerId = this.meetingProviderId || "zoom";
  }

  updated(changedProperties) {
    if (changedProperties.has("kind") && this.kind === "in-person") {
      if (this._mode === "automatic" && this._createMeeting) {
        this._mode = "manual";
        this._createMeeting = false;
        this._requirePassword = false;
        showInfoAlert(
          "Automatic meetings can only be created for virtual or hybrid events. The event has been switched to manual mode.",
        );
      }
    }

    if (
      (changedProperties.has("startsAt") ||
        changedProperties.has("endsAt") ||
        changedProperties.has("kind")) &&
      this._mode === "automatic"
    ) {
      const availability = this._getAutomaticAvailability();
      if (!availability.allowed) {
        this._mode = "manual";
        this._createMeeting = false;
        this._requirePassword = false;
        this._joinUrl = "";
        showInfoAlert(
          availability.reason || "Automatic meetings are disabled until the schedule requirements are met.",
        );
      }
    }
  }

  /**
   * Gets the form field name with optional prefix for session arrays.
   * @param {string} fieldName - Base field name
   * @returns {string} Prefixed field name if prefix exists, otherwise base name
   */
  _getFieldName(fieldName) {
    return this.fieldNamePrefix ? `${this.fieldNamePrefix}[${fieldName}]` : fieldName;
  }

  /**
   * Shows confirmation dialog when switching from automatic to manual mode.
   * @returns {Promise<boolean>} True if user confirms, false if cancelled
   */
  async _confirmModeSwitch() {
    const result = await Swal.fire({
      text: "Switching to manual mode will delete the automatically created meeting. This action cannot be undone. Do you want to continue?",
      icon: "warning",
      showCancelButton: true,
      confirmButtonText: "Yes, switch to manual",
      cancelButtonText: "No, keep automatic",
      position: "center",
      backdrop: true,
      buttonsStyling: false,
      iconColor: "var(--color-primary-500)",
      customClass: {
        popup: "pb-10! pt-5! px-0! rounded-lg! max-w-[100%] md:max-w-[400px]! shadow-lg!",
        confirmButton: "btn-primary",
        cancelButton: "btn-primary-outline ms-5",
      },
    });
    return result.isConfirmed;
  }

  /**
   * Shows confirmation dialog when switching from manual to automatic mode.
   * @returns {Promise<boolean>} True if user confirms, false if cancelled
   */
  async _confirmManualToAutomaticSwitch() {
    const result = await Swal.fire({
      text: "Switching to automatic mode will replace the current meeting link. Do you want to continue?",
      icon: "warning",
      showCancelButton: true,
      confirmButtonText: "Yes, switch to automatic",
      cancelButtonText: "No, keep manual",
      position: "center",
      backdrop: true,
      buttonsStyling: false,
      iconColor: "var(--color-primary-500)",
      customClass: {
        popup: "pb-10! pt-5! px-0! rounded-lg! max-w-[100%] md:max-w-[400px]! shadow-lg!",
        confirmButton: "btn-primary",
        cancelButton: "btn-primary-outline ms-5",
      },
    });
    return result.isConfirmed;
  }

  /**
   * Renders a selectable mode card.
   * @param {object} option Card data
   * @returns {import('lit').TemplateResult} Mode card element
   */
  _renderModeOption(option) {
    const isSelected = this._mode === option.value;
    const cardClasses = [
      "h-full rounded-xl border transition bg-white",
      "p-4 md:p-5 flex",
      isSelected ? "border-primary-400 ring-2 ring-primary-200" : "border-stone-200",
      option.disabled ? "opacity-60 cursor-not-allowed" : "hover:border-primary-300",
    ].join(" ");

    return html`
      <label class="block h-full">
        <input
          type="radio"
          class="sr-only"
          value="${option.value}"
          .checked="${isSelected}"
          ?disabled="${option.disabled}"
          @change="${this._handleModeChange}"
        />
        <div class="${cardClasses}">
          <div class="flex items-start gap-3">
            <span class="mt-1 inline-flex">
              <span
                class="${[
                  "relative flex h-5 w-5 items-center justify-center rounded-full",
                  "border",
                  isSelected ? "border-primary-500" : "border-stone-300",
                ].join(" ")}"
              >
                ${isSelected ? html`<span class="h-2.5 w-2.5 rounded-full bg-primary-500"></span>` : ""}
              </span>
            </span>
            <div class="space-y-1">
              <div class="text-base font-semibold text-stone-900">${option.title}</div>
              <p class="text-sm text-stone-600 leading-relaxed">${option.description}</p>
              ${option.helper
                ? html`<p class="text-sm text-amber-700 leading-relaxed">${option.helper}</p>`
                : ""}
            </div>
          </div>
        </div>
      </label>
    `;
  }

  /**
   * Handles radio button change for mode selection.
   * @param {Event} e - Change event from radio input
   */
  async _handleModeChange(e) {
    const newMode = e.target.value;

    if (newMode === this._mode) {
      return;
    }

    if (newMode === "manual" && this._mode === "automatic") {
      const meetingExists = this.meetingInSync || (this._createMeeting && this.meetingJoinUrl);

      if (meetingExists) {
        const confirmed = await this._confirmModeSwitch();
        if (!confirmed) {
          this.requestUpdate();
          return;
        }
      }

      this._mode = "manual";
      this._createMeeting = false;
      this._requirePassword = false;
    } else if (newMode === "automatic" && this._mode === "manual") {
      if (this.meetingInSync) {
        const confirmed = await this._confirmManualToAutomaticSwitch();
        if (!confirmed) {
          this.requestUpdate();
          return;
        }
      }
      this._mode = "automatic";
      this._joinUrl = "";
      this._recordingUrl = "";
      this._createMeeting = true;
    } else {
      this._mode = newMode;
    }

    this.requestUpdate();
  }

  /**
   * Handles toggle change for create meeting.
   * @param {Event} e - Change event from toggle input
   */
  _handleCreateMeetingChange(e) {
    e.stopPropagation();
    this._createMeeting = e.target.checked;
    if (!this._createMeeting) {
      this._requirePassword = false;
    }
  }

  /**
   * Handles toggle change for require password.
   * @param {Event} e - Change event from toggle input
   */
  _handleRequirePasswordChange(e) {
    this._requirePassword = e.target.checked;
  }

  /**
   * Handles input change for meeting URL.
   * @param {Event} e - Input event
   */
  _handleJoinUrlChange(e) {
    this._joinUrl = e.target.value;
  }

  /**
   * Handles input change for recording URL.
   * @param {Event} e - Input event
   */
  _handleRecordingUrlChange(e) {
    this._recordingUrl = e.target.value;
  }

  _getAutomaticAvailability() {
    const isVirtualOrHybrid = this.kind === "virtual" || this.kind === "hybrid";
    if (!isVirtualOrHybrid) {
      return {
        allowed: false,
        reason: "Automatic meetings are only available for virtual or hybrid events.",
      };
    }

    if (!this.startsAt || !this.endsAt) {
      return {
        allowed: false,
        reason: "Set start and end times to enable automatic meetings.",
      };
    }

    const startDate = new Date(this.startsAt);
    const endDate = new Date(this.endsAt);

    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
      return {
        allowed: false,
        reason: "Provide valid start and end times to enable automatic meetings.",
      };
    }

    const durationMinutes = (endDate - startDate) / 60000;

    if (!Number.isFinite(durationMinutes) || durationMinutes <= 0) {
      return {
        allowed: false,
        reason: "End time must be after the start time for automatic meetings.",
      };
    }

    if (durationMinutes < MIN_MEETING_MINUTES || durationMinutes > MAX_MEETING_MINUTES) {
      return {
        allowed: false,
        reason: `Duration must be between ${MIN_MEETING_MINUTES} and ${MAX_MEETING_MINUTES} minutes.`,
      };
    }

    return { allowed: true, reason: "" };
  }

  /**
   * Validates automatic meeting request if enabled.
   * @param {Function} displaySection - Optional callback to switch to date-venue section
   * @returns {boolean} True if valid or not in automatic mode, false otherwise
   */
  validate(displaySection = null) {
    if (this._mode !== "automatic" || !this._createMeeting) {
      return true;
    }

    return validateMeetingRequest({
      requested: true,
      kindValue: this.kind,
      startsAtValue: this.startsAt,
      endsAtValue: this.endsAt,
      showError: showErrorAlert,
      displaySection,
    });
  }

  /**
   * Resets component to initial manual mode state.
   */
  reset() {
    this._mode = "manual";
    this._joinUrl = "";
    this._recordingUrl = "";
    this._createMeeting = false;
    this._requirePassword = false;
    this._providerId = "zoom";
    this.requestUpdate();
  }

  /**
   * Renders hidden inputs for form submission.
   * @returns {import('lit').TemplateResult} Hidden input elements
   */
  _renderHiddenInputs() {
    const isAutomatic = this._mode === "automatic" && this._createMeeting;
    const joinUrlValue = isAutomatic ? "" : (this._joinUrl || "").trim();
    const recordingUrlValue = (this._recordingUrl || "").trim();
    const providerIdValue = isAutomatic ? (this._providerId || "").trim() : "";

    return html`
      <input
        type="hidden"
        name="${this._getFieldName("meeting_join_url")}"
        value="${joinUrlValue}"
        ?disabled="${joinUrlValue === ""}"
      />
      <input
        type="hidden"
        name="${this._getFieldName("meeting_recording_url")}"
        value="${recordingUrlValue}"
        ?disabled="${recordingUrlValue === ""}"
      />
      <input type="hidden" name="${this._getFieldName("meeting_requested")}" value="${isAutomatic}" />
      <input
        type="hidden"
        name="${this._getFieldName("meeting_requires_password")}"
        value="${isAutomatic && this._requirePassword}"
      />
      <input
        type="hidden"
        name="${this._getFieldName("meeting_provider_id")}"
        value="${providerIdValue}"
        ?disabled="${!isAutomatic || providerIdValue === ""}"
      />
    `;
  }

  /**
   * Renders meeting status display for update forms.
   * @returns {import('lit').TemplateResult} Status display or empty template
   */
  _renderMeetingStatus() {
    const shouldShowPending = this._mode === "automatic" && this._createMeeting && !this.meetingInSync;
    const hasMeetingDetails =
      this.meetingInSync || this.meetingPassword || this.meetingError || this.meetingJoinUrl;
    const showPendingMessage =
      !this.meetingInSync && !this.meetingJoinUrl && !this.meetingPassword && !this.meetingError;

    if (!shouldShowPending && !hasMeetingDetails) {
      return html``;
    }

    return html`
      <div class="rounded-lg border border-stone-200 bg-white p-4 space-y-2 mt-4">
        <div class="flex items-center gap-3">
          ${this.meetingInSync
            ? html`
                <div class="svg-icon size-4 bg-emerald-500 icon-check"></div>
                <span class="text-sm font-medium text-emerald-700">Meeting synced</span>
              `
            : html`
                <div class="svg-icon size-4 bg-amber-500 icon-warning"></div>
                <span class="text-sm font-medium text-amber-700">Meeting not synced yet</span>
              `}
        </div>

        ${showPendingMessage
          ? html`
              <p class="text-sm text-stone-700">We requested the meeting; syncing may take a few minutes.</p>
            `
          : ""}
        ${this.meetingJoinUrl
          ? html`
              <div class="text-sm text-stone-700 break-words">
                <span class="font-medium">Join link:</span>
                <a
                  href="${this.meetingJoinUrl}"
                  class="text-primary-500 hover:text-primary-600 break-words"
                  target="_blank"
                  rel="noopener noreferrer"
                  >${this.meetingJoinUrl}</a
                >
              </div>
            `
          : ""}
        ${this.meetingPassword
          ? html`
              <div class="text-sm text-stone-700">
                <span class="font-medium">Password:</span>
                <code class="ml-2 px-2 py-0.5 bg-stone-100 rounded text-stone-800"
                  >${this.meetingPassword}</code
                >
              </div>
            `
          : ""}
        ${this.meetingError
          ? html`
              <div class="text-sm text-red-700 bg-red-50 border border-red-100 rounded p-3">
                ${this.meetingError}
              </div>
            `
          : ""}
      </div>
    `;
  }

  /**
   * Renders manual mode fields (meeting and recording URLs).
   * @returns {import('lit').TemplateResult} Manual mode field elements
   */
  _renderManualFields() {
    return html`
      <div class="space-y-2">
        <label for="${this._getFieldName("meeting_join_url")}" class="form-label">Meeting URL</label>
        <div class="mt-2">
          <input
            type="url"
            id="${this._getFieldName("meeting_join_url")}"
            class="input-primary"
            placeholder="https://meet.example.com/123456789"
            .value="${this._joinUrl}"
            @input="${this._handleJoinUrlChange}"
          />
        </div>
        <p class="form-legend">Teams, Meet, or any other video link.</p>
      </div>

      <div class="space-y-2">
        <label for="${this._getFieldName("meeting_recording_url")}" class="form-label"
          >Recording URL (optional)</label
        >
        <div class="mt-2">
          <input
            type="url"
            id="${this._getFieldName("meeting_recording_url")}"
            class="input-primary"
            placeholder="https://youtube.com/watch?v=..."
            .value="${this._recordingUrl}"
            @input="${this._handleRecordingUrlChange}"
          />
        </div>
        <p class="form-legend">Add a recording link now or after the event.</p>
      </div>
    `;
  }

  /**
   * Renders automatic mode fields (create meeting and password toggles).
   * @returns {import('lit').TemplateResult} Automatic mode field elements
   */
  _renderAutomaticFields() {
    return html`
      <div class="space-y-4 rounded-xl border border-stone-200 bg-white p-4 md:col-span-2">
        <div class="flex items-start justify-between gap-4">
          <div class="space-y-1">
            <div class="text-base font-semibold text-stone-900">Create meeting automatically</div>
            <p class="text-sm text-stone-600 leading-relaxed">
              We will create and manage the meeting when you save this event.
            </p>
            <ul class="list-disc pl-5 space-y-1 text-sm text-stone-600 leading-relaxed">
              <li>Only available for virtual or hybrid events.</li>
              <li>
                Requires start and end times between ${MIN_MEETING_MINUTES} and ${MAX_MEETING_MINUTES}
                minutes.
              </li>
              <li>Manual links cannot be set while automatic creation is on.</li>
            </ul>
          </div>
          <label class="inline-flex items-center cursor-pointer">
            <input
              type="checkbox"
              class="sr-only peer"
              .checked="${this._createMeeting}"
              @change="${this._handleCreateMeetingChange}"
            />
            <div
              class="relative w-11 h-6 bg-stone-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-stone-300 after:border after:border-stone-200 after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-500"
            ></div>
          </label>
        </div>

        ${this._createMeeting
          ? html`
              <div class="rounded-lg border border-stone-100 bg-stone-50 p-3 space-y-2">
                <div class="space-y-2">
                  <label class="form-label text-sm font-medium text-stone-900">Meeting provider</label>
                  <select
                    class="input-primary"
                    @change="${(e) => (this._providerId = e.target.value || "zoom")}"
                  >
                    <option value="zoom" .selected="${this._providerId === "zoom"}">Zoom</option>
                  </select>
                </div>
                <div class="flex items-center justify-between gap-3 mt-3">
                  <div>
                    <div class="text-sm font-medium text-stone-900">Require meeting password</div>
                    <p class="text-sm text-stone-600 leading-relaxed">
                      Add password protection for attendees.
                    </p>
                  </div>
                  <label class="inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      class="sr-only peer"
                      .checked="${this._requirePassword}"
                      @change="${this._handleRequirePasswordChange}"
                    />
                    <div
                      class="relative w-11 h-6 bg-stone-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-stone-300 after:border after:border-stone-200 after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-500"
                    ></div>
                  </label>
                </div>
              </div>
            `
          : ""}
      </div>
    `;
  }

  /**
   * Renders the main component template.
   * @returns {import('lit').TemplateResult} Component template
   */
  render() {
    const availability = this._getAutomaticAvailability();
    const modeOptions = [
      {
        value: "manual",
        title: "Use my own meeting link",
        description: "Paste a Teams, Meet, or other link.",
        helper: "",
        disabled: false,
      },
      {
        value: "automatic",
        title: "Create meeting automatically",
        description: "We will create and manage a meeting when you save this event.",
        helper: availability.allowed ? "" : availability.reason,
        disabled: !availability.allowed,
      },
    ];

    return html`
      ${this._renderHiddenInputs()}

      <div class="space-y-6 max-w-5xl">
        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          ${modeOptions.map((option) => this._renderModeOption(option))}
        </div>

        <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
          ${this._mode === "manual" ? this._renderManualFields() : this._renderAutomaticFields()}
        </div>

        ${this._mode === "automatic" ? this._renderMeetingStatus() : ""}
      </div>
    `;
  }
}
if (!customElements.get("online-event-details")) {
  customElements.define("online-event-details", OnlineEventDetails);
}
