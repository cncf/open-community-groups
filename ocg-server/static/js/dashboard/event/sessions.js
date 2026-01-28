import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import {
  isObjectEmpty,
  convertTimestampToDateTimeLocal,
  convertTimestampToDateTimeLocalInTz,
} from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/logo-image.js";
import "/static/js/common/speakers-selector.js";
import "/static/js/common/online-event-details.js";
import { normalizeSpeakers } from "/static/js/dashboard/event/speaker-utils.js";

/**
 * Component for managing session entries in events.
 * Supports adding, removing, and reordering session items.
 * @extends LitWrapper
 */
export class SessionsSection extends LitWrapper {
  /**
   * Component properties definition
   * @property {Array} sessions - List of session entries
   * Each entry contains:
   *  - id: Unique identifier
   *  - name: Session title
   *  - description: Full session description (markdown format, optional)
   *  - kind: Session type (hybrid, in-person, virtual)
   *  - starts_at: Session start time (datetime-local format)
   *  - ends_at: Session end time (datetime-local format, optional)
   *  - location: Location details (optional)
   *  - meeting_join_url: URL for session meeting (optional)
   *  - meeting_recording_url: URL for session meeting recording (optional)
   *  - speakers: Session speakers (array, handled separately)
   */
  static properties = {
    sessions: { type: Array },
    // List of available session kinds to render options
    sessionKinds: { type: Array, attribute: "session-kinds" },
    // Timezone to render datetime-local values (e.g. "Europe/Amsterdam")
    timezone: { type: String, attribute: "timezone" },
    meetingMaxParticipants: { type: Object, attribute: "meeting-max-participants" },
    // Whether meetings feature is enabled for the group
    meetingsEnabled: { type: Boolean, attribute: "meetings-enabled" },
    // Disable editing controls
    disabled: { type: Boolean },
  };

  constructor() {
    super();
    this.sessions = [];
    this.sessionKinds = [];
    this.meetingMaxParticipants = {};
    this.meetingsEnabled = false;
    this.disabled = false;
    this._bindHtmxCleanup();
  }

  connectedCallback() {
    super.connectedCallback();

    // Accept JSON passed via attributes when used from server templates.
    if (typeof this.sessions === "string") {
      try {
        this.sessions = JSON.parse(this.sessions || "[]");
      } catch (_) {
        this.sessions = [];
      }
    }

    // When an object is received, extract and flatten its array values to
    // obtain a sessions array.
    if (!Array.isArray(this.sessions) && this.sessions && typeof this.sessions === "object") {
      try {
        const values = Object.values(this.sessions);
        this.sessions = values.reduce((acc, v) => {
          if (Array.isArray(v)) acc.push(...v);
          return acc;
        }, []);
      } catch (_) {
        // If anything goes wrong, fall back to empty array below.
      }
    }
    if (!Array.isArray(this.sessions)) this.sessions = [];

    if (typeof this.sessionKinds === "string") {
      try {
        this.sessionKinds = JSON.parse(this.sessionKinds || "[]");
      } catch (_) {
        this.sessionKinds = [];
      }
    }
    if (!Array.isArray(this.sessionKinds)) this.sessionKinds = [];

    if (typeof this.meetingMaxParticipants === "string") {
      try {
        this.meetingMaxParticipants = JSON.parse(this.meetingMaxParticipants || "{}");
      } catch (_) {
        this.meetingMaxParticipants = {};
      }
    }
    if (!this.meetingMaxParticipants || typeof this.meetingMaxParticipants !== "object") {
      this.meetingMaxParticipants = {};
    }

    this._initializeSessionIds();
  }

  /**
   * Assigns unique IDs to session entries.
   * Creates initial entry if none exist or array is empty.
   * @private
   */
  _initializeSessionIds() {
    if (this.sessions === null || this.sessions.length === 0) {
      this.sessions = [this._getData()];
    } else {
      this.sessions = this.sessions.map((item, index) => {
        const toLocal = (ts) =>
          this.timezone
            ? convertTimestampToDateTimeLocalInTz(ts, this.timezone)
            : convertTimestampToDateTimeLocal(ts);
        return {
          ...this._getData(),
          ...item,
          id: index,
          starts_at: toLocal(item.starts_at),
          ends_at: toLocal(item.ends_at),
        };
      });
    }
  }

  /**
   * Creates a new empty session data object.
   * @returns {Object} Empty session entry
   * @private
   */
  _getData = () => {
    let item = {
      id: this.sessions ? this.sessions.length : 0,
      name: "",
      description: "",
      kind: "",
      starts_at: "",
      ends_at: "",
      location: "",
      meeting_requested: false,
      meeting_in_sync: false,
      meeting_join_url: "",
      meeting_provider_id: "",
      meeting_password: "",
      meeting_error: "",
      meeting_recording_url: "",
      meeting_hosts: [],
      speakers: [],
    };

    return item;
  };

  /**
   * Adds a new session entry at specified index.
   * @param {number} index - Position to insert new entry
   * @private
   */
  _addSessionItem(index) {
    if (this.disabled) return;
    const currentSessions = [...this.sessions];
    currentSessions.splice(index, 0, this._getData());

    this.sessions = currentSessions;
  }

  /**
   * Removes session entry at specified index.
   * Ensures at least one empty entry remains.
   * @param {number} index - Position of entry to remove
   * @private
   */
  _removeSessionItem(index) {
    if (this.disabled) return;
    const tmpSessions = this.sessions.filter((_, i) => i !== index);
    // If there are no more session items, add a new one
    this.sessions = tmpSessions.length === 0 ? [this._getData()] : tmpSessions;
  }

  /**
   * Updates session data at specified index.
   * @param {Object} data - Updated session data
   * @param {number} index - Index of entry to update
   * @private
   */
  _onDataChange = (data, index) => {
    this.sessions[index] = data;
  };

  /**
   * Renders a session entry with controls.
   * @param {number} index - Entry index
   * @param {Object} session - Session data
   * @returns {import('lit').TemplateResult} Entry template
   * @private
   */
  _getSessionForm(index, session) {
    const hasSingleSessionItem = this.sessions.length === 1;

    return html`<div class="mt-10">
      <div class="flex w-full max-w-5xl">
        <div class="flex flex-col space-y-3 me-3">
          <div>
            <button
              @click=${() => this._addSessionItem(index)}
              type="button"
              class="p-2 border border-stone-200 rounded-full ${this.disabled
                ? "cursor-not-allowed opacity-60"
                : "cursor-pointer hover:bg-stone-100"}"
              ?disabled=${this.disabled}
              title="Add above"
            >
              <div class="svg-icon size-4 icon-plus-top bg-stone-600"></div>
            </button>
          </div>
          <div>
            <button
              @click=${() => this._addSessionItem(index + 1)}
              type="button"
              class="p-2 border border-stone-200 rounded-full ${this.disabled
                ? "cursor-not-allowed opacity-60"
                : "cursor-pointer hover:bg-stone-100"}"
              ?disabled=${this.disabled}
              title="Add below"
            >
              <div class="svg-icon size-4 icon-plus-bottom bg-stone-600"></div>
            </button>
          </div>
          <div>
            <button
              @click=${() => this._removeSessionItem(index)}
              type="button"
              class="p-2 border border-stone-200 rounded-full ${this.disabled
                ? "cursor-not-allowed opacity-60"
                : "cursor-pointer hover:bg-stone-100"}"
              ?disabled=${this.disabled}
              title=${hasSingleSessionItem ? "Clean" : "Delete"}
            >
              <div
                class="svg-icon size-4 icon-${hasSingleSessionItem ? "eraser" : "trash"} bg-stone-600"
              ></div>
            </button>
          </div>
        </div>
        <session-item
          .data=${session}
          .index=${index}
          .sessionKinds=${this.sessionKinds || []}
          .meetingMaxParticipants=${this.meetingMaxParticipants || {}}
          .meetingsEnabled=${this.meetingsEnabled}
          .onDataChange=${this._onDataChange}
          .disabled=${this.disabled}
          class="w-full"
        ></session-item>
      </div>
    </div>`;
  }

  render() {
    return html` <div class="text-sm/6 text-stone-500">
        Add sessions for your event. You can add additional sessions by clicking on the
        <span class="font-semibold">+</span> buttons on the left of the card (
        <div class="inline-block svg-icon size-4 icon-plus-top bg-stone-600 relative -bottom-0.5"></div>
        to add the new session above,
        <div class="inline-block svg-icon size-4 icon-plus-bottom bg-stone-600 relative -bottom-0.5"></div>
        to add it below). Sessions will be displayed in the order provided.
      </div>
      <div id="sessions-section">
        ${repeat(
          this.sessions,
          (s) => s.id,
          (s, index) => this._getSessionForm(index, s),
        )}
      </div>`;
  }

  /**
   * Removes empty session parameters before HTMX submits the form.
   * Prevents backend validation errors when a placeholder session is untouched.
   * @private
   */
  _bindHtmxCleanup() {
    if (SessionsSection._cleanupBound || typeof window === "undefined" || !window.htmx) {
      return;
    }
    window.htmx.on("htmx:configRequest", (event) => {
      const params = event.detail?.parameters;
      if (!params || typeof params !== "object") {
        return;
      }

      const buckets = {};
      Object.entries(params).forEach(([key, value]) => {
        const match = key.match(/^sessions\[(\d+)\]/);
        if (!match) return;
        const idx = match[1];
        if (!buckets[idx]) buckets[idx] = [];
        buckets[idx].push({ key, value });
      });

      const isNonEmpty = (entry) => {
        const { key, value } = entry;
        if (value === null || typeof value === "undefined") return false;
        if (Array.isArray(value)) return value.length > 0;
        const normalized = String(value).trim();
        if (normalized === "" || normalized === "0") return false;
        if (normalized === "false") return false;
        if (key.endsWith("_mode") && normalized === "manual") return false;
        return true;
      };

      Object.values(buckets).forEach((entries) => {
        const hasContent = entries.some(isNonEmpty);
        if (hasContent) return;
        entries.forEach(({ key }) => {
          delete params[key];
        });
      });
    });
    SessionsSection._cleanupBound = true;
  }
}
SessionsSection._cleanupBound = false;
customElements.define("sessions-section", SessionsSection);

/**
 * Individual session entry component.
 * Handles form inputs and validation for a single session item.
 * @extends LitWrapper
 */
class SessionItem extends LitWrapper {
  /**
   * Component properties definition
   * @property {Object} data - Session entry data
   * @property {number} index - Position of the entry in the list
   * @property {boolean} isObjectEmpty - Indicates if the data object is empty
   * @property {Function} onDataChange - Callback function to notify parent component of changes
   */
  static properties = {
    data: { type: Object },
    index: { type: Number },
    isObjectEmpty: { type: Boolean },
    onDataChange: { type: Function },
    // Session kinds list provided by parent component
    sessionKinds: { type: Array, attribute: "session-kinds" },
    meetingMaxParticipants: {
      type: Object,
      attribute: "meeting-max-participants",
    },
    // Whether meetings feature is enabled for the group
    meetingsEnabled: { type: Boolean },
    // Disable editing controls
    disabled: { type: Boolean },
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
      meeting_join_url: "",
      meeting_recording_url: "",
      meeting_provider_id: "",
      meeting_hosts: [],
      speakers: [],
    };
    this.index = 0;
    this.isObjectEmpty = true;
    this.onDataChange = () => {};
    this.sessionKinds = [];
    this.meetingMaxParticipants = {};
    this.meetingsEnabled = false;
    this.disabled = false;
  }

  connectedCallback() {
    super.connectedCallback();
    if (!this.data) {
      this.data = {};
    }
    this.data.meeting_requested =
      this.data.meeting_requested === true || this.data.meeting_requested === "true";
    this.data.meeting_in_sync = this.data.meeting_in_sync === true || this.data.meeting_in_sync === "true";
    this.data.meeting_provider_id = this.data.meeting_provider_id || "";
    this.data.meeting_password = this.data.meeting_password || "";
    this.data.meeting_error = this.data.meeting_error || "";
    this.data.speakers = normalizeSpeakers(this.data.speakers);
    this.isObjectEmpty = isObjectEmpty(this.data);

    if (typeof this.meetingMaxParticipants === "string") {
      try {
        this.meetingMaxParticipants = JSON.parse(this.meetingMaxParticipants || "{}");
      } catch (_) {
        this.meetingMaxParticipants = {};
      }
    }
    if (!this.meetingMaxParticipants || typeof this.meetingMaxParticipants !== "object") {
      this.meetingMaxParticipants = {};
    }
  }

  /**
   * Handles input field changes.
   * @param {Event} event - Input event
   * @private
   */
  _onInputChange = (event) => {
    if (this.disabled) return;
    const value = event.target.value;
    const name = event.target.dataset.name;

    this.data = { ...this.data, [name]: value };
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  };

  /**
   * Handles markdown editor changes.
   * @param {string} value - Updated markdown content
   * @private
   */
  _onTextareaChange = (value) => {
    if (this.disabled) return;
    this.data = { ...this.data, description: value };
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  };

  _handleSpeakersChanged = (event) => {
    if (this.disabled) return;
    /**
     * Receives updated speakers from the shared selector.
     * @param {CustomEvent} event
     */
    const speakers = normalizeSpeakers(event.detail?.speakers || []);
    this.data = { ...this.data, speakers };
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  };

  render() {
    const speakers = normalizeSpeakers(this.data?.speakers);
    return html` <div
      class="grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6 border-2 border-stone-200 border-dashed p-8 rounded-lg bg-stone-50/25 w-full"
    >
      <div class="col-span-full">
        <label class="form-label"> Session Title <span class="asterisk">*</span> </label>
        <div class="mt-2">
          <input
            @input=${(e) => this._onInputChange(e)}
            data-name="name"
            type="text"
            name="sessions[${this.index}][name]"
            class="input-primary ${this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""}"
            value=${this.data.name}
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            ?required=${!this.isObjectEmpty}
            ?disabled=${this.disabled}
          />
        </div>
      </div>

      <div class="col-span-2">
        <label class="form-label"> Session Type <span class="asterisk">*</span> </label>
        <div class="mt-2">
          <select
            @change=${(e) => this._onInputChange(e)}
            data-name="kind"
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
        <label class="form-label"> Start Time <span class="asterisk">*</span> </label>
        <div class="mt-2">
          <input
            type="datetime-local"
            @input=${(e) => this._onInputChange(e)}
            data-name="starts_at"
            name="sessions[${this.index}][starts_at]"
            class="input-primary ${this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""}"
            value=${this.data.starts_at || ""}
            ?required=${!this.isObjectEmpty}
            ?disabled=${this.disabled}
          />
        </div>
      </div>

      <div class="col-span-2">
        <label class="form-label"> End Time </label>
        <div class="mt-2">
          <input
            type="datetime-local"
            @input=${(e) => this._onInputChange(e)}
            data-name="ends_at"
            name="sessions[${this.index}][ends_at]"
            class="input-primary ${this.disabled ? "bg-stone-100 text-stone-500 cursor-not-allowed" : ""}"
            value=${this.data.ends_at || ""}
            ?disabled=${this.disabled}
          />
        </div>
      </div>

      <div class="col-span-full">
        <label for="summary" class="form-label"> Description </label>
        <div class="mt-2">
          <markdown-editor
            id="sessions[${this.index}][description]"
            name="sessions[${this.index}][description]"
            content=${this.data.description}
            .onChange=${(value) => this._onTextareaChange(value)}
            maxlength=${8000}
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

      <div class="col-span-full">
        <label class="form-label"> Location </label>
        <div class="mt-2">
          <input
            @input=${(e) => this._onInputChange(e)}
            data-name="location"
            type="text"
            name="sessions[${this.index}][location]"
            class="input-primary"
            value=${this.data.location}
            placeholder="Optional - physical location or meeting room"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            ?disabled=${this.disabled}
          />
        </div>
      </div>

      ${this.data.kind !== "in-person"
        ? html`
            <div class="col-span-full">
              <label class="form-label"> Session meeting details </label>
              <div class="mt-2">
                ${this.meetingsEnabled
                  ? html`
                      <online-event-details
                        kind=${this.data.kind || "virtual"}
                        meeting-join-url=${this.data.meeting_join_url || ""}
                        meeting-recording-url=${this.data.meeting_recording_url || ""}
                        ?meeting-requested=${this.data.meeting_requested}
                        ?meeting-in-sync=${this.data.meeting_in_sync}
                        meeting-password=${this.data.meeting_password || ""}
                        meeting-error=${this.data.meeting_error || ""}
                        starts-at=${this.data.starts_at || ""}
                        ends-at=${this.data.ends_at || ""}
                        .meetingHosts=${this.data.meeting_hosts || {}}
                        .meetingMaxParticipants=${this.meetingMaxParticipants || {}}
                        field-name-prefix="sessions[${this.index}]"
                        ?disabled=${this.disabled}
                      ></online-event-details>
                    `
                  : html`
                      <div class="space-y-6">
                        <div class="grid grid-cols-1 gap-6">
                          <div class="space-y-2">
                            <label for="meeting_join_url_${this.index}" class="form-label">Meeting URL</label>
                            <div class="mt-2">
                              <input
                                type="url"
                                id="meeting_join_url_${this.index}"
                                name="sessions[${this.index}][meeting_join_url]"
                                class="input-primary ${this.disabled
                                  ? "bg-stone-100 text-stone-500 cursor-not-allowed"
                                  : ""}"
                                value=${this.data.meeting_join_url || ""}
                                placeholder="https://meet.example.com/123456789"
                                @input=${(e) => this._onInputChange(e)}
                                data-name="meeting_join_url"
                                ?disabled=${this.disabled}
                              />
                            </div>
                            <p class="form-legend">Teams, Meet, or any other video link.</p>
                          </div>
                          <div class="space-y-2">
                            <label for="meeting_recording_url_${this.index}" class="form-label"
                              >Recording URL (optional)</label
                            >
                            <div class="mt-2">
                              <input
                                type="url"
                                id="meeting_recording_url_${this.index}"
                                name="sessions[${this.index}][meeting_recording_url]"
                                class="input-primary ${this.disabled
                                  ? "bg-stone-100 text-stone-500 cursor-not-allowed"
                                  : ""}"
                                value=${this.data.meeting_recording_url || ""}
                                placeholder="https://youtube.com/watch?v=..."
                                @input=${(e) => this._onInputChange(e)}
                                data-name="meeting_recording_url"
                                ?disabled=${true}
                              />
                            </div>
                            <p class="form-legend">Add a recording link now or after the event.</p>
                          </div>
                        </div>
                      </div>
                    `}
              </div>
            </div>
          `
        : ""}
    </div>`;
  }
}
customElements.define("session-item", SessionItem);
