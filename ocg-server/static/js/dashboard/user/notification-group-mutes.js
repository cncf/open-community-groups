import { html, nothing } from "lit";
import { repeat } from "lit/directives/repeat.js";
import { showServerErrorAlert, showSuccessAlert } from "/static/js/common/alerts.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { getElementById, markDatasetReady } from "/static/js/common/dom.js";
import { DropdownPlacementController } from "/static/js/common/dropdown-placement.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { isSuccessfulXHR } from "/static/js/common/utils.js";

const GROUP_MUTES_READY_KEY = "notificationGroupMutesReady";
const GROUP_OPTIONS_ID = "notification-group-mute-options";
const GROUP_OPTION_ID_PREFIX = "notification-group-mute-option-";
const GROUP_SEARCH_ID = "notification-group-mute-search";
const MUTED_GROUPS_ENDPOINT = "/dashboard/user/notifications/muted-groups";
const MUTED_GROUPS_ID = "muted-groups";
const MUTED_GROUPS_TITLE_ID = "muted-groups-title";
const REFRESH_MUTED_GROUPS_EVENT = "refresh-muted-groups";

/**
 * Notification group mute selector.
 *
 * Lets users search groups they can mute, saves each mute immediately, and
 * invalidates its option cache whenever the server-rendered muted list refreshes.
 * @extends LitWrapper
 */
export class NotificationGroupMutes extends LitWrapper {
  /**
   * Component properties definition.
   * @property {string} describedBy Element id that describes the input.
   * @property {string} optionsUrl Endpoint returning muteable group options.
   * @property {Array} _options Cached group options.
   * @property {string} _loadStatus Options load status: idle, loading, ready, or error.
   * @property {boolean} _isBusy Whether a mute request is pending.
   */
  static properties = {
    describedBy: { type: String, attribute: "described-by" },
    optionsUrl: { type: String, attribute: "options-url" },
    _isBusy: { state: true },
    _loadStatus: { state: true },
    _options: { state: true },
  };

  constructor() {
    super();
    this.describedBy = "";
    this.optionsUrl = "";
    this._abortController = null;
    this._focusWithoutOpen = false;
    this._isBusy = false;
    this._loadError = "";
    this._loadSequence = 0;
    this._loadStatus = "idle";
    this._options = [];
    this._handleRefreshMutedGroups = this._handleRefreshMutedGroups.bind(this);
    this._combobox = new ComboboxController(this, {
      getItemCount: () => this._filteredOptions.length,
      isInteractionBlocked: () => this._isBusy,
      canOpen: () => !this._isBusy,
      onActiveIndexMove: () => this._scrollActiveOptionIntoView(),
      onOpen: () => this._ensureOptionsLoaded(),
      onSelect: (index) => {
        const option = this._filteredOptions[index];
        if (option) {
          this._muteGroup(option);
        }
      },
    });
    this._dropdownPlacement = new DropdownPlacementController(this, {
      getAnchor: () => this.querySelector("[data-group-mute-search]"),
      getDropdown: () => this.querySelector("[data-group-mute-dropdown]"),
    });
  }

  connectedCallback() {
    super.connectedCallback();
    document.body.addEventListener(REFRESH_MUTED_GROUPS_EVENT, this._handleRefreshMutedGroups);
  }

  disconnectedCallback() {
    this._abortController?.abort();
    document.body.removeEventListener(REFRESH_MUTED_GROUPS_EVENT, this._handleRefreshMutedGroups);
    super.disconnectedCallback();
  }

  /**
   * Returns options matching the current query by group or community name.
   * @returns {Array<object>} Filtered group options.
   */
  get _filteredOptions() {
    const query = (this._combobox.query || "").trim().toLowerCase();
    if (!query) {
      return this._options;
    }

    return this._options.filter((option) =>
      [option.name, option.community_display_name]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(query)),
    );
  }

  /**
   * Returns the group search input.
   * @returns {HTMLInputElement|null} Search input, when rendered.
   */
  get _searchInput() {
    return this.querySelector(`#${GROUP_SEARCH_ID}`);
  }

  render() {
    return html`
      <div class="relative">
        <label for=${GROUP_SEARCH_ID} class="form-label">Mute a group</label>
        <div class="relative mt-2" data-group-mute-search>
          <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
            <div class="svg-icon size-4 icon-search bg-stone-300" aria-hidden="true"></div>
          </div>
          ${this._renderSearchInput()}
        </div>
        ${this._renderDropdown()}
        <p class="sr-only" role="status">
          ${this._loadStatus === "loading" ? "Loading groups to mute..." : ""}
        </p>
      </div>
    `;
  }

  /**
   * Keeps Enter in the search from submitting any containing form.
   * @param {KeyboardEvent} event Search input keydown event.
   * @returns {void}
   */
  _handleSearchKeydown(event) {
    if (event.key !== "Enter") {
      return;
    }

    const comboboxHandlesEnter = this._combobox.isOpen && !this._isBusy && this._filteredOptions.length > 0;
    if (!comboboxHandlesEnter) {
      event.preventDefault();
    }
  }

  /**
   * Clears cached options after the muted-groups list changes elsewhere.
   * @returns {void}
   */
  _handleRefreshMutedGroups() {
    this._invalidateOptions();
  }

  /**
   * Invalidates option cache and aborts in-flight option loads.
   * @returns {void}
   */
  _invalidateOptions() {
    this._abortController?.abort();
    this._abortController = null;
    this._loadError = "";
    this._loadSequence += 1;
    this._loadStatus = "idle";
    this._options = [];
  }

  /**
   * Loads options when none are cached or the previous load failed.
   * @returns {void}
   */
  _ensureOptionsLoaded() {
    if (this._loadStatus === "idle" || this._loadStatus === "error") {
      this._loadOptions();
    }
  }

  /**
   * Loads group options, ignoring stale responses.
   * @returns {Promise<void>}
   */
  async _loadOptions() {
    if (!this.optionsUrl || this._loadStatus === "loading") {
      return;
    }

    const sequence = this._loadSequence + 1;
    this._loadSequence = sequence;
    this._abortController?.abort();
    this._abortController = new AbortController();
    this._loadError = "";
    this._loadStatus = "loading";

    try {
      const response = await ocgFetch(this.optionsUrl, {
        credentials: "same-origin",
        signal: this._abortController.signal,
      });

      if (!response.ok) {
        throw new Error(`Failed to load notification group options: ${response.status}`);
      }

      const options = await response.json();
      if (sequence !== this._loadSequence || !this.isConnected) {
        return;
      }

      this._options = Array.isArray(options) ? options : [];
      this._loadStatus = "ready";

      if (this._searchInput === document.activeElement) {
        this._combobox.open();
      }
    } catch (error) {
      if (error?.name === "AbortError" || sequence !== this._loadSequence || !this.isConnected) {
        return;
      }

      this._options = [];
      this._loadError = "Groups could not be loaded. Try again.";
      this._loadStatus = "error";
    }
  }

  /**
   * Mutes a group and refreshes the server-rendered muted list.
   * @param {Object} group Group option to mute.
   * @returns {Promise<void>}
   */
  async _muteGroup(group) {
    if (this._isBusy || !group?.group_id) {
      return;
    }

    this._isBusy = true;
    this._combobox.close();

    try {
      const response = await ocgFetch(`${MUTED_GROUPS_ENDPOINT}/${encodeURIComponent(group.group_id)}`, {
        credentials: "same-origin",
        method: "PUT",
      });

      if (!response.ok) {
        const serverMessage = await response.text();
        throw new Error(serverMessage || `Mute failed with status ${response.status}`);
      }

      if (!this.isConnected) {
        return;
      }

      this._isBusy = false;
      globalThis.htmx?.trigger?.(document.body, REFRESH_MUTED_GROUPS_EVENT);
      this._invalidateOptions();
      this._combobox.setQuery("");
      await this.updateComplete;
      this._showAlertFromSearch(() => showSuccessAlert(`${group.name} muted.`));
    } catch (error) {
      if (!this.isConnected) {
        return;
      }

      this._isBusy = false;
      this._invalidateOptions();
      await this.updateComplete;
      this._showAlertFromSearch(() =>
        showServerErrorAlert("Something went wrong muting this group.", error?.message || ""),
      );
      await this._loadOptions();
    }
  }

  /**
   * Renders the dropdown panel with loading, empty, error, and option states.
   * @returns {import("lit").TemplateResult}
   */
  _renderDropdown() {
    return html`
      <div
        data-group-mute-dropdown
        class="absolute start-0 end-0 z-10 mt-1 max-h-72 overflow-y-auto rounded-lg border border-stone-200 bg-white shadow ${
          this._combobox.isOpen ? "" : "hidden"
        }"
      >
        ${this._renderDropdownContent()}
      </div>
    `;
  }

  /**
   * Renders the active dropdown state.
   * @returns {import("lit").TemplateResult}
   */
  _renderDropdownContent() {
    if (this._loadStatus === "loading") {
      return html`<div class="px-4 py-3 text-sm text-stone-500">Loading groups...</div>`;
    }

    if (this._loadStatus === "error") {
      return html`
        <div class="px-4 py-3 text-sm text-red-900" role="alert">
          <p>${this._loadError}</p>
          <button
            type="button"
            class="btn-primary-outline btn-mini mt-3"
            @click=${() => this._retryLoadOptions()}
          >
            Retry
          </button>
        </div>
      `;
    }

    if (this._filteredOptions.length === 0) {
      const hasQuery = this._combobox.query.trim().length > 0;
      return html`<div class="px-4 py-3 text-sm text-stone-500">
        ${hasQuery ? "No groups match your search." : "No groups available to mute."}
      </div>`;
    }

    return html`
      <ul id=${GROUP_OPTIONS_ID} class="py-1" role="listbox" aria-label="Groups to mute">
        ${repeat(
          this._filteredOptions,
          (group) => group.group_id,
          (group, index) => this._renderOption(group, index),
        )}
      </ul>
    `;
  }

  /**
   * Renders one group option.
   * @param {Object} group Group option.
   * @param {number} index Option index.
   * @returns {import("lit").TemplateResult}
   */
  _renderOption(group, index) {
    const isActive = this._combobox.activeIndex === index;
    return html`
      <li role="presentation">
        <button
          id=${`${GROUP_OPTION_ID_PREFIX}${index}`}
          type="button"
          role="option"
          tabindex="-1"
          aria-selected=${isActive ? "true" : "false"}
          class="flex w-full items-center gap-3 px-4 py-2 text-left text-sm ${
            isActive ? "bg-stone-50 text-stone-900" : "text-stone-700 hover:bg-stone-50 hover:text-stone-900"
          }"
          @click=${() => this._muteGroup(group)}
          @mouseover=${() => this._combobox.setActiveIndex(index)}
        >
          ${renderGroupLogo(group)}
          <span class="min-w-0">
            <span
              class="block truncate text-[0.65rem]/3 font-semibold uppercase tracking-wider text-stone-400"
            >
              ${group.community_display_name}
            </span>
            <span class="mt-0.5 block truncate text-sm/5 font-semibold text-stone-900">${group.name}</span>
          </span>
        </button>
      </li>
    `;
  }

  /**
   * Renders the search input and its combobox ARIA state.
   * @returns {import("lit").TemplateResult}
   */
  _renderSearchInput() {
    const hasOptions = this._filteredOptions.length > 0;
    const activeOptionId =
      this._combobox.isOpen && hasOptions && this._combobox.activeIndex !== null
        ? `${GROUP_OPTION_ID_PREFIX}${this._combobox.activeIndex}`
        : nothing;

    return html`
      <input
        id=${GROUP_SEARCH_ID}
        type="search"
        role="combobox"
        class="input-primary ps-9"
        placeholder=${this._loadStatus === "loading" ? "Loading groups..." : "Search groups"}
        autocomplete="off"
        autocorrect="off"
        autocapitalize="off"
        spellcheck="false"
        .value=${this._combobox.query}
        ?disabled=${this._isBusy}
        aria-activedescendant=${activeOptionId}
        aria-autocomplete="list"
        aria-controls=${hasOptions ? GROUP_OPTIONS_ID : nothing}
        aria-describedby=${this.describedBy || nothing}
        aria-expanded=${this._combobox.isOpen ? "true" : "false"}
        aria-haspopup="listbox"
        @click=${() => {
          this._combobox.open();
          this._ensureOptionsLoaded();
        }}
        @focus=${() => {
          if (this._focusWithoutOpen) {
            this._focusWithoutOpen = false;
            return;
          }
          this._combobox.open();
          this._ensureOptionsLoaded();
        }}
        @input=${(event) => {
          this._combobox.setQuery(event.target.value || "");
          this._combobox.open();
          this._ensureOptionsLoaded();
        }}
        @keydown=${(event) => this._handleSearchKeydown(event)}
      />
    `;
  }

  /**
   * Moves focus back to the search input without reopening the dropdown.
   * @returns {void}
   */
  _restoreSearchFocus() {
    const searchInput = this._searchInput;
    if (!searchInput || searchInput.disabled || searchInput === document.activeElement) {
      return;
    }

    this._focusWithoutOpen = true;
    searchInput.focus();
    this._focusWithoutOpen = false;
  }

  /**
   * Retries loading the options while keeping focus on the search input.
   * @returns {void}
   */
  _retryLoadOptions() {
    this._restoreSearchFocus();
    this._loadOptions();
  }

  /**
   * Scrolls the keyboard-active option into view after rendering.
   * @returns {void}
   */
  _scrollActiveOptionIntoView() {
    this.updateComplete.then(() => {
      const index = this._combobox.activeIndex;
      if (index === null) {
        return;
      }

      this.querySelector(`#${GROUP_OPTION_ID_PREFIX}${index}`)?.scrollIntoView({ block: "nearest" });
    });
  }

  /**
   * Shows a mute alert that returns focus to the search input on close
   * without reopening the dropdown or reloading the options.
   * @param {Function} showAlert Callback that opens the alert.
   * @returns {void}
   */
  _showAlertFromSearch(showAlert) {
    // Focus the enabled input first so the alert returns focus there on close
    this._restoreSearchFocus();
    // Skip the focus-open behavior once when the alert returns focus
    this._focusWithoutOpen = this._searchInput === document.activeElement;
    showAlert();
  }
}

/**
 * Initializes focus recovery for HTMX refreshes of the muted-groups list.
 *
 * HTMX swaps only the #muted-groups contents. When the activated Unmute button
 * disappears, browsers can leave focus on body; moving focus to the stable
 * heading keeps keyboard users oriented in the refreshed section. A successful
 * Unmute moves focus to the heading before its success alert opens, so the
 * alert returns focus there when it closes.
 * @returns {void}
 */
export const initializeMutedGroupsSwapFocusRecovery = () => {
  if (!markDatasetReady(document.documentElement, GROUP_MUTES_READY_KEY)) {
    return;
  }

  document.addEventListener("htmx:afterSwap", handleMutedGroupsAfterSwap);
  // Capture runs before the shared bubbling response handlers open alerts
  document.addEventListener("htmx:beforeOnLoad", handleUnmuteBeforeOnLoad, true);
};

/**
 * Restores focus after HTMX replaces the muted groups inner content.
 * @param {Event} event HTMX after-swap event.
 * @returns {void}
 */
const handleMutedGroupsAfterSwap = (event) => {
  const target =
    event.detail?.target instanceof Element
      ? event.detail.target
      : event.target instanceof Element
        ? event.target
        : null;
  if (target?.id !== MUTED_GROUPS_ID) {
    return;
  }

  const activeElement = document.activeElement;
  if (activeElement && activeElement !== document.body && activeElement.isConnected) {
    return;
  }

  getElementById(document, MUTED_GROUPS_TITLE_ID)?.focus();
};

/**
 * Moves focus to the muted groups heading when an Unmute request succeeds.
 * @param {CustomEvent} event HTMX before-on-load event.
 * @returns {void}
 */
const handleUnmuteBeforeOnLoad = (event) => {
  const trigger = event.detail?.elt instanceof Element ? event.detail.elt : event.target;
  const mutedGroups = getElementById(document, MUTED_GROUPS_ID);
  if (
    !(trigger instanceof Element) ||
    !mutedGroups ||
    trigger === mutedGroups ||
    !mutedGroups.contains(trigger) ||
    !isSuccessfulXHR(event.detail?.xhr)
  ) {
    return;
  }

  getElementById(document, MUTED_GROUPS_TITLE_ID)?.focus();
};

/**
 * Renders a group logo with the framed style used on group pages. Groups
 * without a logo show the same placeholder used for images that fail to load.
 * @param {Object} group Group option.
 * @returns {import("lit").TemplateResult}
 */
const renderGroupLogo = (group) => html`
  <span
    class="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-lg border border-[5px] border-white outline outline-1 outline-stone-300 ${
      group.logo_url ? "bg-white" : "bg-stone-50"
    }"
  >
    ${
      group.logo_url
        ? html`<img
            src=${group.logo_url}
            alt=""
            class="h-full w-full object-contain"
            width="36"
            height="36"
            loading="lazy"
          />`
        : html`<span class="svg-icon size-5 icon-broken-image bg-stone-400" aria-hidden="true"></span>`
    }
  </span>
`;

customElements.define("notification-group-mutes", NotificationGroupMutes);
initializeMutedGroupsSwapFocusRecovery();
