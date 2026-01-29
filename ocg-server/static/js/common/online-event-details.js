import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  validateMeetingRequest,
  MIN_MEETING_MINUTES,
  MAX_MEETING_MINUTES,
} from "/static/js/dashboard/group/meeting-validations.js";
import { showErrorAlert, showInfoAlert } from "/static/js/common/alerts.js";
import "/static/js/common/multiple-inputs.js";

const DEFAULT_MEETING_PROVIDER = "zoom";

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
    meetingHosts: {
      type: Array,
      attribute: "meeting-hosts",
      converter: {
        fromAttribute: (value) => {
          if (!value || value.trim() === "") return [];
          try {
            return JSON.parse(value);
          } catch {
            return [];
          }
        },
      },
    },
    startsAt: { type: String, attribute: "starts-at" },
    endsAt: { type: String, attribute: "ends-at" },
    meetingInSync: { type: Boolean, attribute: "meeting-in-sync" },
    meetingPassword: { type: String, attribute: "meeting-password" },
    meetingError: { type: String, attribute: "meeting-error" },
    fieldNamePrefix: { type: String, attribute: "field-name-prefix" },
    meetingProviderId: { type: String, attribute: "meeting-provider-id" },
    meetingMaxParticipants: {
      type: Object,
      attribute: "meeting-max-participants",
      converter: {
        fromAttribute: (value) => {
          if (!value) return {};
          try {
            return JSON.parse(value);
          } catch (e) {
            console.warn("Failed to parse meeting-max-participants", e);
            return {};
          }
        },
      },
    },
    _mode: { type: String, state: true },
    _joinUrl: { type: String, state: true },
    _recordingUrl: { type: String, state: true },
    _createMeeting: { type: Boolean, state: true },
    _providerId: { type: String, state: true },
    _hosts: { type: Array, state: true },
    _capacityWarning: { type: String, state: true },
    disabled: { type: Boolean },
  };

  constructor() {
    super();
    this.kind = "virtual";
    this.meetingJoinUrl = "";
    this.meetingRecordingUrl = "";
    this.meetingRequested = false;
    this.meetingHosts = [];
    this.startsAt = "";
    this.endsAt = "";
    this.meetingInSync = false;
    this.meetingPassword = "";
    this.meetingError = "";
    this.fieldNamePrefix = "";
    this.meetingProviderId = DEFAULT_MEETING_PROVIDER;
    this.meetingMaxParticipants = {};

    this._mode = "manual";
    this._joinUrl = "";
    this._recordingUrl = "";
    this._createMeeting = false;
    this._providerId = DEFAULT_MEETING_PROVIDER;
    this._hosts = [];
    this._capacityWarning = "";
    this.disabled = false;
  }

  connectedCallback() {
    super.connectedCallback();

    // Initialize state from attributes
    this._joinUrl = this.meetingJoinUrl || "";
    this._recordingUrl = this.meetingRecordingUrl || "";
    this._createMeeting = this.meetingRequested;
    this._providerId = this.meetingProviderId || DEFAULT_MEETING_PROVIDER;
    this._hosts = Array.isArray(this.meetingHosts) ? [...this.meetingHosts] : [];

    // Determine mode based on meeting state
    if (this.meetingRequested || this.meetingInSync) {
      this._mode = "automatic";
    } else {
      this._mode = "manual";
    }

    const capacityField = document.getElementById("capacity");
    capacityField?.addEventListener("input", () => {
      this._checkMeetingCapacity();
      this.requestUpdate();
    });
    this._checkMeetingCapacity();
  }

  /**
   * Called after first render to initialize sub-components.
   */
  firstUpdated() {
    this._initializeHostsInput();
  }

  updated(changedProperties) {
    // Reinitialize hosts input when switching to automatic mode or when create meeting is toggled
    if (changedProperties.has("_mode") || changedProperties.has("_createMeeting")) {
      if (this._mode === "automatic" && this._createMeeting) {
        // Wait for next render cycle to ensure the input element exists
        setTimeout(() => this._initializeHostsInput(), 0);
      }
      this._checkMeetingCapacity();
    }
  }

  /**
   * Initializes the meeting hosts input component with existing data.
   * @private
   */
  _initializeHostsInput() {
    const hostsInput = this.renderRoot.querySelector("#meeting-hosts-input");

    if (hostsInput && this._hosts.length > 0) {
      // Convert plain string array to the format MultipleInputs expects: {id, value}
      const formattedItems = this._hosts.map((host, index) => ({
        id: index,
        value: host,
      }));
      hostsInput.items = formattedItems;
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
   * Checks if the component is being used in a session context.
   * @returns {boolean} True if used for a session, false for a full event.
   * @private
   */
  _isSession() {
    return this.fieldNamePrefix.startsWith("sessions");
  }

  /**
   * Returns the appropriate legend text for the meeting hosts input based on
   * whether this is a session or full event context.
   * @returns {string} Legend text explaining default meeting hosts behavior.
   * @private
   */
  _getMeetingHostsLegend() {
    if (this._isSession()) {
      return "By default, hosts and session speakers are added as meeting hosts. Add additional emails here if their meeting provider email differs from their user email (optional).";
    }
    return "By default, hosts and event speakers are added as meeting hosts. Add additional emails here if their meeting provider email differs from their user email (optional).";
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
   * Shows confirmation dialog when a change would disable automatic meetings.
   * @returns {Promise<boolean>} True if user confirms, false if cancelled
   */
  async _confirmAutomaticDisable() {
    const result = await Swal.fire({
      text: "This change will disable automatic meeting creation. Do you want to continue?",
      icon: "warning",
      showCancelButton: true,
      confirmButtonText: "Yes, disable automatic",
      cancelButtonText: "No, keep settings",
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
   * Checks if confirmation is needed before disabling automatic meetings.
   * @returns {boolean} True if meeting is synced or hosts were added
   */
  _needsDisableConfirmation() {
    return this._mode === "automatic" && (this.meetingInSync || this._hosts.length > 0);
  }

  /**
   * Emits event when user cancels a change that would disable automatic meetings.
   * @param {string} property - The property that triggered the conflict
   */
  _emitMeetingModeConflict(property) {
    this.dispatchEvent(
      new CustomEvent("meeting-mode-conflict", {
        bubbles: true,
        composed: true,
        detail: { property },
      }),
    );
  }

  /**
   * Disables automatic meeting mode and switches to manual.
   */
  _disableAutomaticMode() {
    this._mode = "manual";
    this._createMeeting = false;
  }

  /**
   * Tries to set event kind, showing confirmation if it would disable automatic meetings.
   * @param {string} value - The new kind value
   * @returns {Promise<boolean>} True if the change was accepted
   */
  async trySetKind(value) {
    if (this.disabled) {
      return false;
    }
    const wouldDisable = value === "in-person" && this._mode === "automatic" && this._createMeeting;

    if (wouldDisable && this._needsDisableConfirmation()) {
      const confirmed = await this._confirmAutomaticDisable();
      if (!confirmed) {
        this._emitMeetingModeConflict("kind");
        return false;
      }
      this._disableAutomaticMode();
    } else if (wouldDisable) {
      this._disableAutomaticMode();
    }

    this.kind = value;
    return true;
  }

  /**
   * Tries to set start time, showing confirmation if it would disable automatic meetings.
   * @param {string} value - The new startsAt value
   * @returns {Promise<boolean>} True if the change was accepted
   */
  async trySetStartsAt(value) {
    if (this.disabled) {
      return false;
    }
    const wouldDisable = this._wouldScheduleChangeDisableAutomatic(value, this.endsAt);

    if (wouldDisable && this._needsDisableConfirmation()) {
      const confirmed = await this._confirmAutomaticDisable();
      if (!confirmed) {
        this._emitMeetingModeConflict("startsAt");
        return false;
      }
      this._disableAutomaticMode();
    } else if (wouldDisable) {
      this._disableAutomaticMode();
    }

    this.startsAt = value;
    return true;
  }

  /**
   * Tries to set end time, showing confirmation if it would disable automatic meetings.
   * @param {string} value - The new endsAt value
   * @returns {Promise<boolean>} True if the change was accepted
   */
  async trySetEndsAt(value) {
    if (this.disabled) {
      return false;
    }
    const wouldDisable = this._wouldScheduleChangeDisableAutomatic(this.startsAt, value);

    if (wouldDisable && this._needsDisableConfirmation()) {
      const confirmed = await this._confirmAutomaticDisable();
      if (!confirmed) {
        this._emitMeetingModeConflict("endsAt");
        return false;
      }
      this._disableAutomaticMode();
    } else if (wouldDisable) {
      this._disableAutomaticMode();
    }

    this.endsAt = value;
    return true;
  }

  /**
   * Checks if a schedule change would make automatic meetings unavailable.
   * @param {string} startsAt - The start time value
   * @param {string} endsAt - The end time value
   * @returns {boolean} True if the change would disable automatic meetings
   */
  _wouldScheduleChangeDisableAutomatic(startsAt, endsAt) {
    if (this._mode !== "automatic" || !this._createMeeting) {
      return false;
    }

    const isVirtualOrHybrid = this.kind === "virtual" || this.kind === "hybrid";
    if (!isVirtualOrHybrid) {
      return true;
    }

    if (!startsAt || !endsAt) {
      return true;
    }

    const startDate = new Date(startsAt);
    const endDate = new Date(endsAt);

    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
      return true;
    }

    const durationMinutes = (endDate - startDate) / 60000;

    if (!Number.isFinite(durationMinutes) || durationMinutes <= 0) {
      return true;
    }

    if (durationMinutes < MIN_MEETING_MINUTES || durationMinutes > MAX_MEETING_MINUTES) {
      return true;
    }

    return false;
  }

  /**
   * Renders a selectable mode card.
   * @param {object} option Card data
   * @returns {import('lit').TemplateResult} Mode card element
   */
  _renderModeOption(option) {
    const isSelected = this._mode === option.value;
    const isDisabled = this.disabled || option.disabled;

    return html`
      <label class="block h-full">
        <input
          type="radio"
          class="sr-only"
          value="${option.value}"
          .checked="${isSelected}"
          ?disabled="${isDisabled}"
          @change="${this._handleModeChange}"
        />
        <div
          class="h-full rounded-xl border transition bg-white p-4 md:p-5 flex ${isSelected
            ? "border-primary-400 ring-2 ring-primary-200"
            : "border-stone-200"} ${isDisabled
            ? "opacity-60 cursor-not-allowed"
            : "hover:border-primary-300"}"
        >
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
              <p class="form-legend">${option.description}</p>
              ${option.reasons && option.reasons.length > 0
                ? html`
                    <ul class="list-disc list-inside form-legend mt-2">
                      ${option.reasons.map((r) => html`<li>${r}</li>`)}
                    </ul>
                  `
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
    if (this.disabled) {
      e.preventDefault();
      return;
    }
    const newMode = e.target.value;

    if (newMode === this._mode) {
      return;
    }

    if (newMode === "manual" && this._mode === "automatic") {
      // Only ask for confirmation if meeting was actually synced (exists in Zoom)
      if (this.meetingInSync) {
        const confirmed = await this._confirmModeSwitch();
        if (!confirmed) {
          this.requestUpdate();
          return;
        }
      } else if (this._needsDisableConfirmation()) {
        const confirmed = await this._confirmAutomaticDisable();
        if (!confirmed) {
          this.requestUpdate();
          return;
        }
      }

      this._mode = "manual";
      this._createMeeting = false;
    } else if (newMode === "automatic" && this._mode === "manual") {
      const availability = this._getAutomaticAvailability();
      if (!availability.allowed) {
        showInfoAlert(availability.reasons[0] || "Cannot enable automatic meetings.");
        this.requestUpdate();
        return;
      }

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
   * Handles input change for meeting URL.
   * @param {Event} e - Input event
   */
  _handleJoinUrlChange(e) {
    if (this.disabled) return;
    this._joinUrl = e.target.value;
  }

  /**
   * Handles input change for recording URL.
   * @param {Event} e - Input event
   */
  _handleRecordingUrlChange(e) {
    if (this._isSession()) return;
    this._recordingUrl = e.target.value;
  }

  _getAutomaticAvailability() {
    if (this.disabled) {
      return { allowed: false, reasons: [] };
    }

    const reasons = [];

    const isVirtualOrHybrid = this.kind === "virtual" || this.kind === "hybrid";
    if (!isVirtualOrHybrid) {
      reasons.push("Event must be virtual or hybrid.");
    }

    if (!this.startsAt || !this.endsAt) {
      reasons.push("Set start and end times.");
    } else {
      const startDate = new Date(this.startsAt);
      const endDate = new Date(this.endsAt);

      if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
        reasons.push("Provide valid start and end times.");
      } else {
        const durationMinutes = (endDate - startDate) / 60000;
        if (!Number.isFinite(durationMinutes) || durationMinutes <= 0) {
          reasons.push("End time must be after start time.");
        } else if (durationMinutes < MIN_MEETING_MINUTES || durationMinutes > MAX_MEETING_MINUTES) {
          reasons.push(`Duration must be ${MIN_MEETING_MINUTES}-${MAX_MEETING_MINUTES} minutes.`);
        }
      }
    }

    const capacityValue = this._getCapacityValue();
    if (!Number.isFinite(capacityValue) || capacityValue <= 0) {
      reasons.push("Set event capacity.");
    } else {
      const capacityLimit = this._getCapacityLimit();
      if (Number.isFinite(capacityLimit) && capacityValue > capacityLimit) {
        reasons.push(`Capacity exceeds meeting limit (${capacityLimit}).`);
      }
    }

    return { allowed: reasons.length === 0, reasons };
  }

  /**
   * Validates automatic meeting request if enabled.
   * @param {Function} displaySection - Optional callback to switch to date-venue section
   * @returns {boolean} True if valid or not in automatic mode, false otherwise
   */
  validate(displaySection = null) {
    if (!this._isAutomaticMeetingActive()) {
      return true;
    }

    return validateMeetingRequest({
      requested: true,
      kindValue: this.kind,
      startsAtValue: this.startsAt,
      endsAtValue: this.endsAt,
      capacityValue: this._getCapacityValue(),
      capacityLimit: this._getCapacityLimit(),
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
    this._providerId = DEFAULT_MEETING_PROVIDER;
    this._hosts = [];
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
      <input type="hidden" name="${this._getFieldName("meeting_join_url")}" value="${joinUrlValue}" />
      <input
        type="hidden"
        name="${this._getFieldName("meeting_recording_url")}"
        value="${recordingUrlValue}"
      />
      <input type="hidden" name="${this._getFieldName("meeting_requested")}" value="${isAutomatic}" />
      <input type="hidden" name="${this._getFieldName("meeting_provider_id")}" value="${providerIdValue}" />
    `;
  }

  _getCapacityValue() {
    const capacityField = document.getElementById("capacity");
    const value = parseInt(capacityField?.value, 10);
    return Number.isFinite(value) ? value : null;
  }

  _getCapacityLimit() {
    if (!this.meetingMaxParticipants || typeof this.meetingMaxParticipants !== "object") {
      return null;
    }

    const providerKey = (this._providerId || DEFAULT_MEETING_PROVIDER).toLowerCase();
    const limit = this.meetingMaxParticipants[providerKey];
    const parsedLimit = parseInt(limit, 10);

    if (Number.isFinite(parsedLimit) && parsedLimit > 0) {
      return parsedLimit;
    }

    return null;
  }

  _checkMeetingCapacity() {
    if (!this._isAutomaticMeetingActive()) {
      this._capacityWarning = "";
      return;
    }

    const capacityValue = this._getCapacityValue();

    const capacityLimit = this._getCapacityLimit();

    if (Number.isFinite(capacityLimit) && Number.isFinite(capacityValue) && capacityValue > capacityLimit) {
      this._capacityWarning = `Capacity (${capacityValue}) exceeds the configured meeting participant limit (${capacityLimit}). Ensure your meeting provider supports this many participants.`;
      return;
    }

    this._capacityWarning = "";
  }

  /**
   * Determines if automatic meeting features are active for validation.
   * @returns {boolean} True when in automatic mode with a requested or synced meeting.
   */
  _isAutomaticMeetingActive() {
    return this._mode === "automatic" && (this._createMeeting || this.meetingInSync);
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
              <p class="text-sm text-stone-700">
                We've requested a meeting for this event. The meeting details (join link and password) will
                appear here once synced, which usually takes a few minutes.
              </p>
            `
          : ""}
        ${this.meetingJoinUrl
          ? html`
              <div class="text-sm text-stone-700 wrap-break-word">
                <span class="font-medium">Join link:</span>
                <a
                  href="${this.meetingJoinUrl}"
                  class="text-primary-500 hover:text-primary-600 wrap-break-word"
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
    const disabledClasses = this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : "";
    const recordingDisabled = this._isSession() && this.disabled;
    return html`
      <div class="space-y-2">
        <label for="${this._getFieldName("meeting_join_url")}" class="form-label">Meeting URL</label>
        <div class="mt-2">
          <input
            type="url"
            id="${this._getFieldName("meeting_join_url")}"
            class="input-primary ${disabledClasses}"
            placeholder="https://meet.example.com/123456789"
            .value="${this._joinUrl}"
            @input="${this._handleJoinUrlChange}"
            ?disabled=${this.disabled}
          />
        </div>
        <p class="form-legend">Zoom, Teams, Meet, or any other video link.</p>
      </div>

      <div class="space-y-2">
        <label for="${this._getFieldName("meeting_recording_url")}" class="form-label"
          >Recording URL (optional)</label
        >
        <div class="mt-2">
          <input
            type="url"
            id="${this._getFieldName("meeting_recording_url")}"
            class="input-primary ${recordingDisabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""}"
            placeholder="https://youtube.com/watch?v=..."
            .value="${this._recordingUrl}"
            @input="${this._handleRecordingUrlChange}"
            ?disabled=${recordingDisabled}
          />
        </div>
        <p class="form-legend">
          ${this._isSession()
            ? "Session recordings are managed at the event level."
            : "Add a recording link now or after the event."}
        </p>
      </div>
    `;
  }

  /**
   * Renders automatic mode fields.
   * @returns {import('lit').TemplateResult} Automatic mode field elements
   */
  _renderAutomaticFields() {
    return html`
      <div class="space-y-4 rounded-xl border border-stone-200 bg-white p-4 md:p-5 md:col-span-2">
        <div class="space-y-1">
          <div class="text-base font-semibold text-stone-900 mb-3">Create meeting automatically</div>
          <p class="form-legend">We will create and manage the meeting when you save this event.</p>
          <ul class="list-disc list-inside mt-2 form-legend">
            <li>Only available for virtual or hybrid events.</li>
            <li>
              Meeting duration must be between ${MIN_MEETING_MINUTES} and ${MAX_MEETING_MINUTES} minutes.
            </li>
            <li>Manual links cannot be set while automatic creation is on.</li>
            <li>The meeting is not going to be created until you publish the event.</li>
          </ul>
        </div>

        ${this._createMeeting
          ? html`
              <div class="rounded-lg border border-stone-100 bg-stone-50 p-3 space-y-7">
                <div class="space-y-2 lg:w-1/2">
                  <label class="form-label text-sm font-medium text-stone-900">Meeting provider</label>
                  <select
                    class="input-primary ${this.disabled
                      ? "bg-stone-100 text-stone-500 cursor-not-allowed"
                      : ""}"
                    @change="${(e) => {
                      this._providerId = e.target.value || DEFAULT_MEETING_PROVIDER;
                      this._checkMeetingCapacity();
                    }}"
                    ?disabled=${this.disabled}
                  >
                    <option value="zoom" .selected="${this._providerId === DEFAULT_MEETING_PROVIDER}">
                      Zoom
                    </option>
                  </select>
                </div>
                <div class="space-y-2 lg:w-1/2">
                  <label class="form-label text-sm font-medium text-stone-900">Meeting hosts</label>
                  <multiple-inputs
                    id="meeting-hosts-input"
                    .items="${this._hosts}"
                    field-name="${this._getFieldName("meeting_hosts")}"
                    input-type="email"
                    label="Host"
                    placeholder="host@example.com"
                    legend="${this._getMeetingHostsLegend()}"
                    ?disabled=${this.disabled}
                  >
                  </multiple-inputs>
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
        description: "Paste a Zoom, Teams, Meet, or other link.",
        helper: "",
        disabled: this.disabled,
      },
      {
        value: "automatic",
        title: "Create meeting automatically",
        description: "We will create and manage a meeting when you save this event.",
        reasons: availability.reasons,
        disabled: this.disabled || !availability.allowed,
      },
    ];

    return html`
      ${this._renderHiddenInputs()}

      <div class="space-y-8 max-w-5xl">
        <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
          ${modeOptions.map((option) => this._renderModeOption(option))}
        </div>

        <div class="grid grid-cols-1 gap-6 ${this._mode === "manual" ? "" : "md:grid-cols-2"}">
          ${this._mode === "manual" ? this._renderManualFields() : this._renderAutomaticFields()}
        </div>

        ${this._capacityWarning
          ? html`
              <div class="rounded-lg border border-amber-200 bg-amber-50 text-amber-800 text-sm p-3">
                ${this._capacityWarning}
              </div>
            `
          : ""}
        ${this._mode === "automatic" ? this._renderMeetingStatus() : ""}
      </div>
    `;
  }
}

customElements.define("online-event-details", OnlineEventDetails);
