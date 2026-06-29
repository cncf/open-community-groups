import { html, repeat } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { showErrorAlert } from "/static/js/common/alerts.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { selectDashboardAndKeepTab } from "/static/js/common/dashboard-selection.js";
import { focusElementById } from "/static/js/common/dom.js";
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
    _isSubmitting: { state: true },
  };

  constructor() {
    super();
    this.communities = [];
    this.selectedCommunityId = "";
    this.selectEndpoint = "/dashboard/community";
    this._isSubmitting = false;
    this._pendingQuery = "";
    this._combobox = new ComboboxController(this, {
      getItemCount: () => this._filteredCommunities.length,
      isInteractionBlocked: () => this._isSubmitting,
      canOpen: () => this.communities.length > 0,
      resetQueryOnToggle: true,
      onOpen: () => {
        this._pendingQuery = "";
        this.updateComplete.then(() => {
          focusElementById(this, "community-search-input");
        });
      },
      onClose: () => {
        this._pendingQuery = "";
      },
      onSelect: (index, event) => {
        const community = this._filteredCommunities[index];
        if (community && !this._isSelected(community)) {
          this._handleCommunityClick(event, community);
        }
      },
    });
  }

  /**
   * Stores the current query and triggers filtering with simple debounce.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    this._pendingQuery = event.target.value || "";
    this._combobox.scheduleSearchUpdate(() => {
      this._combobox.setActiveIndex(null);
      this._combobox.setQuery(this._pendingQuery);
    }, 200);
  }

  /**
   * Gets filtered communities based on current query.
   */
  get _filteredCommunities() {
    const normalized = (this._combobox.query || "").trim().toLowerCase();
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
    this._combobox.close();
    try {
      await this._selectDashboardCommunity(community.community_id);
    } catch (_) {
      showErrorAlert("Something went wrong selecting the community. Please try again later.");
    } finally {
      this._isSubmitting = false;
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
          class="select select-primary relative text-left pe-9 ${
            isDisabled ? "opacity-80 cursor-not-allowed" : "cursor-pointer"
          }"
          ?disabled=${isDisabled}
          aria-haspopup="listbox"
          aria-expanded=${this._combobox.isOpen ? "true" : "false"}
          @click=${() => this._combobox.toggle()}
        >
          <div class="flex flex-col justify-center min-h-10">
            <div class="text-xs/4 text-stone-900 line-clamp-2">
              ${
                selectedCommunity
                  ? selectedCommunity.display_name || selectedCommunity.name
                  : "Select a community"
              }
            </div>
          </div>
          <div class="absolute inset-y-0 end-0 flex items-center pe-3 pointer-events-none">
            <div class="svg-icon size-3 icon-caret-down bg-stone-600"></div>
          </div>
        </button>

        <div
          class="absolute top-14 left-0 right-0 z-10 bg-white rounded-lg shadow-sm border border-stone-200 ${
            this._combobox.isOpen ? "" : "hidden"
          }"
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
                .value=${this._combobox.query}
                @input=${(event) => this._handleSearchInput(event)}
              />
            </div>
          </div>

          ${
            this._filteredCommunities.length > 0
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
                      const isActive = this._combobox.activeIndex === index;
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
                            @mouseover=${() => this._combobox.setActiveIndex(index)}
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
              : html`<div class="px-4 py-3 text-sm text-stone-500">No communities found.</div>`
          }
        </div>
      </div>
    `;
  }
}

if (!customElements.get("community-selector")) {
  customElements.define("community-selector", CommunitySelector);
}
