import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import {
  isObjectEmpty,
  convertTimestampToDateTimeLocal,
  convertTimestampToDateTimeLocalInTz,
  lockBodyScroll,
  unlockBodyScroll,
} from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/logo-image.js";
import "/static/js/common/speakers-selector.js";
import "/static/js/common/online-event-details.js";
import { normalizeSpeakers } from "/static/js/dashboard/event/speaker-utils.js";

/**
 * Extracts date part from datetime-local string.
 * @param {string} datetimeLocal - Datetime string (e.g., "2025-01-15T10:00")
 * @returns {string} Date part (e.g., "2025-01-15")
 */
const extractDatePart = (datetimeLocal) => {
  if (!datetimeLocal) return "";
  return datetimeLocal.slice(0, 10);
};

/**
 * Extracts time part from datetime-local string.
 * @param {string} datetimeLocal - Datetime string (e.g., "2025-01-15T10:00")
 * @returns {string} Time part (e.g., "10:00")
 */
const extractTimePart = (datetimeLocal) => {
  if (!datetimeLocal || datetimeLocal.length < 16) return "";
  return datetimeLocal.slice(11, 16);
};

/**
 * Combines date and time into datetime-local format.
 * @param {string} date - Date part (e.g., "2025-01-15")
 * @param {string} time - Time part (e.g., "10:00")
 * @returns {string} Combined datetime (e.g., "2025-01-15T10:00")
 */
const combineDateAndTime = (date, time) => {
  if (!date || !time) return "";
  return `${date}T${time}`;
};

/**
 * Formats a time string for display in 24-hour format.
 * @param {string} datetimeLocal - Datetime string
 * @returns {string} Formatted time (e.g., "10:00")
 */
const formatTimeDisplay = (datetimeLocal) => {
  if (!datetimeLocal) return "";
  return extractTimePart(datetimeLocal);
};

/**
 * Formats a date string for display as a day header.
 * @param {string} dateStr - Date string (e.g., "2025-01-15")
 * @returns {string} Formatted date (e.g., "Wednesday, December 3, 2025")
 */
const formatDayHeader = (dateStr) => {
  if (!dateStr) return "";
  const date = new Date(dateStr + "T12:00:00");
  return date.toLocaleDateString(undefined, {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
};

/**
 * Component for managing session entries in events.
 * Displays sessions as cards with modal for add/edit operations.
 * @extends LitWrapper
 */
export class SessionsSection extends LitWrapper {
  /**
   * Component properties definition.
   * @property {Array} sessions - Session entries for the event.
   * @property {Array} sessionKinds - Available session kinds.
   * @property {Array} approvedSubmissions - Approved CFS submissions.
   * @property {string} timezone - Timezone used for datetime conversion.
   * @property {Object} meetingMaxParticipants - Limits per meeting provider.
   * @property {boolean} meetingsEnabled - Whether meetings can be configured.
   * @property {number} descriptionMaxLength - Max session description length.
   * @property {number} sessionNameMaxLength - Max session title length.
   * @property {number} locationMaxLength - Max session location length.
   * @property {boolean} disabled - Whether editing controls are disabled.
   * @property {string} eventStartsAt - Event start datetime.
   * @property {string} eventEndsAt - Event end datetime.
   */
  static properties = {
    sessions: { type: Array },
    sessionKinds: { type: Array, attribute: "session-kinds" },
    approvedSubmissions: { type: Array, attribute: "approved-submissions" },
    timezone: { type: String, attribute: "timezone" },
    meetingMaxParticipants: { type: Object, attribute: "meeting-max-participants" },
    meetingsEnabled: { type: Boolean, attribute: "meetings-enabled" },
    descriptionMaxLength: { type: Number, attribute: "description-max-length" },
    sessionNameMaxLength: { type: Number, attribute: "session-name-max-length" },
    locationMaxLength: { type: Number, attribute: "location-max-length" },
    disabled: { type: Boolean },
    eventStartsAt: { type: String, attribute: "event-starts-at" },
    eventEndsAt: { type: String, attribute: "event-ends-at" },
  };

  constructor() {
    super();
    this.sessions = [];
    this.sessionKinds = [];
    this.approvedSubmissions = [];
    this.meetingMaxParticipants = {};
    this.meetingsEnabled = false;
    this.descriptionMaxLength = undefined;
    this.sessionNameMaxLength = undefined;
    this.locationMaxLength = undefined;
    this.disabled = false;
    this.eventStartsAt = "";
    this.eventEndsAt = "";
    this._bindHtmxCleanup();
  }

  connectedCallback() {
    super.connectedCallback();
    this._parseAttributes();
    this._initializeSessions();
  }

  /**
   * Parses JSON attributes from server templates.
   * @private
   */
  _parseAttributes() {
    if (typeof this.sessions === "string") {
      try {
        this.sessions = JSON.parse(this.sessions || "[]");
      } catch (_) {
        this.sessions = [];
      }
    }

    if (!Array.isArray(this.sessions) && this.sessions && typeof this.sessions === "object") {
      try {
        const values = Object.values(this.sessions);
        this.sessions = values.reduce((acc, v) => {
          if (Array.isArray(v)) acc.push(...v);
          return acc;
        }, []);
      } catch (_) {
        this.sessions = [];
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

    if (typeof this.approvedSubmissions === "string") {
      try {
        this.approvedSubmissions = JSON.parse(this.approvedSubmissions || "[]");
      } catch (_) {
        this.approvedSubmissions = [];
      }
    }
    if (!Array.isArray(this.approvedSubmissions)) this.approvedSubmissions = [];

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
   * Initializes sessions with IDs and converted timestamps.
   * @private
   */
  _initializeSessions() {
    if (this.sessions === null || this.sessions.length === 0) {
      this.sessions = [];
    } else {
      this.sessions = this.sessions.map((item, index) => {
        const toLocal = (ts) =>
          this.timezone
            ? convertTimestampToDateTimeLocalInTz(ts, this.timezone)
            : convertTimestampToDateTimeLocal(ts);
        return {
          ...this._createEmptySession(),
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
  _createEmptySession = () => ({
    id: this.sessions ? this.sessions.length : 0,
    name: "",
    description: "",
    kind: "",
    starts_at: "",
    ends_at: "",
    cfs_submission_id: "",
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
  });

  /**
   * Determines the current scenario based on event dates.
   * @returns {string} "no-dates" | "single-day" | "multi-day"
   * @private
   */
  _computeScenario() {
    if (!this.eventStartsAt || !this.eventEndsAt) {
      return "no-dates";
    }
    const startDate = extractDatePart(this.eventStartsAt);
    const endDate = extractDatePart(this.eventEndsAt);
    return startDate === endDate ? "single-day" : "multi-day";
  }

  /**
   * Computes all days between event start and end dates.
   * Uses string manipulation to avoid timezone issues with Date objects.
   * @returns {string[]} Array of date strings (e.g., ["2025-01-15", "2025-01-16"])
   * @private
   */
  _computeEventDays() {
    if (!this.eventStartsAt || !this.eventEndsAt) return [];

    const startDate = extractDatePart(this.eventStartsAt);
    const endDate = extractDatePart(this.eventEndsAt);
    const days = [];

    // Parse date parts as integers to avoid timezone issues
    let [year, month, day] = startDate.split("-").map(Number);
    const [endYear, endMonth, endDay] = endDate.split("-").map(Number);

    // Iterate through dates using simple arithmetic
    while (
      year < endYear ||
      (year === endYear && month < endMonth) ||
      (year === endYear && month === endMonth && day <= endDay)
    ) {
      const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
      days.push(dateStr);

      // Increment day and handle month/year overflow
      day++;
      const daysInMonth = new Date(year, month, 0).getDate();
      if (day > daysInMonth) {
        day = 1;
        month++;
        if (month > 12) {
          month = 1;
          year++;
        }
      }
    }

    return days;
  }

  /**
   * Groups sessions by their date.
   * @returns {Map<string, Array>} Map of date to sessions array
   * @private
   */
  _groupSessionsByDay() {
    const map = new Map();
    const days = this._computeEventDays();

    days.forEach((day) => map.set(day, []));

    this.sessions.forEach((session) => {
      const dayKey = extractDatePart(session.starts_at);
      if (dayKey && map.has(dayKey)) {
        map.get(dayKey).push(session);
      }
    });

    map.forEach((sessions) => {
      sessions.sort((a, b) => (a.starts_at || "").localeCompare(b.starts_at || ""));
    });

    return map;
  }

  /**
   * Returns sessions sorted by start time.
   * @returns {Array} Sorted sessions
   * @private
   */
  _getSortedSessions() {
    return [...this.sessions].sort((a, b) => (a.starts_at || "").localeCompare(b.starts_at || ""));
  }

  /**
   * Returns sessions outside of the current event date range.
   * @param {string[]} days - Event day strings
   * @returns {Array} Sessions outside range, sorted by start time
   * @private
   */
  _getOutOfRangeSessions(days) {
    const daySet = new Set(days);
    return this.sessions
      .filter((session) => !daySet.has(extractDatePart(session.starts_at)))
      .sort((a, b) => (a.starts_at || "").localeCompare(b.starts_at || ""));
  }

  /**
   * Opens the modal to add a new session.
   * @param {string} prefilledDate - Date to pre-fill for the session
   * @private
   */
  _openAddModal(prefilledDate = "") {
    if (this.disabled) return;
    const modal = this.querySelector("session-form-modal");
    if (modal) {
      modal.open(null, prefilledDate);
    }
  }

  /**
   * Opens the modal to edit an existing session.
   * @param {Object} session - Session to edit
   * @private
   */
  _openEditModal(session) {
    if (this.disabled) return;
    const modal = this.querySelector("session-form-modal");
    if (modal) {
      const prefilledDate = extractDatePart(session.starts_at);
      modal.open(session, prefilledDate);
    }
  }

  /**
   * Gets the next unique session ID.
   * @returns {number} Next session ID
   * @private
   */
  _getNextSessionId() {
    const maxId = this.sessions.reduce((currentMax, currentSession) => {
      const currentId = Number(currentSession?.id);
      if (!Number.isFinite(currentId)) return currentMax;
      return Math.max(currentMax, currentId);
    }, -1);
    return maxId + 1;
  }

  /**
   * Handles session saved event from modal.
   * @param {CustomEvent} event - Event with session data
   * @private
   */
  _handleSessionSaved = (event) => {
    const { session, isNew } = event.detail;
    if (isNew) {
      const newSession = {
        ...session,
        id: this._getNextSessionId(),
      };
      this.sessions = [...this.sessions, newSession];
    } else {
      this.sessions = this.sessions.map((s) => (s.id === session.id ? session : s));
    }
    this.requestUpdate();
  };

  /**
   * Deletes a session from the list.
   * @param {Object} session - Session to delete
   * @private
   */
  _deleteSession(session) {
    if (this.disabled) return;
    this.sessions = this.sessions.filter((s) => s.id !== session.id);
    this.requestUpdate();
  }

  /**
   * Gets the display name for a session kind.
   * @param {string} kindId - Session kind ID
   * @returns {string} Display name
   * @private
   */
  _getSessionKindDisplayName(kindId) {
    const kind = this.sessionKinds.find((k) => k.session_kind_id === kindId);
    return kind?.display_name || kindId || "";
  }

  /**
   * Renders the no-dates placeholder.
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderNoDatesPlaceholder() {
    return html`
      <div
        class="flex flex-col items-center justify-center py-12 px-6 bg-stone-50 border border-stone-200 rounded-lg"
      >
        <div class="svg-icon size-12 icon-calendar bg-stone-400 mb-4"></div>
        <div class="text-lg font-medium text-stone-700 mb-2">Sessions cannot be added yet</div>
        <p class="text-sm text-stone-500 text-center max-w-md">
          Please set the event start and end dates in the
          <span class="font-semibold">Date & Venue</span> tab first.
        </p>
      </div>
    `;
  }

  /**
   * Renders the empty state when no sessions exist.
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderEmptyState() {
    const message = this.disabled
      ? "No sessions were scheduled for this event."
      : 'No sessions scheduled yet. Click "Add session" to create one.';
    return html` <div class="text-sm text-stone-400 italic py-8 text-center">${message}</div> `;
  }

  /**
   * Renders the single-day view.
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderSingleDay() {
    const sortedSessions = this._getSortedSessions();
    const eventDate = extractDatePart(this.eventStartsAt);

    return html`
      <div class="space-y-4">
        <div class="flex items-start justify-between gap-4">
          <div class="text-sm/6 text-stone-500">
            Manage sessions for your event. Sessions are displayed sorted by start time.
          </div>
          <button
            type="button"
            class="btn-primary-outline btn-mini shrink-0 ${this.disabled
              ? "opacity-60 cursor-not-allowed"
              : ""}"
            @click=${() => this._openAddModal(eventDate)}
            ?disabled=${this.disabled}
          >
            Add session
          </button>
        </div>

        ${sortedSessions.length === 0
          ? this._renderEmptyState()
          : html`
              <div class="grid gap-3">
                ${repeat(
                  sortedSessions,
                  (s) => s.id,
                  (s) => html`
                    <session-card
                      .session=${s}
                      .sessionKinds=${this.sessionKinds}
                      .disabled=${this.disabled}
                      @edit=${() => this._openEditModal(s)}
                      @delete=${() => this._deleteSession(s)}
                    ></session-card>
                  `,
                )}
              </div>
            `}
      </div>
    `;
  }

  /**
   * Renders the multi-day view.
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderMultiDay() {
    const days = this._computeEventDays();
    const sessionsByDay = this._groupSessionsByDay();
    const outOfRangeSessions = this._getOutOfRangeSessions(days);

    return html`
      <div class="space-y-6">
        <div class="text-sm/6 text-stone-500">
          Manage sessions for each day of your event. Sessions are displayed sorted by start time.
        </div>

        ${days.map(
          (day) => html`
            <div class="border-t border-stone-200 pt-6 first:border-t-0 first:pt-0">
              <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-semibold text-stone-900">${formatDayHeader(day)}</h3>
                <button
                  type="button"
                  class="btn-primary-outline btn-mini ${this.disabled ? "opacity-60 cursor-not-allowed" : ""}"
                  @click=${() => this._openAddModal(day)}
                  ?disabled=${this.disabled}
                >
                  Add session
                </button>
              </div>

              ${sessionsByDay.get(day)?.length > 0
                ? html`
                    <div class="grid gap-3">
                      ${repeat(
                        sessionsByDay.get(day),
                        (s) => s.id,
                        (s) => html`
                          <session-card
                            .session=${s}
                            .sessionKinds=${this.sessionKinds}
                            .disabled=${this.disabled}
                            @edit=${() => this._openEditModal(s)}
                            @delete=${() => this._deleteSession(s)}
                          ></session-card>
                        `,
                      )}
                    </div>
                  `
                : html`
                    <div class="text-sm text-stone-400 italic py-4">No sessions scheduled for this day.</div>
                  `}
            </div>
          `,
        )}
        ${outOfRangeSessions.length > 0
          ? html`
              <div class="border-t border-stone-200 pt-6">
                <h3 class="text-lg font-semibold text-stone-900">Sessions outside event dates</h3>
                <p class="text-sm text-stone-500 mt-1">
                  These sessions do not match the event date range. You can edit or delete them.
                </p>
                <div class="grid gap-3 mt-4">
                  ${repeat(
                    outOfRangeSessions,
                    (s) => s.id,
                    (s) => html`
                      <session-card
                        .session=${s}
                        .sessionKinds=${this.sessionKinds}
                        .disabled=${this.disabled}
                        @edit=${() => this._openEditModal(s)}
                        @delete=${() => this._deleteSession(s)}
                      ></session-card>
                    `,
                  )}
                </div>
              </div>
            `
          : ""}
      </div>
    `;
  }

  /**
   * Renders hidden inputs for form submission.
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderHiddenInputs() {
    return html`
      ${this.sessions.map(
        (session, index) => html`
          <input type="hidden" name="sessions[${index}][session_id]" value=${session.session_id || ""} />
          <input type="hidden" name="sessions[${index}][name]" value=${session.name || ""} />
          <input type="hidden" name="sessions[${index}][kind]" value=${session.kind || ""} />
          <input type="hidden" name="sessions[${index}][starts_at]" value=${session.starts_at || ""} />
          <input type="hidden" name="sessions[${index}][ends_at]" value=${session.ends_at || ""} />
          <input type="hidden" name="sessions[${index}][location]" value=${session.location || ""} />
          <input type="hidden" name="sessions[${index}][description]" value=${session.description || ""} />
          <input
            type="hidden"
            name="sessions[${index}][cfs_submission_id]"
            value=${session.cfs_submission_id || ""}
          />
          <input
            type="hidden"
            name="sessions[${index}][meeting_join_url]"
            value=${session.meeting_join_url || ""}
          />
          <input
            type="hidden"
            name="sessions[${index}][meeting_recording_url]"
            value=${session.meeting_recording_url || ""}
          />
          <input
            type="hidden"
            name="sessions[${index}][meeting_requested]"
            value=${session.meeting_requested || false}
          />
          <input
            type="hidden"
            name="sessions[${index}][meeting_provider_id]"
            value=${session.meeting_provider_id || ""}
          />
          ${(session.speakers || []).map(
            (speaker, speakerIndex) => html`
              <input
                type="hidden"
                name="sessions[${index}][speakers][${speakerIndex}][user_id]"
                value=${speaker.user_id || ""}
              />
              <input
                type="hidden"
                name="sessions[${index}][speakers][${speakerIndex}][featured]"
                value=${speaker.featured || false}
              />
            `,
          )}
        `,
      )}
    `;
  }

  render() {
    const scenario = this._computeScenario();
    const usedSubmissionIds = this.sessions.map((s) => s.cfs_submission_id).filter((id) => id);

    return html`
      <div id="sessions-section">
        ${scenario === "no-dates"
          ? this._renderNoDatesPlaceholder()
          : scenario === "single-day"
            ? this._renderSingleDay()
            : this._renderMultiDay()}
      </div>

      ${this._renderHiddenInputs()}

      <session-form-modal
        .sessionKinds=${this.sessionKinds}
        .approvedSubmissions=${this.approvedSubmissions}
        .usedSubmissionIds=${usedSubmissionIds}
        .meetingMaxParticipants=${this.meetingMaxParticipants}
        .meetingsEnabled=${this.meetingsEnabled}
        .descriptionMaxLength=${this.descriptionMaxLength}
        .sessionNameMaxLength=${this.sessionNameMaxLength}
        .locationMaxLength=${this.locationMaxLength}
        .disabled=${this.disabled}
        @session-saved=${this._handleSessionSaved}
      ></session-form-modal>
    `;
  }

  /**
   * Removes empty session parameters before HTMX submits the form.
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
 * Session card component for displaying session summary.
 * @extends LitWrapper
 */
class SessionCard extends LitWrapper {
  /**
   * Component properties definition.
   * @property {Object} session - Session entry displayed by the card.
   * @property {Array} sessionKinds - Available session kinds.
   * @property {boolean} disabled - Whether actions are disabled.
   */
  static properties = {
    session: { type: Object },
    sessionKinds: { type: Array },
    disabled: { type: Boolean },
  };

  constructor() {
    super();
    this.session = {};
    this.sessionKinds = [];
    this.disabled = false;
  }

  /**
   * Gets the display name for a session kind.
   * @param {string} kindId - Session kind ID
   * @returns {string} Display name
   * @private
   */
  _getSessionKindDisplayName(kindId) {
    const kind = this.sessionKinds.find((k) => k.session_kind_id === kindId);
    return kind?.display_name || kindId || "";
  }

  _onEdit() {
    this.dispatchEvent(new CustomEvent("edit", { bubbles: true, composed: true }));
  }

  _onDelete() {
    this.dispatchEvent(new CustomEvent("delete", { bubbles: true, composed: true }));
  }

  render() {
    const { session } = this;
    const startTime = formatTimeDisplay(session.starts_at);
    const endTime = formatTimeDisplay(session.ends_at);
    const kindName = this._getSessionKindDisplayName(session.kind);
    const hasApprovedProposal = Boolean(session.cfs_submission_id);

    return html`
      <div
        class="flex w-full min-w-0 items-center gap-4 p-4 border border-stone-200 rounded-lg bg-white hover:border-stone-300 transition-colors overflow-hidden"
      >
        <div class="flex items-center gap-3 shrink-0">
          <div class="text-right w-14">
            <div class="text-sm font-medium text-stone-700">${startTime || "--:--"}</div>
            <div class="text-sm text-stone-400">${endTime || "--:--"}</div>
          </div>
          <div class="w-0.5 h-10 bg-primary-300 rounded-full"></div>
        </div>

        <div class="flex-1 w-0 min-w-0 overflow-hidden">
          <div class="font-medium text-stone-900 truncate w-full">${session.name || "Untitled Session"}</div>
          <div class="text-sm text-stone-500 truncate w-full">
            ${kindName}${session.location ? html` · ${session.location}` : ""}
          </div>
        </div>

        <div class="flex items-center gap-3 shrink-0">
          ${hasApprovedProposal
            ? html`<span class="custom-badge px-2.5 py-0.5 uppercase shrink-0"> Approved proposal </span>`
            : ""}
          <div class="flex items-center gap-1 shrink-0">
            <button
              type="button"
              class="p-2 rounded-full hover:bg-stone-100 transition-colors ${this.disabled
                ? "opacity-60 cursor-not-allowed"
                : ""}"
              title="Edit"
              @click=${this._onEdit}
              ?disabled=${this.disabled}
            >
              <div class="svg-icon size-4 icon-pencil bg-stone-600"></div>
            </button>
            <button
              type="button"
              class="p-2 rounded-full hover:bg-red-50 transition-colors ${this.disabled
                ? "opacity-60 cursor-not-allowed"
                : ""}"
              title="Delete"
              @click=${this._onDelete}
              ?disabled=${this.disabled}
            >
              <div class="svg-icon size-4 icon-trash bg-stone-600 hover:bg-red-600"></div>
            </button>
          </div>
        </div>
      </div>
    `;
  }
}
customElements.define("session-card", SessionCard);

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
    this._onKeydown = this._onKeydown.bind(this);
  }

  connectedCallback() {
    super.connectedCallback();
    document.addEventListener("keydown", this._onKeydown);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    if (this._isOpen) {
      unlockBodyScroll();
    }
    document.removeEventListener("keydown", this._onKeydown);
  }

  /**
   * Creates a new empty session.
   * @returns {Object} Empty session
   * @private
   */
  _createEmptySession() {
    return {
      id: Date.now(),
      name: "",
      description: "",
      kind: "",
      starts_at: "",
      ends_at: "",
      cfs_submission_id: "",
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
  }

  /**
   * Opens the modal for adding or editing a session.
   * @param {Object|null} session - Session to edit, or null for new session
   * @param {string} prefilledDate - Date to pre-fill for the session
   */
  open(session = null, prefilledDate = "") {
    this._isNewSession = !session;
    this._session = session ? { ...session } : this._createEmptySession();
    this._prefilledDate = prefilledDate;
    this._isOpen = true;
    lockBodyScroll();
  }

  /**
   * Closes the modal.
   */
  close() {
    if (!this._isOpen) return;
    this._isOpen = false;
    this._session = null;
    this._prefilledDate = "";
    unlockBodyScroll();
  }

  /**
   * Handles Escape key to close modal.
   * @param {KeyboardEvent} event
   * @private
   */
  _onKeydown(event) {
    if (event.key === "Escape" && this._isOpen) {
      this.close();
    }
  }

  /**
   * Handles session data changes from SessionItem.
   * @param {Object} data - Updated session data
   * @private
   */
  _onDataChange = (data) => {
    this._session = data;
  };

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
        class="fixed inset-0 flex items-center justify-center z-[1000]"
        role="dialog"
        aria-modal="true"
        aria-labelledby="session-form-modal-title"
      >
        <div class="absolute inset-0 bg-stone-950 opacity-35" @click=${() => this.close()}></div>
        <div class="relative p-4 w-full max-w-6xl max-h-[90vh] overflow-hidden">
          <div
            class="relative bg-white rounded-2xl shadow-lg flex flex-col overflow-hidden"
            style="max-height: calc(90vh - 2rem)"
          >
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

            <div class="p-6 overflow-y-auto min-h-0 flex-1">
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
   * Handles time input changes when date is pre-filled.
   * @param {Event} event - Input event
   * @param {string} field - Field name (starts_at or ends_at)
   * @private
   */
  _onTimeChange = (event, field) => {
    if (this.disabled) return;
    const time = event.target.value;
    const datetime = combineDateAndTime(this.prefilledDate, time);

    this.data = { ...this.data, [field]: datetime };
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
    const speakers = normalizeSpeakers(event.detail?.speakers || []);
    this.data = { ...this.data, speakers };
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  };

  /**
   * Handles input mode radio button changes.
   * @param {Event} event - Change event from radio input
   * @private
   */
  _onModeChange = (event) => {
    if (this.disabled) return;
    const newMode = event.target.value;
    this.inputMode = newMode;

    if (newMode === "cfs") {
      this.data = { ...this.data, description: "", speakers: [] };
    } else {
      this.data = { ...this.data, cfs_submission_id: "" };
    }

    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
    this.requestUpdate();
  };

  render() {
    const usedSubmissionIds = new Set((this.usedSubmissionIds || []).map((id) => String(id)));
    const currentSubmissionId = this.data?.cfs_submission_id ? String(this.data.cfs_submission_id) : "";
    const hasPrefilledDate = !!this.prefilledDate;
    const startTime = extractTimePart(this.data.starts_at);
    const endTime = extractTimePart(this.data.ends_at);
    const sessionNameMaxLength = Number(this.sessionNameMaxLength) || -1;
    const locationMaxLength = Number(this.locationMaxLength) || -1;

    return html` <div class="grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6 w-full">
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
            .maxLength=${sessionNameMaxLength}
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
          ${hasPrefilledDate
            ? html`
                <input
                  type="time"
                  @input=${(e) => this._onTimeChange(e, "starts_at")}
                  class="input-primary ${this.disabled
                    ? "bg-stone-100 text-stone-500 cursor-not-allowed"
                    : ""}"
                  value=${startTime}
                  ?required=${!this.isObjectEmpty}
                  ?disabled=${this.disabled}
                />
              `
            : html`
                <input
                  type="datetime-local"
                  @input=${(e) => this._onInputChange(e)}
                  data-name="starts_at"
                  name="sessions[${this.index}][starts_at]"
                  class="input-primary ${this.disabled
                    ? "bg-stone-100 text-stone-500 cursor-not-allowed"
                    : ""}"
                  value=${this.data.starts_at || ""}
                  ?required=${!this.isObjectEmpty}
                  ?disabled=${this.disabled}
                />
              `}
        </div>
      </div>

      <div class="col-span-2">
        <label class="form-label"> End Time </label>
        <div class="mt-2">
          ${hasPrefilledDate
            ? html`
                <input
                  type="time"
                  @input=${(e) => this._onTimeChange(e, "ends_at")}
                  class="input-primary ${this.disabled
                    ? "bg-stone-100 text-stone-500 cursor-not-allowed"
                    : ""}"
                  value=${endTime}
                  ?disabled=${this.disabled}
                />
              `
            : html`
                <input
                  type="datetime-local"
                  @input=${(e) => this._onInputChange(e)}
                  data-name="ends_at"
                  name="sessions[${this.index}][ends_at]"
                  class="input-primary ${this.disabled
                    ? "bg-stone-100 text-stone-500 cursor-not-allowed"
                    : ""}"
                  value=${this.data.ends_at || ""}
                  ?disabled=${this.disabled}
                />
              `}
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
            .maxLength=${locationMaxLength}
            ?disabled=${this.disabled}
          />
        </div>
      </div>

      ${this.approvedSubmissions?.length
        ? html`
            <div class="col-span-full">
              <label class="form-label">Session details</label>
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
                    class="h-full rounded-xl border transition bg-white p-4 md:p-5 flex ${this.inputMode ===
                    "cfs"
                      ? "border-primary-400 ring-2 ring-primary-200"
                      : "border-stone-200"} ${this.disabled
                      ? "opacity-60 cursor-not-allowed"
                      : "hover:border-primary-300"}"
                  >
                    <div class="flex items-start gap-3">
                      <span class="mt-1 inline-flex">
                        <span
                          class="relative flex h-5 w-5 items-center justify-center rounded-full border ${this
                            .inputMode === "cfs"
                            ? "border-primary-500"
                            : "border-stone-300"}"
                        >
                          ${this.inputMode === "cfs"
                            ? html`<span class="h-2.5 w-2.5 rounded-full bg-primary-500"></span>`
                            : ""}
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
                    class="h-full rounded-xl border transition bg-white p-4 md:p-5 flex ${this.inputMode ===
                    "manual"
                      ? "border-primary-400 ring-2 ring-primary-200"
                      : "border-stone-200"} ${this.disabled
                      ? "opacity-60 cursor-not-allowed"
                      : "hover:border-primary-300"}"
                  >
                    <div class="flex items-start gap-3">
                      <span class="mt-1 inline-flex">
                        <span
                          class="relative flex h-5 w-5 items-center justify-center rounded-full border ${this
                            .inputMode === "manual"
                            ? "border-primary-500"
                            : "border-stone-300"}"
                        >
                          ${this.inputMode === "manual"
                            ? html`<span class="h-2.5 w-2.5 rounded-full bg-primary-500"></span>`
                            : ""}
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
            </div>
          `
        : ""}
      ${this.inputMode === "cfs" && this.approvedSubmissions?.length
        ? html`
            <div class="col-span-full">
              <label class="form-label"> Link to CFS submission </label>
              <div class="mt-2">
                <select
                  @change=${(e) => this._onInputChange(e)}
                  data-name="cfs_submission_id"
                  name="sessions[${this.index}][cfs_submission_id]"
                  class="input-primary ${this.disabled
                    ? "bg-stone-100 text-stone-500 cursor-not-allowed"
                    : ""}"
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
        : ""}
      ${this.inputMode === "manual" || !this.approvedSubmissions?.length
        ? html`
            <div class="col-span-full">
              <label for="summary" class="form-label"> Description </label>
              <div class="mt-2">
                <markdown-editor
                  id="sessions[${this.index}][description]"
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
        : ""}
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
