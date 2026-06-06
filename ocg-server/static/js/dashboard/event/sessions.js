import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import {
  convertTimestampToDateTimeLocal,
  convertTimestampToDateTimeLocalInTz,
} from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/dashboard/event/session-card.js";
import "/static/js/dashboard/event/session-form-modal.js";
import {
  parseArrayAttribute,
  parseObjectAttribute,
  parseSessionsAttribute,
} from "/static/js/dashboard/event/sessions-attributes.js";
import { extractDatePart, formatDayHeader } from "/static/js/dashboard/event/sessions-datetime.js";
import {
  computeEventDays,
  computeSessionScenario,
  createEmptySession,
  getNextSessionId,
  getOutOfRangeSessions,
  getSortedSessions,
  groupSessionsByDay,
} from "/static/js/dashboard/event/sessions-schedule.js";
import { renderSessionsHiddenInputs } from "/static/js/dashboard/event/sessions-hidden-inputs.js";

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
    this.sessions = parseSessionsAttribute(this.sessions);
    this.sessionKinds = parseArrayAttribute(this.sessionKinds);
    this.approvedSubmissions = parseArrayAttribute(this.approvedSubmissions);
    this.meetingMaxParticipants = parseObjectAttribute(this.meetingMaxParticipants);
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
        const meetingProviderId = item.meeting_provider_id || item.meeting_provider || "";
        return {
          ...createEmptySession(index),
          ...item,
          meeting_provider_id: meetingProviderId,
          id: index,
          starts_at: toLocal(item.starts_at),
          ends_at: toLocal(item.ends_at),
        };
      });
    }
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
   * Handles session saved event from modal.
   * @param {CustomEvent} event - Event with session data
   * @private
   */
  _handleSessionSaved = (event) => {
    const { session, isNew } = event.detail;
    if (isNew) {
      const newSession = {
        ...session,
        id: getNextSessionId(this.sessions),
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
   * Renders session cards as a grid.
   * @param {Array} sessions - Sessions to render
   * @param {string} [gridClass] - Grid classes for wrapper spacing
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderSessionsGrid(sessions, gridClass = "grid gap-3 pt-3") {
    return html`
      <div class="${gridClass}">
        ${repeat(
          sessions,
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
    `;
  }

  /**
   * Renders a day section with sessions and add button.
   * @param {object} options - Day section options
   * @param {string} options.day - Day key in YYYY-MM-DD format
   * @param {Array} options.sessions - Sessions for the day
   * @param {string} [options.containerClass] - Wrapper spacing classes
   * @param {string} [options.buttonClass] - Additional button classes
   * @param {import('lit').TemplateResult} options.emptyContent - Empty state content
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderDaySection({ day, sessions, containerClass = "", buttonClass = "", emptyContent }) {
    return html`
      <div class="${containerClass}">
        <div class="flex items-center justify-between mb-6">
          <h3 class="text-lg font-semibold text-stone-900">${formatDayHeader(day)}</h3>
          <button
            type="button"
            class="btn-primary-outline btn-mini ${buttonClass} ${this.disabled
              ? "opacity-60 cursor-not-allowed"
              : ""}"
            @click=${() => this._openAddModal(day)}
            ?disabled=${this.disabled}
          >
            Add session
          </button>
        </div>

        ${sessions.length === 0 ? emptyContent : this._renderSessionsGrid(sessions)}
      </div>
    `;
  }

  /**
   * Renders the single-day view.
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderSingleDay() {
    const sortedSessions = getSortedSessions(this.sessions);
    const eventDate = extractDatePart(this.eventStartsAt);

    return html`
      <div class="space-y-4">
        <div class="text-sm/6 text-stone-500">
          Manage sessions for your event. Sessions are displayed sorted by start time.
        </div>

        ${this._renderDaySection({
          day: eventDate,
          sessions: sortedSessions,
          containerClass: "pt-4",
          buttonClass: "shrink-0",
          emptyContent: this._renderEmptyState(),
        })}
      </div>
    `;
  }

  /**
   * Renders the multi-day view.
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderMultiDay() {
    const days = computeEventDays(this.eventStartsAt, this.eventEndsAt);
    const sessionsByDay = groupSessionsByDay(this.sessions, days);
    const outOfRangeSessions = getOutOfRangeSessions(this.sessions, days);

    return html`
      <div class="space-y-6">
        <div class="text-sm/6 text-stone-500">
          Manage sessions for each day of your event. Sessions are displayed sorted by start time.
        </div>

        ${days.map((day) =>
          this._renderDaySection({
            day,
            sessions: sessionsByDay.get(day) || [],
            containerClass: "pt-8 first:pt-0",
            emptyContent: html`
              <div class="text-sm text-stone-400 italic py-4">No sessions scheduled for this day.</div>
            `,
          }),
        )}
        ${outOfRangeSessions.length > 0
          ? html`
              <div class="border-t border-stone-200 pt-6">
                <h3 class="text-lg font-semibold text-stone-900">Sessions outside event dates</h3>
                <p class="text-sm text-stone-500 mt-1">
                  These sessions do not match the event date range. You can edit or delete them.
                </p>
                ${this._renderSessionsGrid(outOfRangeSessions, "grid gap-3 mt-4")}
              </div>
            `
          : ""}
      </div>
    `;
  }

  render() {
    const scenario = computeSessionScenario(this.eventStartsAt, this.eventEndsAt);
    const usedSubmissionIds = this.sessions.map((s) => s.cfs_submission_id).filter((id) => id);

    return html`
      <div id="sessions-section">
        ${scenario === "no-dates"
          ? this._renderNoDatesPlaceholder()
          : scenario === "single-day"
            ? this._renderSingleDay()
            : this._renderMultiDay()}
      </div>

      ${renderSessionsHiddenInputs(this.sessions)}

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
