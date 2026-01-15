import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * GroupSelector renders a searchable dropdown to pick a single group.
 *
 * Keyboard interactions follow the ARIA combobox pattern. Down, Up, Home and
 * End move the highlight, Enter selects the highlighted item and Escape closes
 * the menu. Typing in the search field filters results with a debounce to
 * reduce re-render pressure while the user is typing.
 *
 * @property {Array<object>} groupsByCommunity List of communities with their
 *   groups, each having community.community_id and groups array
 * @property {string} selectedCommunityId Currently selected community identifier
 * @property {string} selectedGroupId Currently selected group identifier
 * @property {number} searchDelay Debounced search delay in milliseconds
 */
export class GroupSelector extends LitWrapper {
  static properties = {
    groupsByCommunity: {
      attribute: "groups-by-community",
      type: Array,
    },
    selectedCommunityId: { type: String, attribute: "selected-community-id" },
    selectedGroupId: { type: String, attribute: "selected-group-id" },
    _isOpen: { state: true },
    _query: { state: true },
    _isSubmitting: { state: true },
    _activeIndex: { state: true },
  };

  constructor() {
    super();
    this.groupsByCommunity = [];
    this.selectedCommunityId = "";
    this.selectedGroupId = "";
    this._isOpen = false;
    this._query = "";
    this._isSubmitting = false;
    this._activeIndex = null;
    this._searchTimeoutId = 0;
    this._documentClickHandler = null;
  }

  connectedCallback() {
    super.connectedCallback();
    this.addEventListener("keydown", this._handleKeydown.bind(this));
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._removeDocumentListener();
    if (this._searchTimeoutId) {
      window.clearTimeout(this._searchTimeoutId);
    }
  }

  /**
   * Gets groups for the selected community from groupsByCommunity data.
   * @returns {Array<object>} Groups for the selected community
   */
  get _groups() {
    if (!this.groupsByCommunity || this.groupsByCommunity.length === 0) {
      return [];
    }
    const targetId = this.selectedCommunityId ? String(this.selectedCommunityId) : "";
    const communityEntry = this.groupsByCommunity.find((item) => {
      const communityId = item.community?.community_id ?? item.community_id;
      return String(communityId) === targetId;
    });
    return communityEntry?.groups ?? [];
  }

  /**
   * Stores the current query and triggers filtering with simple debounce.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    const value = event.target.value || "";
    this._query = value;
    if (this._searchTimeoutId) {
      window.clearTimeout(this._searchTimeoutId);
    }
    this._searchTimeoutId = window.setTimeout(() => {
      this._activeIndex = null;
      this.requestUpdate();
    }, 200);
  }

  /**
   * Gets filtered groups based on current query.
   */
  get _filteredGroups() {
    const normalized = (this._query || "").trim().toLowerCase();
    if (!normalized) {
      return this._groups;
    }
    return this._groups.filter((group) => {
      return (group.name || "").toLowerCase().includes(normalized);
    });
  }

  /**
   * Triggers dashboard group selection via HTMX or falls back to reloading.
   * @param {string|number} groupId Identifier of the group to select
   * @returns {XMLHttpRequest|null} Active HTMX request when available
   */
  _selectDashboardGroup(groupId) {
    const url = `/dashboard/group/${groupId}/select`;

    if (typeof window !== "undefined" && window.htmx && typeof window.htmx.ajax === "function") {
      const request = window.htmx.ajax("PUT", url, {
        target: "#dashboard-content",
        indicator: "#dashboard-spinner",
      });
      return request ?? null;
    }

    if (typeof window !== "undefined") {
      window.location.assign("/dashboard/group");
    }
    return null;
  }

  /**
   * Handles clicks on a group option and closes the dropdown.
   * @param {MouseEvent} event Option click event
   * @param {object} group Associated group data
   */
  _handleGroupClick(event, group) {
    if (this._isSelected(group) || this._isSubmitting) {
      event.preventDefault();
      return;
    }
    event.preventDefault();
    this._isSubmitting = true;
    this._selectDashboardGroup(group.group_id, {
      target: "#dashboard-content",
      indicator: "#dashboard-spinner",
    });
    this._closeDropdown();
  }

  /**
   * Toggles dropdown visibility.
   */
  _toggleDropdown() {
    if (this._isSubmitting) {
      return;
    }
    if (this._isOpen) {
      this._closeDropdown();
    } else {
      this._openDropdown();
    }
  }

  /**
   * Opens the dropdown and resets search.
   */
  _openDropdown() {
    if (this._groups.length === 0 || this._isSubmitting) {
      return;
    }
    this._isOpen = true;
    this._query = "";
    this._activeIndex = null;
    this._addDocumentListener();
    this.updateComplete.then(() => {
      const input = this.querySelector("#group-search-input");
      if (input) {
        input.focus();
      }
    });
  }

  /**
   * Closes the dropdown and clears search state.
   */
  _closeDropdown() {
    this._isOpen = false;
    this._query = "";
    this._activeIndex = null;
    this._removeDocumentListener();
  }

  /**
   * Registers a click listener on document to detect outside clicks.
   */
  _addDocumentListener() {
    if (this._documentClickHandler) {
      return;
    }
    this._documentClickHandler = (event) => {
      if (!this.contains(event.target)) {
        this._closeDropdown();
      }
    };
    document.addEventListener("click", this._documentClickHandler);
  }

  /**
   * Removes the outside click listener if it exists.
   */
  _removeDocumentListener() {
    if (!this._documentClickHandler) {
      return;
    }
    document.removeEventListener("click", this._documentClickHandler);
    this._documentClickHandler = null;
  }

  /**
   * Handles keyboard navigation and shortcuts.
   * @param {KeyboardEvent} event Native keyboard event
   */
  _handleKeydown(event) {
    if (event.defaultPrevented || this._isSubmitting) {
      return;
    }

    if (!this._isOpen || this._filteredGroups.length === 0) {
      if (this._isOpen && event.key === "Escape") {
        event.preventDefault();
        this._closeDropdown();
      }
      return;
    }

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        if (this._activeIndex === null) {
          this._activeIndex = 0;
        } else {
          this._activeIndex = (this._activeIndex + 1) % this._filteredGroups.length;
        }
        break;
      case "ArrowUp":
        event.preventDefault();
        if (this._activeIndex === null) {
          this._activeIndex = 0;
        } else {
          this._activeIndex =
            (this._activeIndex - 1 + this._filteredGroups.length) % this._filteredGroups.length;
        }
        break;
      case "Enter":
        event.preventDefault();
        if (this._activeIndex !== null) {
          const group = this._filteredGroups[this._activeIndex];
          if (group && !this._isSelected(group)) {
            this._handleGroupClick(event, group);
          }
        }
        break;
      case "Escape":
        event.preventDefault();
        this._closeDropdown();
        break;
      default:
        break;
    }
  }

  /**
   * Returns the selected group object, or null when none is selected.
   * @returns {object|null}
   */
  _findSelectedGroup() {
    const groups = this._groups;
    if (!groups || groups.length === 0) {
      return null;
    }
    const targetId = this.selectedGroupId != null ? String(this.selectedGroupId) : "";
    return groups.find((group) => String(group.group_id) === targetId) || null;
  }

  /**
   * Checks whether the provided group matches the selected identifier.
   * @param {object} group Group metadata
   * @returns {boolean}
   */
  _isSelected(group) {
    return String(group.group_id) === String(this.selectedGroupId || "");
  }

  render() {
    const selectedGroup = this._findSelectedGroup();
    const isDisabled = this._groups.length === 0 || this._isSubmitting;

    return html`
      <div class="relative">
        <button
          id="group-selector-button"
          type="button"
          class="select select-primary relative text-left pe-9 ${isDisabled
            ? "opacity-60 cursor-not-allowed"
            : "cursor-pointer"}"
          ?disabled=${isDisabled}
          aria-haspopup="listbox"
          aria-expanded=${this._isOpen ? "true" : "false"}
          @click=${() => this._toggleDropdown()}
        >
          <div class="flex flex-col justify-center min-h-10">
            <div class="text-xs/4 text-stone-900 line-clamp-2">
              ${selectedGroup ? selectedGroup.name : "Select a group"}
            </div>
          </div>
          <div class="absolute inset-y-0 end-0 flex items-center pe-3 pointer-events-none">
            <div class="svg-icon size-3 icon-caret-down bg-stone-600"></div>
          </div>
        </button>

        <div
          class="absolute top-14 left-0 right-0 z-10 bg-white rounded-lg shadow-sm border border-stone-200 ${this
            ._isOpen
            ? ""
            : "hidden"}"
        >
          <div class="p-3 border-b border-stone-200">
            <div class="relative">
              <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
                <div class="svg-icon size-4 icon-search bg-stone-300"></div>
              </div>
              <input
                id="group-search-input"
                type="search"
                class="input-primary w-full ps-9"
                placeholder="Search groups"
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                spellcheck="false"
                .value=${this._query}
                @input=${(event) => this._handleSearchInput(event)}
              />
            </div>
          </div>

          ${this._filteredGroups.length > 0
            ? html`
                <ul id="group-selector-list" class="max-h-48 overflow-y-auto text-stone-700" role="listbox">
                  ${repeat(
                    this._filteredGroups,
                    (group) => group.group_id,
                    (group, index) => {
                      const isSelected = this._isSelected(group);
                      const isActive = this._activeIndex === index;
                      const isDisabled = isSelected || this._isSubmitting;

                      let statusClass = "";
                      if (isDisabled) {
                        statusClass = "opacity-50 cursor-not-allowed bg-stone-100";
                      } else if (isActive) {
                        statusClass = "cursor-pointer bg-stone-50";
                      } else {
                        statusClass = "cursor-pointer hover:bg-stone-50";
                      }

                      return html`
                        <li role="presentation" data-index=${index}>
                          <button
                            id="group-option-${group.group_id}"
                            type="button"
                            class="group-button w-full px-4 py-2 whitespace-normal min-h-10 flex flex-col justify-center text-left focus:outline-none ${statusClass}"
                            role="option"
                            data-group-id=${group.group_id}
                            ?disabled=${isDisabled}
                            @click=${(event) => this._handleGroupClick(event, group)}
                            @mouseover=${() => (this._activeIndex = index)}
                          >
                            <div class="text-xs/4 text-stone-900 line-clamp-2">${group.name}</div>
                          </button>
                        </li>
                      `;
                    },
                  )}
                </ul>
              `
            : html`<div class="px-4 py-3 text-sm text-stone-500">No groups found.</div>`}
        </div>
      </div>
    `;
  }
}

customElements.define("group-selector", GroupSelector);
