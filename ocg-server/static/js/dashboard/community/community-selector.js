import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { selectDashboardAndKeepTab } from "/static/js/common/dashboard-selection.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * CommunitySelector renders a searchable dropdown to pick a single community.
 *
 * Keyboard interactions follow the ARIA combobox pattern. Down and Up move the
 * highlight, Enter selects the highlighted item and Escape closes the menu.
 * Typing in the search field filters results with a debounce to reduce
 * re-render pressure while the user is typing.
 *
 * @property {Array<object>} communities List of communities with community_id,
 *   community_name and display_name keys
 * @property {string} selectedCommunityId Currently selected community identifier
 * @property {string} selectEndpoint API endpoint for selecting community
 */
export class CommunitySelector extends LitWrapper {
  static properties = {
    communities: {
      attribute: "communities",
      type: Array,
    },
    selectedCommunityId: { type: String, attribute: "selected-community-id" },
    selectEndpoint: { type: String, attribute: "select-endpoint" },
    _isOpen: { state: true },
    _query: { state: true },
    _isSubmitting: { state: true },
    _activeIndex: { state: true },
  };

  constructor() {
    super();
    this.communities = [];
    this.selectedCommunityId = "";
    this.selectEndpoint = "/dashboard/community";
    this._isOpen = false;
    this._query = "";
    this._isSubmitting = false;
    this._activeIndex = null;
    this._searchTimeoutId = 0;
    this._pendingQuery = "";
    this._documentClickHandler = null;
    this._keydownHandler = (event) => this._handleKeydown(event);
  }

  connectedCallback() {
    super.connectedCallback();
    this.addEventListener("keydown", this._keydownHandler);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this.removeEventListener("keydown", this._keydownHandler);
    this._removeDocumentListener();
    if (this._searchTimeoutId) {
      window.clearTimeout(this._searchTimeoutId);
      this._searchTimeoutId = 0;
    }
  }

  /**
   * Stores the current query and triggers filtering with simple debounce.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    const value = event.target.value || "";
    this._pendingQuery = value;
    if (this._searchTimeoutId) {
      window.clearTimeout(this._searchTimeoutId);
    }
    this._searchTimeoutId = window.setTimeout(() => {
      this._activeIndex = null;
      this._query = this._pendingQuery;
      this._searchTimeoutId = 0;
    }, 200);
  }

  /**
   * Gets filtered communities based on current query.
   */
  get _filteredCommunities() {
    const normalized = (this._query || "").trim().toLowerCase();
    if (!normalized) {
      return this.communities;
    }
    return this.communities.filter((community) => {
      const name = (community.display_name || community.name || "").toLowerCase();
      return name.includes(normalized);
    });
  }

  /**
   * Triggers dashboard community selection and lets HTMX refresh the current URL.
   * @param {string|number} communityId Identifier of the community to select
   * @returns {Promise<void>}
   */
  async _selectDashboardCommunity(communityId) {
    const url = `${this.selectEndpoint}/${communityId}/select`;
    await selectDashboardAndKeepTab(url);
  }

  /**
   * Handles clicks on a community option and closes the dropdown.
   * @param {MouseEvent} event Option click event
   * @param {object} community Associated community data
   */
  async _handleCommunityClick(event, community) {
    if (this._isSelected(community) || this._isSubmitting) {
      event.preventDefault();
      return;
    }
    event.preventDefault();
    this._isSubmitting = true;
    this._closeDropdown();
    try {
      await this._selectDashboardCommunity(community.community_id);
    } catch (_) {
      // Keep the current selector usable when the request fails.
    } finally {
      this._isSubmitting = false;
    }
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
    if (this.communities.length === 0 || this._isSubmitting) {
      return;
    }
    this._isOpen = true;
    this._query = "";
    this._pendingQuery = "";
    this._activeIndex = null;
    this._addDocumentListener();
    this.updateComplete.then(() => {
      const input = this.querySelector("#community-search-input");
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
    this._pendingQuery = "";
    this._activeIndex = null;
    if (this._searchTimeoutId) {
      window.clearTimeout(this._searchTimeoutId);
      this._searchTimeoutId = 0;
    }
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

    if (!this._isOpen || this._filteredCommunities.length === 0) {
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
          this._activeIndex = (this._activeIndex + 1) % this._filteredCommunities.length;
        }
        break;
      case "ArrowUp":
        event.preventDefault();
        if (this._activeIndex === null) {
          this._activeIndex = 0;
        } else {
          this._activeIndex =
            (this._activeIndex - 1 + this._filteredCommunities.length) % this._filteredCommunities.length;
        }
        break;
      case "Enter":
        event.preventDefault();
        if (this._activeIndex !== null) {
          const community = this._filteredCommunities[this._activeIndex];
          if (community && !this._isSelected(community)) {
            this._handleCommunityClick(event, community);
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
   * Returns the selected community object, or null when none is selected.
   * @returns {object|null}
   */
  _findSelectedCommunity() {
    const communities = this.communities;
    if (!communities || communities.length === 0) {
      return null;
    }
    const targetId = this.selectedCommunityId != null ? String(this.selectedCommunityId) : "";
    return communities.find((community) => String(community.community_id) === targetId) || null;
  }

  /**
   * Checks whether the provided community matches the selected identifier.
   * @param {object} community Community metadata
   * @returns {boolean}
   */
  _isSelected(community) {
    return String(community.community_id) === String(this.selectedCommunityId || "");
  }

  render() {
    const selectedCommunity = this._findSelectedCommunity();
    const isDisabled = this._isSubmitting;

    return html`
      <div class="relative">
        <button
          id="community-selector-button"
          type="button"
          class="select select-primary relative text-left pe-9 ${isDisabled
            ? "opacity-80 cursor-not-allowed"
            : "cursor-pointer"}"
          ?disabled=${isDisabled}
          aria-haspopup="listbox"
          aria-expanded=${this._isOpen ? "true" : "false"}
          @click=${() => this._toggleDropdown()}
        >
          <div class="flex flex-col justify-center min-h-10">
            <div class="text-xs/4 text-stone-900 line-clamp-2">
              ${selectedCommunity
                ? selectedCommunity.display_name || selectedCommunity.name
                : "Select a community"}
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
                id="community-search-input"
                type="search"
                class="input-primary w-full ps-9"
                placeholder="Search communities"
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                spellcheck="false"
                .value=${this._query}
                @input=${(event) => this._handleSearchInput(event)}
              />
            </div>
          </div>

          ${this._filteredCommunities.length > 0
            ? html`
                <ul
                  id="community-selector-list"
                  class="max-h-48 overflow-y-auto text-stone-700"
                  role="listbox"
                >
                  ${repeat(
                    this._filteredCommunities,
                    (community) => community.community_id,
                    (community, index) => {
                      const isSelected = this._isSelected(community);
                      const isActive = this._activeIndex === index;
                      const isDisabled = isSelected || this._isSubmitting;

                      let statusClass = "";
                      if (isDisabled) {
                        statusClass =
                          "cursor-not-allowed bg-primary-50 text-primary-600 font-semibold opacity-100!";
                      } else if (isActive) {
                        statusClass = "cursor-pointer text-stone-900 bg-stone-50";
                      } else {
                        statusClass = "cursor-pointer text-stone-900 hover:bg-stone-50";
                      }

                      return html`
                        <li role="presentation" data-index=${index}>
                          <button
                            id="community-option-${community.community_id}"
                            type="button"
                            class="community-button w-full px-4 py-2 whitespace-normal min-h-10 flex flex-col justify-center text-left focus:outline-none ${statusClass}"
                            role="option"
                            ?disabled=${isDisabled}
                            @click=${(event) => this._handleCommunityClick(event, community)}
                            @mouseover=${() => (this._activeIndex = index)}
                          >
                            <div class="text-xs/4 line-clamp-2">
                              ${community.display_name || community.name}
                            </div>
                          </button>
                        </li>
                      `;
                    },
                  )}
                </ul>
              `
            : html`<div class="px-4 py-3 text-sm text-stone-500">No communities found.</div>`}
        </div>
      </div>
    `;
  }
}

if (!customElements.get("community-selector")) {
  customElements.define("community-selector", CommunitySelector);
}
