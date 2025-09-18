import { html } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * Lightweight dropdown that loads group events on demand for attendee filtering.
 */
class EventSelector extends LitWrapper {
  /**
   * Component properties
   * - selectedEventId: currently applied event uuid
   * - selectedEvent: preloaded event payload to render selected label
   * - groupId: optional override group uuid
   * - buttonId: optional button id to control focus interactions
   * - hasEvents: indicates if the group has any events to fetch
   * - _isOpen: dropdown visibility flag
   * - _query: current search term
   * - _results: fetched events list
   * - _loading: remote fetch in progress indicator
   * - _error: remote fetch error message
   * - _activeIndex: highlighted result index for keyboard navigation
   */
  static properties = {
    selectedEventId: { type: String, attribute: "selected-event-id" },
    selectedEvent: {
      attribute: "selected-event",
      converter: {
        fromAttribute(value) {
          if (!value) return null;
          try {
            return JSON.parse(value);
          } catch (error) {
            console.warn("Invalid selected event payload", error);
            return null;
          }
        },
      },
    },
    groupId: { type: String, attribute: "group-id" },
    buttonId: { type: String, attribute: "button-id" },
    hasEvents: { type: Boolean, attribute: "has-events" },
    _isOpen: { state: true },
    _query: { state: true },
    _results: { state: true },
    _loading: { state: true },
    _error: { state: true },
    _activeIndex: { state: true },
  };

  constructor() {
    super();
    this.selectedEventId = "";
    this.selectedEvent = null;
    this.groupId = "";
    this.buttonId = "";
    this.hasEvents = false;
    this._isOpen = false;
    this._query = "";
    this._results = [];
    this._loading = false;
    this._error = "";
    this._hasFetched = false;
    this._activeIndex = -1;
    this._outsideHandler = (event) => {
      if (!this.contains(event.target)) {
        this._closeDropdown();
      }
    };
  }

  /**
   * Cleans listeners and pending work when detached.
   */
  disconnectedCallback() {
    super.disconnectedCallback();
    this._removeOutsideListener();
  }

  /**
   * Re-processes HTMX bindings whenever results change.
   * @param {Map<string, unknown>} changed Changed reactive props
   */
  updated(changed) {
    if (
      (changed.has("_results") || changed.has("_isOpen")) &&
      typeof window !== "undefined" &&
      window.htmx &&
      typeof window.htmx.process === "function"
    ) {
      this.updateComplete.then(() => {
        const buttons = this.querySelectorAll(".event-button");
        if (buttons.length === 0) {
          window.htmx.process(this);
          return;
        }
        buttons.forEach((button) => {
          button.removeAttribute("hx-processed");
          window.htmx.process(button);
          if (!button._eventSelectorBound) {
            button.addEventListener("htmx:beforeRequest", () => {
              this._closeDropdown();
            });
            button._eventSelectorBound = true;
          }
        });
      });
    }
  }

  /**
   * Handles query input changes with a debounce.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    this._query = event.target.value || "";
    this._activeIndex = -1;
    const trimmed = this._query.trim();
    if (trimmed.length > 2) {
      this._fetchEvents();
    } else {
      this._loading = false;
      this._results = [];
    }
  }

  /**
   * Keyboard navigation support for the search input.
   * @param {KeyboardEvent} event Triggering keyboard event
   */
  _handleInputKeydown(event) {
    if (!this._isOpen) {
      return;
    }

    if (event.key === "ArrowDown") {
      event.preventDefault();
      this._activeIndex = this._activeIndex < this._results.length - 1 ? this._activeIndex + 1 : 0;
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      this._activeIndex = this._activeIndex > 0 ? this._activeIndex - 1 : this._results.length - 1;
    } else if (event.key === "Enter") {
      event.preventDefault();
      this._selectActiveResult();
    } else if (event.key === "Escape") {
      event.preventDefault();
      this._closeDropdown();
    }
  }

  /**
   * Toggles dropdown visibility.
   * @param {MouseEvent} event Triggering click
   */
  _toggleDropdown(event) {
    event.preventDefault();
    if (!this.hasEvents) {
      return;
    }
    if (this._isOpen) {
      this._closeDropdown();
    } else {
      this._openDropdown();
    }
  }

  /**
   * Opens dropdown and performs the initial fetch when needed.
   */
  _openDropdown() {
    if (!this.hasEvents) {
      return;
    }
    if (this._isOpen) return;
    this._isOpen = true;
    this._addOutsideListener();
    this.updateComplete.then(() => {
      const input = this.querySelector("#event-search-input");
      if (input) {
        input.focus();
        input.select();
      }
    });
    if (!this._hasFetched) {
      const trimmed = this._query.trim();
      if (trimmed.length > 2) {
        this._fetchEvents();
        this._hasFetched = true;
      }
    }
  }

  /**
   * Closes dropdown and removes the outside listener.
   */
  _closeDropdown() {
    if (!this._isOpen) return;
    this._isOpen = false;
    this._removeOutsideListener();
    this._activeIndex = -1;
  }

  /**
   * Starts listening for clicks outside the dropdown.
   */
  _addOutsideListener() {
    document.addEventListener("click", this._outsideHandler);
  }

  /**
   * Removes the outside click listener.
   */
  _removeOutsideListener() {
    document.removeEventListener("click", this._outsideHandler);
  }

  /**
   * Queries remote events using the selected group id.
   */
  async _fetchEvents() {
    if (!this.hasEvents) {
      this._results = [];
      return;
    }
    const groupId = this._resolveGroupId();
    if (!groupId) {
      this._results = [];
      return;
    }
    this._loading = true;
    this._error = "";
    const params = new URLSearchParams();
    params.append("group", groupId);
    params.set("limit", "10");
    params.set("date_from", "2000-01-01");
    const trimmed = this._query.trim();
    if (trimmed.length <= 2) {
      this._results = [];
      this._loading = false;
      return;
    }
    params.set("ts_query", trimmed);

    try {
      const response = await fetch(`/explore/events/search?${params.toString()}`, {
        headers: {
          Accept: "application/json",
        },
      });
      if (!response.ok) {
        throw new Error("Failed to search events");
      }
      const payload = await response.json();
      const events = Array.isArray(payload?.events) ? payload.events : [];
      this._results = events;
      this._activeIndex = -1;
      this._hasFetched = true;
      if (this.selectedEventId) {
        const selectedId = String(this.selectedEventId);
        const match = events.find((item) => item.event_id === selectedId);
        if (match) {
          this.selectedEvent = match;
        }
      }
    } catch (error) {
      this._error = "Unable to load events";
    } finally {
      this._loading = false;
    }
  }

  /**
   * Determines which group id should be used for searches.
   * @returns {string}
   */
  _resolveGroupId() {
    if (this.groupId) {
      return this.groupId;
    }
    const selector = document.querySelector("group-selector");
    return selector?.getAttribute("selected-group-id") ?? "";
  }

  /**
   * Returns the event that matches the current selection.
   * @returns {object|null}
   */
  _findSelectedEvent() {
    const matchesSelected = (event) => {
      return event.event_id === String(this.selectedEventId ?? "");
    };

    if (!this.selectedEventId) {
      return this.selectedEvent;
    }

    if (this.selectedEvent && matchesSelected(this.selectedEvent)) {
      return this.selectedEvent;
    }

    const found = this._results.find((item) => matchesSelected(item));
    if (found) {
      this.selectedEvent = found;
      return found;
    }

    return this.selectedEvent;
  }

  /**
   * Formats an event date with month, day, year, time, and zone.
   * @param {object} event Event payload
   * @returns {{text: string, isPlaceholder: boolean}}
   */
  _formatEventDate(event) {
    if (!event || !event.starts_at) {
      return { text: "TBD", isPlaceholder: true };
    }
    try {
      const date = new Date(Number(event.starts_at) * 1000);
      const formatter = new Intl.DateTimeFormat("en-US", {
        month: "long",
        day: "numeric",
        year: "numeric",
        hour: "numeric",
        minute: "numeric",
        hour12: true,
        timeZone: event.timezone || "UTC",
        timeZoneName: "short",
      });
      const parts = formatter.formatToParts(date);
      const pick = (type) => parts.find((part) => part.type === type)?.value ?? "";
      const month = pick("month");
      const day = pick("day");
      const year = pick("year");
      const hour = pick("hour");
      const minute = pick("minute");
      const dayPeriod = pick("dayPeriod");
      const timeZoneName = pick("timeZoneName");

      const dateLabel = [month, day].filter(Boolean).join(" ");
      const dateWithYear = year ? `${dateLabel}${dateLabel ? ", " : ""}${year}` : dateLabel || year;
      const minuteLabel = minute ? minute.padStart(2, "0") : "00";
      const timeLabel = hour ? `${hour}:${minuteLabel}${dayPeriod ? ` ${dayPeriod}` : ""}` : "";
      const timeWithZone = [timeLabel, timeZoneName].filter(Boolean).join(" ");
      const text = [dateWithYear, timeWithZone].filter(Boolean).join(" · ");

      return { text: text || formatter.format(date), isPlaceholder: false };
    } catch (_error) {
      return { text: "-", isPlaceholder: false };
    }
  }

  /**
   * Ensures the toggle button has a stable id.
   * @returns {string}
   */
  _ensureButtonId() {
    if (this.buttonId) {
      return this.buttonId;
    }
    if (!this._generatedButtonId) {
      const randomChunk = Math.random().toString(36).slice(2, 10);
      this._generatedButtonId = `event-selector-${randomChunk}`;
    }
    return this._generatedButtonId;
  }

  /**
   * Builds the dropdown list content based on loading state.
   * @returns {import("lit").TemplateResult}
   */
  _renderDropdownContent() {
    if (this._error) {
      return html`<ul class="max-h-64 overflow-y-auto text-stone-700">
        <li class="px-4 py-4 text-sm text-stone-500">${this._error}</li>
      </ul>`;
    }
    if (!this._results || this._results.length === 0) {
      return html`<ul class="max-h-64 overflow-y-auto text-stone-700">
        <li class="px-4 py-4 text-sm text-stone-500">No events found</li>
      </ul>`;
    }
    return html`
      <ul class="max-h-64 overflow-y-auto text-stone-700">
        ${this._results.map((event, index) => this._renderEventOption(event, index))}
      </ul>
    `;
  }

  /**
   * Renders a single event option button.
   * @param {object} event Event payload
   * @returns {import("lit").TemplateResult}
   */
  _renderEventOption(event, index) {
    const isSelected = this.selectedEventId && String(this.selectedEventId) === String(event.event_id);
    const isActive = index === this._activeIndex;
    let status = "";
    if (isActive && !isSelected) {
      status = "bg-stone-50";
    }
    if (isSelected) {
      status = "bg-stone-100";
    }

    return html`
      <li>
        <button
          id="select-event-${event.event_id}"
          type="button"
          class="event-button cursor-pointer w-full flex items-center justify-between px-4 py-2 text-sm/6 text-left hover:bg-stone-100 ${status}"
          ?disabled="${isSelected}"
          hx-get="/dashboard/group/attendees?event_id=${event.event_id}"
          hx-target="#dashboard-content"
          hx-indicator="#dashboard-spinner"
          hx-swap="innerHTML show:body:top"
          hx-disabled-elt=".event-button"
          @mouseenter="${() => {
            this._activeIndex = index;
          }}"
        >
          ${this._renderEventPreview(event)}
        </button>
      </li>
    `;
  }

  /**
   * Generates the label block shown for an event.
   * @param {object} event Event payload
   * @returns {import("lit").TemplateResult}
   */
  _renderEventPreview(event) {
    const formattedDate = this._formatEventDate(event);
    return html`
      <div class="flex flex-col min-w-0 pe-6 items-start">
        <div class="max-w-full truncate">${event.name ?? ""}</div>
        <div class="text-xs ${formattedDate.isPlaceholder ? "text-stone-400" : "text-stone-500"} truncate">
          ${formattedDate.text}
        </div>
      </div>
    `;
  }

  /**
   * Clears the search input and resets local results.
   */
  _clearSearch() {
    this._query = "";
    this._results = [];
    this._loading = false;
    this._error = "";
    this._activeIndex = -1;
    this._hasFetched = false;
    const input = this.querySelector("#event-search-input");
    if (input) {
      input.value = "";
      input.focus();
    }
  }

  /**
   * Triggers selection of the highlighted result.
   */
  _selectActiveResult() {
    if (this._activeIndex < 0 || this._activeIndex >= this._results.length) {
      return;
    }
    const active = this._results[this._activeIndex];
    if (!active) {
      return;
    }
    const button = document.getElementById(`select-event-${active.event_id}`);
    if (button && !button.disabled && typeof button.click === "function") {
      button.click();
    }
  }

  /**
   * Primary render entrypoint.
   * @returns {import("lit").TemplateResult}
   */
  render() {
    const buttonId = this._ensureButtonId();
    const selectedEvent = this._findSelectedEvent();

    if (!this.hasEvents) {
      return html`
        <button
          id="${buttonId}"
          class="select select-primary w-full opacity-50 cursor-not-allowed
                 text-left"
          aria-label="No events"
          disabled
        >
          <div class="flex items-center relative">
            <div class="min-w-0">
              <div class="max-w-full truncate text-stone-500">No events</div>
              <div class="text-xs text-stone-500 truncate">Create an event to view attendees</div>
            </div>
          </div>
        </button>
      `;
    }

    return html`
      <button
        id="${buttonId}"
        class="relative cursor-pointer select select-primary w-full
               text-left pe-9"
        aria-label="Select event"
        @click="${(event) => this._toggleDropdown(event)}"
      >
        ${selectedEvent
          ? this._renderEventPreview(selectedEvent)
          : html`<div class="flex flex-col min-w-0">
              <div class="max-w-full truncate">Select event</div>
              <div class="text-xs text-stone-500 truncate">Choose an event to view attendees</div>
            </div>`}
        <div class="absolute inset-y-0 end-0 flex items-center pe-3 pointer-events-none gap-2">
          ${this._loading
            ? html`<div role="status" class="flex size-5">
                <img
                  src="/static/images/spinner/spinner_1.svg"
                  height="auto"
                  width="auto"
                  alt="Loading spinner"
                  class="size-auto animate-spin"
                />
                <span class="sr-only">Loading...</span>
              </div>`
            : ""}
          <div class="svg-icon size-3 icon-caret-down bg-stone-600"></div>
        </div>
      </button>
      <div
        id="dropdown-events"
        class="${this._isOpen
          ? ""
          : "hidden"} absolute top-22 start-0 w-full z-10 bg-white rounded-lg shadow-sm border border-stone-200"
      >
        <div class="p-3 border-b border-stone-200">
          <div class="relative">
            <div
              class="absolute inset-y-0 start-0 flex items-center ps-3
                     pointer-events-none"
            >
              <div class="svg-icon size-4 icon-search bg-stone-300"></div>
            </div>
            <input
              id="event-search-input"
              type="text"
              class="input-primary w-full ps-9 pe-9"
              placeholder="Search events"
              autocomplete="off"
              autocorrect="off"
              autocapitalize="off"
              spellcheck="false"
              value="${this._query}"
              @input="${(event) => this._handleSearchInput(event)}"
              @keydown="${(event) => this._handleInputKeydown(event)}"
            />
            ${this._query.trim().length > 0
              ? html`<button
                  type="button"
                  class="absolute inset-y-0 end-2 flex items-center"
                  @click="${() => this._clearSearch()}"
                >
                  <div class="svg-icon size-4 icon-close bg-stone-400 hover:bg-stone-600"></div>
                  <span class="sr-only">Clear search</span>
                </button>`
              : null}
          </div>
        </div>
        ${this._renderDropdownContent()}
      </div>
    `;
  }
}

customElements.define("event-selector", EventSelector);
