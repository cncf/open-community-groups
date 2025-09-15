import { html, repeat } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { isObjectEmpty, convertTimestampToDateTimeLocal } from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/user-search-selector.js";

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
   *  - recording_url: URL for session recording (optional)
   *  - streaming_url: URL for session live stream (optional)
   *  - speakers: Session speakers (array, handled separately)
   */
  static properties = {
    sessions: { type: Array },
    // List of available session kinds to render options
    sessionKinds: { type: Array, attribute: "session-kinds" },
  };

  constructor() {
    super();
    this.sessions = [];
    this.sessionKinds = [];
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
        return {
          ...this._getData(),
          ...item,
          id: index,
          starts_at: convertTimestampToDateTimeLocal(item.starts_at),
          ends_at: convertTimestampToDateTimeLocal(item.ends_at),
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
      recording_url: "",
      streaming_url: "",
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
      <div class="flex w-full xl:w-2/3">
        <div class="flex flex-col space-y-3 me-3">
          <div>
            <button
              @click=${() => this._addSessionItem(index)}
              type="button"
              class="cursor-pointer p-2 border border-stone-200 hover:bg-stone-100 rounded-full"
              title="Add above"
            >
              <div class="svg-icon size-4 icon-plus-top bg-stone-600"></div>
            </button>
          </div>
          <div>
            <button
              @click=${() => this._addSessionItem(index + 1)}
              type="button"
              class="cursor-pointer p-2 border border-stone-200 hover:bg-stone-100 rounded-full"
              title="Add below"
            >
              <div class="svg-icon size-4 icon-plus-bottom bg-stone-600"></div>
            </button>
          </div>
          <div>
            <button
              @click=${() => this._removeSessionItem(index)}
              type="button"
              class="cursor-pointer p-2 border border-stone-200 hover:bg-stone-100 rounded-full"
              title="${hasSingleSessionItem ? "Clean" : "Delete"}"
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
          .onDataChange=${this._onDataChange}
          class="w-full"
        ></session-item>
      </div>
    </div>`;
  }

  render() {
    return html` <div class="text-sm/6 text-stone-500">
        Add sessions for your event. You can add additional sessions by clicking on the
        <span class="font-semibold">+</span> buttons on the left of the card (
        <div class="inline-block svg-icon size-4 icon-plus-top bg-stone-600 relative -bottom-[2px]"></div>
        to add the new session above,
        <div class="inline-block svg-icon size-4 icon-plus-bottom bg-stone-600 relative -bottom-[2px]"></div>
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
}
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
      recording_url: "",
      streaming_url: "",
      speakers: [],
    };
    this.index = 0;
    this.isObjectEmpty = true;
    this.onDataChange = () => {};
    this.sessionKinds = [];
  }

  connectedCallback() {
    super.connectedCallback();
    this.isObjectEmpty = isObjectEmpty(this.data);
  }

  /**
   * Handles input field changes.
   * @param {Event} event - Input event
   * @private
   */
  _onInputChange = (event) => {
    const value = event.target.value;
    const name = event.target.dataset.name;

    this.data[name] = value;
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
  };

  /**
   * Handles markdown editor changes.
   * @param {string} value - Updated markdown content
   * @private
   */
  _onTextareaChange = (value) => {
    this.data.description = value;
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
  };

  render() {
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
            class="input-primary"
            value="${this.data.name}"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            ?required=${!this.isObjectEmpty}
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
            class="input-primary"
            ?required=${!this.isObjectEmpty}
          >
            <option value="" ?selected=${!this.data.kind}>Select type</option>
            ${this.sessionKinds.map(
              (k) =>
                html`<option value="${k.session_kind_id}" ?selected=${this.data.kind === k.session_kind_id}>
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
            class="input-primary"
            value="${this.data.starts_at || ""}"
            ?required=${!this.isObjectEmpty}
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
            class="input-primary"
            value="${this.data.ends_at || ""}"
          />
        </div>
      </div>

      <div class="col-span-full">
        <label for="summary" class="form-label"> Description </label>
        <div class="mt-2">
          <markdown-editor
            id="sessions[${this.index}][description]"
            name="sessions[${this.index}][description]"
            content="${this.data.description}"
            .onChange="${(value) => this._onTextareaChange(value)}"
            mini
          ></markdown-editor>
        </div>
      </div>

      <div class="col-span-full">
        <label class="form-label">Speakers</label>
        <div class="mt-2">
          <user-search-selector
            field-name="sessions[${this.index}][speakers]"
            dashboard-type="group"
            label="speaker"
            .selectedUsers=${this.data.speakers || []}
            legend="Add speakers or presenters for this session."
          ></user-search-selector>
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
            value="${this.data.location}"
            placeholder="Optional - physical location or meeting room"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
          />
        </div>
      </div>

      <div class="col-span-3">
        <label class="form-label"> Recording URL </label>
        <div class="mt-2">
          <input
            @input=${(e) => this._onInputChange(e)}
            data-name="recording_url"
            type="url"
            name="sessions[${this.index}][recording_url]"
            class="input-primary"
            value="${this.data.recording_url}"
            placeholder="Optional - link to recorded session"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
          />
        </div>
      </div>

      <div class="col-span-3">
        <label class="form-label"> Streaming URL </label>
        <div class="mt-2">
          <input
            @input=${(e) => this._onInputChange(e)}
            data-name="streaming_url"
            type="url"
            name="sessions[${this.index}][streaming_url]"
            class="input-primary"
            value="${this.data.streaming_url}"
            placeholder="Optional - link to live stream"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
          />
        </div>
      </div>
    </div>`;
  }
}
customElements.define("session-item", SessionItem);
