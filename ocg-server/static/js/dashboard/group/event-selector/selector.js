import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { getNextLoopedIndex, isEscapeEvent } from "/static/js/common/keyboard.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { showErrorAlert, showInfoAlert } from "/static/js/common/alerts.js";
import { focusElementById, getElementById, setElementHidden } from "/static/js/common/dom.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import {
  buildPrimaryEventResults,
  buildSelectedEventFromDetails,
  findEventById,
  getActiveEventResult,
  getDashboardSelectionContext,
  getEmptyEventSearchState,
  getEventSelectorKeyAction,
  getLoadedPrimaryEventSearchState,
  getLoadedQueryEventSearchState,
  getNoGroupEventSearchState,
  getSelectedEvent,
  normalizeEventId,
  resolveEventSearchContext,
} from "/static/js/dashboard/group/event-selector/utils.js";
import { requestEventSelectorEvents } from "/static/js/dashboard/group/event-selector/api.js";
import {
  renderEventSelectorDropdownContent,
  renderEventSelectorPreview,
} from "/static/js/dashboard/group/event-selector/dropdown.js";
import { applyCopiedEventDetails } from "/static/js/dashboard/group/event-selector/copy.js";
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
   * - alliance: alliance slug for event search
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
          return parseJsonAttribute(value, null);
        },
      },
    },
    groupId: { type: String, attribute: "group-id" },
    alliance: { type: String, attribute: "alliance" },
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
    this.alliance = "";
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
    if (changed.has("groupId") || changed.has("alliance") || changed.has("groupSlug")) {
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

    const keyAction = getEventSelectorKeyAction({
      activeIndex: this._activeIndex,
      getNextIndex: getNextLoopedIndex,
      isEscape: isEscapeEvent(event),
      key: event.key,
      resultsLength: this._results.length,
    });

    if (keyAction.preventDefault) {
      event.preventDefault();
    }
    if (keyAction.action === "highlight") {
      this._activeIndex = keyAction.activeIndex;
    } else if (keyAction.action === "select") {
      this._selectActiveResult();
    } else if (keyAction.action === "close") {
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
      focusElementById(this, "event-search-input", { select: true });
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
      await this._applyEventDetails(details);
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
    setElementHidden(indicator, !loading);
    const triggerButton = getElementById(document, this.buttonId);
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
    const response = await ocgFetch(url, {
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
   * @returns {Promise<void>}
   */
  async _applyEventDetails(details) {
    await applyCopiedEventDetails(details);
  }

  /**
   * Updates selector state after copying.
   * @param {object} details Copied event details
   */
  _updateSelectorAfterCopy(details) {
    const selectedEvent = buildSelectedEventFromDetails(details);
    if (!selectedEvent) {
      return;
    }
    this.selectedEventId = selectedEvent.event_id;
    this.selectedEvent = selectedEvent;
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

    const eventId = normalizeEventId(event?.event_id);
    if (eventId && eventId !== (this.selectedEventId ?? "")) {
      this.selectedEventId = eventId;
    }
  }

  /**
   * Gets the group dashboard selection context from DOM.
   * @returns {{alliance: string, groupSlug: string}}
   */
  _getDashboardSelection() {
    return getDashboardSelectionContext(this);
  }

  /**
   * Performs a remote search using the provided config.
   * @param {{sortDirection?: string, query?: string, dateFrom?: string, dateTo?: string}} config
   * @returns {Promise<object[]>}
   */
  async _requestEvents(config) {
    const searchContext = resolveEventSearchContext({
      alliance: this.alliance,
      dashboardSelection: this._getDashboardSelection(),
      groupSlug: this.groupSlug,
    });
    return requestEventSelectorEvents({
      ...config,
      ...searchContext,
    });
  }

  /**
   * Retrieves 10 events for initial dropdown load (5 upcoming + 5 past closest to today).
   */
  async _fetchPrimaryEvents() {
    const groupId = this.groupId ? String(this.groupId) : "";
    if (!groupId) {
      Object.assign(this, getNoGroupEventSearchState());
      return;
    }

    if (this._primaryResults.length > 0) {
      Object.assign(this, getLoadedPrimaryEventSearchState(this._primaryResults));
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
        Object.assign(this, getLoadedPrimaryEventSearchState(this._primaryResults));
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

        const primaryResults = buildPrimaryEventResults({ upcomingEvents, pastEvents });
        this._primaryResults = primaryResults;
        Object.assign(this, getLoadedPrimaryEventSearchState(primaryResults));

        if (this.selectedEventId) {
          const match = findEventById(this._primaryResults, this.selectedEventId);
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
      Object.assign(this, getNoGroupEventSearchState());
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
      Object.assign(this, getLoadedQueryEventSearchState(events));
      if (this.selectedEventId) {
        const match = findEventById(this._results, this.selectedEventId);
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
    const found = getSelectedEvent({
      selectedEvent: this.selectedEvent,
      selectedEventId: this.selectedEventId,
      results: this._results,
    });
    if (found) {
      this.selectedEvent = found;
    }
    return found;
  }

  /**
   * Clears the search input and resets local results.
   */
  _clearSearch() {
    const emptySearchState = getEmptyEventSearchState();
    this._query = "";
    this._activeIndex = emptySearchState.activeIndex;
    this._error = emptySearchState.error;
    if (this._primaryResults.length > 0) {
      this._results = this._primaryResults;
      this._loading = false;
    } else {
      this._results = [];
      this._fetchPrimaryEvents();
    }
    const input = getElementById(this, "event-search-input");
    if (input) {
      input.value = "";
      input.focus();
    }
  }

  /**
   * Triggers selection of the highlighted result.
   */
  _selectActiveResult() {
    const active = getActiveEventResult(this._results, this._activeIndex);
    if (!active) {
      return;
    }
    const button = getElementById(document, `select-event-${active.event_id}`);
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
            ? renderEventSelectorPreview(selectedEvent)
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
          ${renderEventSelectorDropdownContent({
            activeIndex: this._activeIndex,
            error: this._error,
            hasFetched: this._hasFetched,
            onHighlight: (index) => {
              this._activeIndex = index;
            },
            onSelect: (event, selectedEvent) => this._handleEventClick(event, selectedEvent),
            results: this._results,
            selectedEventId: this.selectedEventId,
          })}
        </div>
      </div>
    `;
  }
}

customElements.define("event-selector", EventSelector);
