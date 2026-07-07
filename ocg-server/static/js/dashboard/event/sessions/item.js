import { html, nothing } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import {
  MEETING_RECORDING_RAW_URLS_LEGEND,
  MEETING_RECORDING_URL_LEGEND,
  MEETING_RECORDING_VISIBILITY_LEGEND,
} from "/static/js/common/meeting-recording.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { isObjectEmpty, parseJsonAttribute } from "/static/js/common/utils.js";
import "/static/js/common/users/speakers-selector.js";
import "/static/js/common/online-event-details.js";
import { combineDateAndTime, extractTimePart } from "/static/js/dashboard/event/sessions/datetime.js";
import { normalizeSpeakers } from "/static/js/dashboard/event/sessions/speaker-utils.js";

/**
 * Returns a valid maxlength attribute value or omits the attribute.
 * @param {*} value Raw max length value.
 * @returns {*} Maxlength attribute value.
 */
const normalizeMaxLength = (value) => {
  const maxLength = Number(value);
  return Number.isFinite(maxLength) && maxLength >= 0 ? maxLength : nothing;
};

/**
 * Individual session entry component.
 * Handles form inputs and validation for a single session item.
 * @extends LitWrapper
 */
class SessionItem extends LitWrapper {
  /**
   * Component properties definition.
   * @property {Object} data - Session data bound to form inputs.
   * @property {number} index - Session index used for form field names.
   * @property {boolean} isObjectEmpty - Whether the session has meaningful data.
   * @property {Function} onDataChange - Callback for data changes.
   * @property {Array} sessionKinds - Available session kinds.
   * @property {Array} approvedSubmissions - Approved CFS submissions.
   * @property {Array} usedSubmissionIds - Submission ids used by other sessions.
   * @property {Object} meetingMaxParticipants - Limits per meeting provider.
   * @property {boolean} meetingsEnabled - Whether meetings can be configured.
   * @property {number} descriptionMaxLength - Max session description length.
   * @property {number} sessionNameMaxLength - Max session title length.
   * @property {number} locationMaxLength - Max session location length.
   * @property {boolean} disabled - Whether editing controls are disabled.
   * @property {string} inputMode - Entry mode, manual or cfs.
   * @property {string} prefilledDate - Date used to pre-fill time fields.
   * @property {boolean} eventPast - Whether the parent event is in the past.
   */
  static properties = {
    data: { type: Object },
    index: { type: Number },
    isObjectEmpty: { type: Boolean },
    onDataChange: { type: Function },
    sessionKinds: { type: Array, attribute: "session-kinds" },
    approvedSubmissions: { type: Array },
    usedSubmissionIds: { type: Array },
    meetingMaxParticipants: { type: Object, attribute: "meeting-max-participants" },
    meetingsEnabled: { type: Boolean },
    descriptionMaxLength: { type: Number, attribute: "description-max-length" },
    sessionNameMaxLength: { type: Number, attribute: "session-name-max-length" },
    locationMaxLength: { type: Number, attribute: "location-max-length" },
    disabled: { type: Boolean },
    inputMode: { type: String },
    prefilledDate: { type: String },
    eventPast: { type: Boolean },
  };

  constructor() {
    super();
    this.data = {
      id: 0,
      name: "",
      description: "",
      kind: "",
      starts_at: "",
      ends_at: "",
      location: "",
      meeting_requested: false,
      meeting_join_instructions: "",
      meeting_join_url: "",
      meeting_recording_published: false,
      meeting_recording_raw_urls: [],
      meeting_recording_url: "",
      meeting_provider_id: "",
      meeting_hosts: [],
      speakers: [],
    };
    this.index = 0;
    this.isObjectEmpty = true;
    this.onDataChange = () => {};
    this.sessionKinds = [];
    this.approvedSubmissions = [];
    this.usedSubmissionIds = [];
    this.meetingMaxParticipants = {};
    this.meetingsEnabled = false;
    this.descriptionMaxLength = undefined;
    this.sessionNameMaxLength = undefined;
    this.locationMaxLength = undefined;
    this.disabled = false;
    this.inputMode = "manual";
    this.prefilledDate = "";
    this.eventPast = false;
    this._onModeChange = this._onModeChange.bind(this);
    this._handleSpeakersChanged = this._handleSpeakersChanged.bind(this);
  }

  connectedCallback() {
    super.connectedCallback();
    if (!this.data) {
      this.data = {};
    }
    this.data.meeting_requested =
      this.data.meeting_requested === true || this.data.meeting_requested === "true";
    this.data.meeting_in_sync = this.data.meeting_in_sync === true || this.data.meeting_in_sync === "true";
    this.data.cfs_submission_id = this.data.cfs_submission_id || "";
    this.data.meeting_provider_id = this.data.meeting_provider_id || "";
    this.data.meeting_password = this.data.meeting_password || "";
    this.data.meeting_error = this.data.meeting_error || "";
    this.data.speakers = normalizeSpeakers(this.data.speakers);
    this.isObjectEmpty = isObjectEmpty(this.data);

    if (!Array.isArray(this.approvedSubmissions)) {
      this.approvedSubmissions = [];
    }
    if (!Array.isArray(this.usedSubmissionIds)) {
      this.usedSubmissionIds = [];
    }

    this.meetingMaxParticipants = parseJsonAttribute(this.meetingMaxParticipants, {});
    if (
      !this.meetingMaxParticipants ||
      typeof this.meetingMaxParticipants !== "object" ||
      Array.isArray(this.meetingMaxParticipants)
    ) {
      this.meetingMaxParticipants = {};
    }

    if (this.data.cfs_submission_id) {
      this.inputMode = "cfs";
    } else {
      this.inputMode = "manual";
    }
  }

  /**
   * Handles input field changes.
   * @param {Event} event - Input event
   * @private
   */
  _onInputChange(event) {
    if (this.disabled) return;
    const value = event.target.type === "checkbox" ? event.target.checked : event.target.value;
    const name = event.target.dataset.name;

    this.data = { ...this.data, [name]: value };
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  }

  /**
   * Handles time input changes when date is pre-filled.
   * @param {Event} event - Input event
   * @param {string} field - Field name (starts_at or ends_at)
   * @private
   */
  _onTimeChange(event, field) {
    if (this.disabled) return;
    const time = event.target.value;
    const datetime = combineDateAndTime(this.prefilledDate, time);

    this.data = { ...this.data, [field]: datetime };
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  }

  /**
   * Handles markdown editor changes.
   * @param {string} value - Updated markdown content
   * @private
   */
  _onTextareaChange(value) {
    if (this.disabled) return;
    this.data = { ...this.data, description: value };
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  }

  _handleSpeakersChanged(event) {
    if (this.disabled) return;
    const speakers = normalizeSpeakers(event.detail?.speakers || []);
    this.data = { ...this.data, speakers };
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  }

  /**
   * Handles input mode radio button changes.
   * @param {Event} event - Change event from radio input
   * @private
   */
  _onModeChange(event) {
    if (this.disabled) return;
    const newMode = event.target.value;
    this.inputMode = newMode;

    if (newMode === "cfs") {
      this.data = { ...this.data, description: "", speakers: [] };
    } else {
      this.data = { ...this.data, cfs_submission_id: "", speakers: [] };
    }

    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  }

  render() {
    const usedSubmissionIds = new Set((this.usedSubmissionIds || []).map((id) => String(id)));
    const currentSubmissionId = this.data?.cfs_submission_id ? String(this.data.cfs_submission_id) : "";
    const hasPrefilledDate = !!this.prefilledDate;
    const startTime = extractTimePart(this.data.starts_at);
    const endTime = extractTimePart(this.data.ends_at);
    const sessionNameMaxLength = normalizeMaxLength(this.sessionNameMaxLength);
    const locationMaxLength = normalizeMaxLength(this.locationMaxLength);
    const sessionNameId = `session-${this.index}-name`;
    const sessionKindId = `session-${this.index}-kind`;
    const sessionStartsAtId = `session-${this.index}-starts-at`;
    const sessionEndsAtId = `session-${this.index}-ends-at`;
    const sessionLocationId = `session-${this.index}-location`;
    const sessionCfsSubmissionId = `session-${this.index}-cfs-submission`;
    const sessionDescriptionId = `session-${this.index}-description`;
    const meetingJoinUrlId = `session-${this.index}-meeting-join-url`;
    const meetingJoinInstructionsId = `session-${this.index}-meeting-join-instructions`;
    const meetingRecordingUrlId = `session-${this.index}-meeting-recording-url`;

    return html` <div class="grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6 w-full h-full">
      <div class="col-span-full">
        <label for=${sessionNameId} class="form-label"> Session Title <span class="asterisk">*</span> </label>
        <div class="mt-2">
          <input
            @input=${(event) => this._onInputChange(event)}
            data-name="name"
            id=${sessionNameId}
            type="text"
            name="sessions[${this.index}][name]"
            class="input-primary ${this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""}"
            value=${this.data.name}
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            maxlength=${sessionNameMaxLength}
            ?required=${!this.isObjectEmpty}
            ?disabled=${this.disabled}
          />
        </div>
      </div>

      <div class="col-span-2">
        <label for=${sessionKindId} class="form-label"> Session Type <span class="asterisk">*</span> </label>
        <div class="mt-2">
          <select
            @change=${(event) => this._onInputChange(event)}
            data-name="kind"
            id=${sessionKindId}
            name="sessions[${this.index}][kind]"
            class="input-primary ${this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""}"
            ?required=${!this.isObjectEmpty}
            ?disabled=${this.disabled}
          >
            <option value="" ?selected=${!this.data.kind}>Select type</option>
            ${this.sessionKinds.map(
              (k) =>
                html`<option value=${k.session_kind_id} ?selected=${this.data.kind === k.session_kind_id}>
                  ${k.display_name}
                </option>`,
            )}
          </select>
        </div>
      </div>

      <div class="col-span-2">
        <label for=${sessionStartsAtId} class="form-label">
          Start Time <span class="asterisk">*</span>
        </label>
        <div class="mt-2">
          ${
            hasPrefilledDate
              ? html`
                  <input
                    id=${sessionStartsAtId}
                    type="time"
                    @input=${(event) => this._onTimeChange(event, "starts_at")}
                    class="input-primary ${
                      this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""
                    }"
                    value=${startTime}
                    ?required=${!this.isObjectEmpty}
                    ?disabled=${this.disabled}
                  />
                `
              : html`
                  <input
                    id=${sessionStartsAtId}
                    type="datetime-local"
                    @input=${(event) => this._onInputChange(event)}
                    data-name="starts_at"
                    name="sessions[${this.index}][starts_at]"
                    class="input-primary ${
                      this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""
                    }"
                    value=${this.data.starts_at || ""}
                    ?required=${!this.isObjectEmpty}
                    ?disabled=${this.disabled}
                  />
                `
          }
        </div>
      </div>

      <div class="col-span-2">
        <label for=${sessionEndsAtId} class="form-label"> End Time </label>
        <div class="mt-2">
          ${
            hasPrefilledDate
              ? html`
                  <input
                    id=${sessionEndsAtId}
                    type="time"
                    @input=${(event) => this._onTimeChange(event, "ends_at")}
                    class="input-primary ${
                      this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""
                    }"
                    value=${endTime}
                    ?disabled=${this.disabled}
                  />
                `
              : html`
                  <input
                    id=${sessionEndsAtId}
                    type="datetime-local"
                    @input=${(event) => this._onInputChange(event)}
                    data-name="ends_at"
                    name="sessions[${this.index}][ends_at]"
                    class="input-primary ${
                      this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""
                    }"
                    value=${this.data.ends_at || ""}
                    ?disabled=${this.disabled}
                  />
                `
          }
        </div>
      </div>

      <div class="col-span-full">
        <label for=${sessionLocationId} class="form-label"> Location </label>
        <div class="mt-2">
          <input
            @input=${(event) => this._onInputChange(event)}
            data-name="location"
            id=${sessionLocationId}
            type="text"
            name="sessions[${this.index}][location]"
            class="input-primary"
            value=${this.data.location}
            placeholder="Optional - physical location or meeting room"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            maxlength=${locationMaxLength}
            ?disabled=${this.disabled}
          />
        </div>
      </div>

      ${
        this.approvedSubmissions?.length
          ? html`
              <fieldset class="col-span-full">
                <legend class="form-label">Description and speakers</legend>
                <div class="mt-2 grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <label class="block h-full">
                    <input
                      type="radio"
                      name="sessions[${this.index}][input_mode]"
                      value="cfs"
                      class="sr-only"
                      .checked=${this.inputMode === "cfs"}
                      @change=${this._onModeChange}
                      ?disabled=${this.disabled}
                    />
                    <div
                      class="h-full rounded-xl border transition bg-white p-4 md:p-5 flex ${
                        this.inputMode === "cfs"
                          ? "border-primary-400 ring-2 ring-primary-200"
                          : "border-stone-200"
                      } ${this.disabled ? "opacity-60 cursor-not-allowed" : "hover:border-primary-300"}"
                    >
                      <div class="flex items-start gap-3">
                        <span class="mt-1 inline-flex">
                          <span
                            class="relative flex h-5 w-5 items-center justify-center rounded-full border ${
                              this.inputMode === "cfs" ? "border-primary-500" : "border-stone-300"
                            }"
                          >
                            ${
                              this.inputMode === "cfs"
                                ? html`<span class="h-2.5 w-2.5 rounded-full bg-primary-500"></span>`
                                : ""
                            }
                          </span>
                        </span>
                        <div class="space-y-1">
                          <div class="text-base font-semibold text-stone-900">
                            From Call for Speakers submission
                          </div>
                          <p class="form-legend">Link an approved CFS submission to this session.</p>
                        </div>
                      </div>
                    </div>
                  </label>
                  <label class="block h-full">
                    <input
                      type="radio"
                      name="sessions[${this.index}][input_mode]"
                      value="manual"
                      class="sr-only"
                      .checked=${this.inputMode === "manual"}
                      @change=${this._onModeChange}
                      ?disabled=${this.disabled}
                    />
                    <div
                      class="h-full rounded-xl border transition bg-white p-4 md:p-5 flex ${
                        this.inputMode === "manual"
                          ? "border-primary-400 ring-2 ring-primary-200"
                          : "border-stone-200"
                      } ${this.disabled ? "opacity-60 cursor-not-allowed" : "hover:border-primary-300"}"
                    >
                      <div class="flex items-start gap-3">
                        <span class="mt-1 inline-flex">
                          <span
                            class="relative flex h-5 w-5 items-center justify-center rounded-full border ${
                              this.inputMode === "manual" ? "border-primary-500" : "border-stone-300"
                            }"
                          >
                            ${
                              this.inputMode === "manual"
                                ? html`<span class="h-2.5 w-2.5 rounded-full bg-primary-500"></span>`
                                : ""
                            }
                          </span>
                        </span>
                        <div class="space-y-1">
                          <div class="text-base font-semibold text-stone-900">Manual</div>
                          <p class="form-legend">Add description and speakers manually.</p>
                        </div>
                      </div>
                    </div>
                  </label>
                </div>
              </fieldset>
            `
          : ""
      }
      ${
        this.inputMode === "cfs" && this.approvedSubmissions?.length
          ? html`
              <div class="col-span-full">
                <label for=${sessionCfsSubmissionId} class="form-label"> Link to CFS submission </label>
                <div class="mt-2">
                  <select
                    @change=${(event) => this._onInputChange(event)}
                    data-name="cfs_submission_id"
                    id=${sessionCfsSubmissionId}
                    name="sessions[${this.index}][cfs_submission_id]"
                    class="input-primary ${
                      this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""
                    }"
                    ?disabled=${this.disabled}
                  >
                    <option value="" ?selected=${!currentSubmissionId}>Select an approved submission</option>
                    ${this.approvedSubmissions.map((submission) => {
                      const submissionId = String(submission.cfs_submission_id);
                      const isUsed = usedSubmissionIds.has(submissionId);
                      const isCurrent = submissionId === currentSubmissionId;
                      return html`<option
                        value=${submissionId}
                        ?selected=${isCurrent}
                        ?disabled=${isUsed && !isCurrent}
                      >
                        ${submission.title} · ${submission.speaker_name}
                      </option>`;
                    })}
                  </select>
                </div>
                <p class="form-legend">Only approved submissions for this event can be linked.</p>
              </div>
            `
          : ""
      }
      ${
        this.inputMode === "manual" || !this.approvedSubmissions?.length
          ? html`
              <div class="col-span-full">
                <label for=${sessionDescriptionId} class="form-label"> Description </label>
                <div class="mt-2">
                  <markdown-editor
                    input-id=${sessionDescriptionId}
                    name="sessions[${this.index}][description]"
                    content=${this.data.description}
                    .onChange=${(value) => this._onTextareaChange(value)}
                    maxlength=${this.descriptionMaxLength}
                    mini
                    ?disabled=${this.disabled}
                  ></markdown-editor>
                </div>
              </div>

              <div class="col-span-full">
                <div class="flex items-center justify-between gap-4 flex-wrap">
                  <speakers-selector
                    selected-speakers=${JSON.stringify(this.data.speakers || [])}
                    dashboard-type="group"
                    field-name-prefix=${`sessions[${this.index}][speakers]`}
                    show-add-button
                    label="Speakers"
                    help-text="Add speakers or presenters for this session."
                    class="w-full"
                    @speakers-changed=${this._handleSpeakersChanged}
                    ?disabled=${this.disabled}
                  ></speakers-selector>
                </div>
              </div>
            `
          : ""
      }
      ${
        this.data.kind !== "in-person"
          ? html`
              <div class="col-span-full">
                <div class="form-label">Session meeting details</div>
                <div class="mt-2 mb-5">
                  ${
                    this.meetingsEnabled
                      ? html`
                          <online-event-details
                            kind=${this.data.kind || "virtual"}
                            meeting-join-url=${this.data.meeting_join_url || ""}
                            meeting-recording-published=${String(this.data.meeting_recording_published === true)}
                            meeting-recording-url=${this.data.meeting_recording_url || ""}
                            ?meeting-requested=${this.data.meeting_requested}
                            ?meeting-in-sync=${this.data.meeting_in_sync}
                            meeting-password=${this.data.meeting_password || ""}
                            meeting-error=${this.data.meeting_error || ""}
                            starts-at=${this.data.starts_at || ""}
                            ends-at=${this.data.ends_at || ""}
                            .meetingRecordingRawUrls=${this.data.meeting_recording_raw_urls || []}
                            .meetingHosts=${this.data.meeting_hosts || {}}
                            .meetingJoinInstructions=${this.data.meeting_join_instructions || ""}
                            .meetingMaxParticipants=${this.meetingMaxParticipants || {}}
                            .eventPast=${this.eventPast}
                            field-name-prefix="sessions[${this.index}]"
                            ?disabled=${this.disabled}
                          ></online-event-details>
                        `
                      : html`
                          <div class="space-y-6">
                            <div class="grid grid-cols-1 gap-6">
                              <div class="space-y-2">
                                <label for=${meetingJoinUrlId} class="form-label">Meeting URL</label>
                                <div class="mt-2">
                                  <input
                                    type="url"
                                    id=${meetingJoinUrlId}
                                    name="sessions[${this.index}][meeting_join_url]"
                                    class="input-primary ${
                                      this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""
                                    }"
                                    value=${this.data.meeting_join_url || ""}
                                    placeholder="https://meet.example.com/123456789"
                                    @input=${(event) => this._onInputChange(event)}
                                    data-name="meeting_join_url"
                                    ?disabled=${this.disabled}
                                  />
                                </div>
                                <p class="form-legend">Teams, Meet, or any other video link.</p>
                              </div>
                              <div class="space-y-2">
                                <label for=${meetingJoinInstructionsId} class="form-label">
                                  Join instructions (optional)
                                </label>
                                <div class="mt-2">
                                  <textarea
                                    id=${meetingJoinInstructionsId}
                                    name="sessions[${this.index}][meeting_join_instructions]"
                                    rows="4"
                                    maxlength="500"
                                    class="input-primary ${
                                      this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""
                                    }"
                                    placeholder="Add passcodes, waiting room details, or other attendee instructions."
                                    .value=${this.data.meeting_join_instructions || ""}
                                    @input=${(event) => this._onInputChange(event)}
                                    data-name="meeting_join_instructions"
                                    ?disabled=${this.disabled}
                                  ></textarea>
                                </div>
                                <p class="form-legend">
                                  Shown with the meeting details on the public event page.
                                </p>
                              </div>
                              ${
                                Array.isArray(this.data.meeting_recording_raw_urls) &&
                                this.data.meeting_recording_raw_urls.length > 0
                                  ? html`
                                      <div class="space-y-2">
                                        ${this.data.meeting_recording_raw_urls.map(
                                          (rawRecordingUrl, rawRecordingIndex) => html`
                                            <div class="space-y-2">
                                              <label
                                                for="meeting_recording_raw_urls_${this.index}_${rawRecordingIndex}"
                                                class="form-label"
                                                >Original provider recording ${rawRecordingIndex + 1}</label
                                              >
                                              <div class="mt-2">
                                                <input
                                                  type="url"
                                                  id="meeting_recording_raw_urls_${this.index}_${rawRecordingIndex}"
                                                  class="input-primary bg-stone-100 text-stone-600 cursor-not-allowed"
                                                  value=${rawRecordingUrl}
                                                  readonly
                                                />
                                              </div>
                                            </div>
                                          `,
                                        )}
                                        <p class="form-legend whitespace-pre-line">
                                          ${MEETING_RECORDING_RAW_URLS_LEGEND}
                                        </p>
                                      </div>
                                    `
                                  : ""
                              }
                              <div class="space-y-2">
                                <label for=${meetingRecordingUrlId} class="form-label"
                                  >Final public recording URL (optional)</label
                                >
                                <div class="mt-2">
                                  <input
                                    type="url"
                                    id=${meetingRecordingUrlId}
                                    name="sessions[${this.index}][meeting_recording_url]"
                                    class="input-primary ${
                                      this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""
                                    }"
                                    value=${this.data.meeting_recording_url || ""}
                                    placeholder="https://youtube.com/watch?v=..."
                                    @input=${(event) => this._onInputChange(event)}
                                    data-name="meeting_recording_url"
                                    ?disabled=${this.disabled}
                                  />
                                </div>
                                <p class="form-legend">${MEETING_RECORDING_URL_LEGEND}</p>
                              </div>
                              <div class="space-y-2">
                                <label class="inline-flex items-center cursor-pointer">
                                  <input
                                    type="checkbox"
                                    class="sr-only peer"
                                    .checked=${this.data.meeting_recording_published === true}
                                    @change=${(event) => this._onInputChange(event)}
                                    data-name="meeting_recording_published"
                                    ?disabled=${this.disabled}
                                  />
                                  <span
                                    class="relative w-11 h-6 bg-stone-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-stone-300 after:border after:border-stone-200 after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-500"
                                  ></span>
                                  <span class="ms-3 text-sm font-medium text-stone-900">
                                    Publish recording publicly
                                  </span>
                                </label>
                                <p class="form-legend">${MEETING_RECORDING_VISIBILITY_LEGEND}</p>
                              </div>
                            </div>
                          </div>
                        `
                  }
                </div>
              </div>
            `
          : ""
      }
    </div>`;
  }
}

customElements.define("session-item", SessionItem);
