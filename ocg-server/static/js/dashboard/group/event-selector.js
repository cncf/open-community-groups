import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { showErrorAlert, showInfoAlert } from "/static/js/common/alerts.js";
import { setImageFieldValue, setSelectValue, setTextValue } from "/static/js/common/utils.js";
import * as formHelpers from "/static/js/dashboard/group/event-form-helpers.js";
import "/static/js/common/svg-spinner.js";

/**
 * Lightweight dropdown that loads group events on demand and populates the event form
 * with selected event details for copying.
 */
class EventSelector extends LitWrapper {
  dateFrom = "2000-01-01";

  /**
   * Component properties
   * - selectedEventId: currently applied event uuid
   * - selectedEvent: preloaded event payload to render selected label
   * - groupId: optional override group uuid
   * - community: community slug for event search
   * - groupSlug: group slug for event search
   * - buttonId: optional button id to control focus interactions
   * - _isOpen: dropdown visibility flag
   * - _query: current search term
   * - _results: fetched events list
   * - _loading: remote fetch in progress indicator
   * - _copyLoading: copy fetch in progress indicator
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
    community: { type: String, attribute: "community" },
    groupSlug: { type: String, attribute: "group-slug" },
    buttonId: { type: String, attribute: "button-id" },
    _isOpen: { state: true },
    _query: { state: true },
    _results: { state: true },
    _loading: { state: true },
    _copyLoading: { state: true },
    _error: { state: true },
    _activeIndex: { state: true },
  };

  constructor() {
    super();
    this.selectedEventId = "";
    this.selectedEvent = null;
    this.groupId = "";
    this.community = "";
    this.groupSlug = "";
    this.buttonId = "";
    this._isOpen = false;
    this._query = "";
    this._results = [];
    this._loading = false;
    this._copyLoading = false;
    this._error = "";
    this._hasFetched = false;
    this._activeIndex = -1;
    this._primaryResults = [];
    this._primaryFetchPromise = null;
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
   * Re-syncs selected event state when properties change.
   * @param {Map<string, unknown>} changed Changed reactive props
   */
  updated(changed) {
    if (changed.has("selectedEvent")) {
      this._syncSelectedEvent();
    }
    if (changed.has("selectedEventId") && !this.selectedEvent) {
      this._hasFetched = false;
      this._primaryResults = [];
    }
    if (changed.has("groupId") || changed.has("community") || changed.has("groupSlug")) {
      this._hasFetched = false;
      this._primaryResults = [];
    }
  }

  /**
   * Handles query input changes with a debounce.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    this._query = event.target.value || "";
    this._activeIndex = -1;
    this._fetchEvents();
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
   * Handles selection click to copy event details into the form.
   * @param {MouseEvent} event Triggering click
   * @param {object} eventData Selected event
   */
  async _handleEventClick(event, eventData) {
    event.preventDefault();
    event.stopImmediatePropagation();
    await this._handleCopyMode(eventData);
  }

  /**
   * Toggles dropdown visibility.
   * @param {MouseEvent} event Triggering click
   */
  _toggleDropdown(event) {
    event.preventDefault();
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
      this._fetchEvents();
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
   * Executes copy mode flow: fetch details and populate the form.
   * @param {object} eventData Selected event data
   */
  async _handleCopyMode(eventData) {
    const eventId = eventData?.event_id;
    if (!eventId || this._copyLoading) {
      return;
    }
    this._setCopyLoading(true);
    try {
      const details = await this._fetchEventDetails(eventId);
      this._applyEventDetails(details);
      this._updateSelectorAfterCopy(details);
      this._closeDropdown();
      this._scrollToTop();
      this._showCopySuccess();
    } catch (error) {
      console.error("Failed to copy event", error);
      this._showCopyError();
    } finally {
      this._setCopyLoading(false);
    }
  }

  /**
   * Shows or hides the copy loading indicator.
   * @param {boolean} loading Loading state
   */
  _setCopyLoading(loading) {
    this._copyLoading = loading;
    const indicator = document.querySelector("[data-copy-indicator]");
    if (indicator) {
      indicator.classList.toggle("hidden", !loading);
    }
    const triggerButton = document.getElementById(this.buttonId);
    if (triggerButton) {
      if (loading) {
        triggerButton.setAttribute("aria-busy", "true");
      } else {
        triggerButton.removeAttribute("aria-busy");
      }
    }
  }

  /**
   * Fetches full event details for copying.
   * @param {string} eventId Event identifier
   * @returns {Promise<object>}
   */
  async _fetchEventDetails(eventId) {
    const url = `/dashboard/group/events/${encodeURIComponent(eventId)}/details`;
    const response = await fetch(url, {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
    });
    if (!response.ok) {
      throw new Error(`Failed to fetch event ${eventId}`);
    }
    return response.json();
  }

  /**
   * Applies copied event details into the form.
   * @param {object} details Event details payload
   */
  _applyEventDetails(details) {
    if (!details || typeof details !== "object") {
      return;
    }
    this._resetMeetingFields();
    const {
      appendCopySuffix,
      setCategoryValue,
      setEventReminderEnabled,
      setGalleryImages,
      setTags,
      setRegistrationRequired,
      updateMarkdownContent,
      updateTimezone,
      setHosts,
      setSponsors,
      setSessions,
    } = this._getFormHelpers();

    setTextValue("name", appendCopySuffix(details.name));
    setCategoryValue(details);
    setSelectValue("kind_id", details.kind);
    setImageFieldValue("logo_url", details.logo_url);
    setTextValue("description_short", details.description_short);
    updateMarkdownContent(details.description);
    setTextValue("capacity", details.capacity);
    setEventReminderEnabled(details.event_reminder_enabled !== false);
    setRegistrationRequired(details.registration_required === true);
    setTextValue("meetup_url", details.meetup_url);
    setGalleryImages(details.photos_urls);
    setTags(details.tags);
    updateTimezone(details.timezone);
    setTextValue("venue_name", details.venue_name);
    setTextValue("venue_address", details.venue_address);
    setTextValue("venue_city", details.venue_city);
    setTextValue("venue_zip_code", details.venue_zip_code);
    setHosts(details.hosts);
    setSponsors(details.sponsors);
    setSessions([]);
  }

  /**
   * Resets meeting-related fields to avoid copying existing links or sync state.
   */
  _resetMeetingFields() {
    setTextValue("meeting_join_url", "");
    setTextValue("meeting_recording_url", "");
    const meetingDetails = document.querySelector("online-event-details");
    if (meetingDetails && typeof meetingDetails.reset === "function") {
      meetingDetails.reset();
    }
  }

  /**
   * Provides form helper utilities.
   * @returns {typeof formHelpers}
   */
  _getFormHelpers() {
    return formHelpers;
  }

  /**
   * Updates selector state after copying.
   * @param {object} details Copied event details
   */
  _updateSelectorAfterCopy(details) {
    if (!details) {
      return;
    }
    this.selectedEventId = String(details.event_id ?? "");
    this.selectedEvent = {
      event_id: String(details.event_id ?? ""),
      name: details.name || "",
      starts_at: this._parseEventTimestamp(details.starts_at),
      timezone: String(details.timezone || ""),
    };
  }

  /**
   * Parses a timestamp value safely.
   * @param {*} value Timestamp value
   * @returns {number|null}
   */
  _parseEventTimestamp(value) {
    if (value === null || value === undefined) {
      return null;
    }
    const timestamp = Number(value);
    return Number.isFinite(timestamp) ? timestamp : null;
  }

  /**
   * Scrolls to top after copying.
   */
  _scrollToTop() {
    if (typeof window !== "undefined" && typeof window.scrollTo === "function") {
      window.scrollTo({ top: 0, behavior: "smooth" });
    }
  }

  /**
   * Displays a success alert after copying.
   */
  _showCopySuccess() {
    showInfoAlert("Event details copied. Update the schedule before publishing.");
  }

  /**
   * Displays an error alert if copying fails.
   */
  _showCopyError() {
    showErrorAlert("Unable to copy that event right now. Please try again.");
  }

  /**
   * Keeps selected event id aligned with provided event payload.
   */
  _syncSelectedEvent() {
    const event = this.selectedEvent;
    if (!event || typeof event !== "object") {
      return;
    }

    const eventId = event?.event_id ? String(event.event_id) : "";
    if (eventId && eventId !== (this.selectedEventId ?? "")) {
      this.selectedEventId = eventId;
    }
  }

  /**
   * Gets the group dashboard selection context from DOM.
   * @returns {{community: string, groupSlug: string}}
   */
  _getDashboardSelection() {
    const container = this.closest("#dashboard-content") || document.getElementById("dashboard-content");
    return {
      community: container?.dataset?.community || "",
      groupSlug: container?.dataset?.groupSlug || "",
    };
  }

  /**
   * Gets the community name for search requests.
   * @returns {string}
   */
  _getCommunityName() {
    if (this.community) {
      return this.community;
    }
    return this._getDashboardSelection().community;
  }

  /**
   * Gets the group slug for search requests.
   * @returns {string}
   */
  _getGroupSlug() {
    if (this.groupSlug) {
      return this.groupSlug;
    }
    return this._getDashboardSelection().groupSlug;
  }

  /**
   * Performs a remote search using the provided config.
   * @param {{sortDirection?: string, query?: string, dateFrom?: string, dateTo?: string}} config
   * @returns {Promise<object[]>}
   */
  async _requestEvents(config) {
    const params = new URLSearchParams();
    params.set("limit", "10");
    if (config.dateFrom) {
      params.set("date_from", config.dateFrom);
    }
    if (config.dateTo) {
      params.set("date_to", config.dateTo);
    }
    if (config.sortDirection) {
      params.set("sort_direction", config.sortDirection);
    }
    if (config.query) {
      params.set("ts_query", config.query);
    }

    const groupSlug = this._getGroupSlug();
    const communityName = this._getCommunityName();
    if (groupSlug) {
      params.append("group[]", groupSlug);
    }
    if (communityName) {
      params.append("community[]", communityName);
    }
    const url = `/explore/events/search?${params.toString()}`;

    const response = await fetch(url, {
      headers: {
        Accept: "application/json",
      },
    });
    if (!response.ok) {
      throw new Error("Failed to search events");
    }
    const payload = await response.json();
    const events = Array.isArray(payload?.events) ? payload.events : [];
    return events;
  }

  /**
   * Retrieves 10 events for initial dropdown load (5 upcoming + 5 past closest to today).
   */
  async _fetchPrimaryEvents() {
    const groupId = this.groupId ? String(this.groupId) : "";
    if (!groupId) {
      this._results = [];
      this._primaryResults = [];
      this._loading = false;
      return;
    }

    if (this._primaryResults.length > 0) {
      this._results = this._primaryResults;
      this._error = "";
      this._loading = false;
      this._activeIndex = -1;
      this._hasFetched = true;
      return;
    }

    if (this._primaryFetchPromise) {
      this._loading = true;
      this._error = "";
      try {
        await this._primaryFetchPromise;
      } finally {
        this._loading = false;
      }
      if (this._primaryResults.length > 0) {
        this._results = this._primaryResults;
        this._activeIndex = -1;
        this._hasFetched = true;
      }
      return;
    }

    this._loading = true;
    this._error = "";
    const fetchPromise = (async () => {
      try {
        const today = new Date().toISOString().split("T")[0];

        const [upcomingEvents, pastEvents] = await Promise.all([
          this._requestEvents({
            sortDirection: "asc",
            query: "",
            dateFrom: today,
          }),
          this._requestEvents({
            sortDirection: "desc",
            query: "",
            dateFrom: this.dateFrom,
            dateTo: today,
          }),
        ]);

        if (this.groupId !== groupId) {
          return;
        }

        const result = [];
        result.push(...upcomingEvents.slice(0, 5).reverse());
        result.push(...pastEvents.slice(0, 5));

        if (result.length < 10) {
          const remainingSlots = 10 - result.length;
          const extraUpcoming = upcomingEvents.slice(5, 5 + remainingSlots).reverse();
          const extraPast = pastEvents.slice(5, 5 + remainingSlots);
          result.push(...extraUpcoming, ...extraPast);
        }

        this._primaryResults = result.slice(0, 10);
        this._results = this._primaryResults;
        this._activeIndex = -1;
        this._hasFetched = true;

        if (this.selectedEventId) {
          const selectedId = String(this.selectedEventId);
          const match = this._primaryResults.find((item) => item.event_id === selectedId);
          if (match) {
            this.selectedEvent = match;
          }
        }
      } catch (_error) {
        this._error = "Unable to load events";
        this._primaryResults = [];
        throw _error;
      } finally {
        this._loading = false;
      }
    })();
    this._primaryFetchPromise = fetchPromise;
    try {
      await fetchPromise;
    } catch (_error) {
      // handled above
    } finally {
      this._primaryFetchPromise = null;
    }
  }

  /**
   * Queries remote events using the selected group id.
   */
  async _fetchEvents() {
    const groupId = this.groupId ? String(this.groupId) : "";
    if (!groupId) {
      this._results = [];
      this._loading = false;
      this._error = "";
      return;
    }
    const trimmed = this._query.trim();
    if (trimmed.length === 0) {
      await this._fetchPrimaryEvents();
      return;
    }

    this._loading = true;
    this._error = "";

    try {
      const events = await this._requestEvents({
        sortDirection: "desc",
        query: trimmed,
        dateFrom: this.dateFrom,
      });
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
    } catch (_error) {
      this._error = "Unable to load events";
    } finally {
      this._loading = false;
    }
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
        <li class="px-4 py-4 text-sm text-stone-500">
          ${this._hasFetched ? "No events available." : "No events found."}
        </li>
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
   * @param {number} index Index in the results list
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
          ?disabled=${isSelected}
          @click=${(clickEvent) => this._handleEventClick(clickEvent, event)}
          @mouseenter=${() => {
            this._activeIndex = index;
          }}
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
    this._activeIndex = -1;
    this._error = "";
    if (this._primaryResults.length > 0) {
      this._results = this._primaryResults;
      this._loading = false;
    } else {
      this._results = [];
      this._fetchPrimaryEvents();
    }
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
    const selectedEvent = this._findSelectedEvent();

    return html`
      <div class="relative inline-block w-full">
        <button
          id=${this.buttonId}
          class="relative cursor-pointer select select-primary w-full
               text-left pe-9"
          aria-label="Select event"
          @click=${(event) => this._toggleDropdown(event)}
        >
          ${selectedEvent
            ? this._renderEventPreview(selectedEvent)
            : html`<div class="flex flex-col min-w-0">
                <div class="max-w-full truncate">Select event</div>
                <div class="text-xs text-stone-500 truncate">Choose an event to copy</div>
              </div>`}
          <div class="absolute inset-y-0 end-0 flex items-center pe-3 pointer-events-none gap-2">
            ${this._loading ? html`<svg-spinner label="Loading events"></svg-spinner>` : ""}
            <div class="svg-icon size-3 icon-caret-down bg-stone-600"></div>
          </div>
        </button>
        <div
          id="dropdown-events"
          class="${this._isOpen
            ? ""
            : "hidden"} absolute top-14 start-0 w-full z-10 bg-white rounded-lg shadow-sm border border-stone-200"
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
                value=${this._query}
                @input=${(event) => this._handleSearchInput(event)}
                @keydown=${(event) => this._handleInputKeydown(event)}
              />
              ${this._query.trim().length > 0
                ? html`<button
                    type="button"
                    class="absolute inset-y-0 end-2 flex items-center"
                    @click=${() => this._clearSearch()}
                  >
                    <div class="svg-icon size-4 icon-close bg-stone-400 hover:bg-stone-600"></div>
                    <span class="sr-only">Clear search</span>
                  </button>`
                : null}
            </div>
          </div>
          ${this._renderDropdownContent()}
        </div>
      </div>
    `;
  }
}

customElements.define("event-selector", EventSelector);
