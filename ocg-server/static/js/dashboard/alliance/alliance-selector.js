import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { showErrorAlert } from "/static/js/common/alerts.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { selectDashboardAndKeepTab } from "/static/js/common/dashboard-selection.js";
import { focusElementById } from "/static/js/common/dom.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * AllianceSelector renders a searchable dropdown to pick a single alliance.
 *
 * Keyboard interactions follow the ARIA combobox pattern. Down and Up move the
 * highlight, Enter selects the highlighted item and Escape closes the menu.
 * Typing in the search field filters results with a debounce to reduce
 * re-render pressure while the user is typing.
 *
 * @property {Array<object>} alliances List of alliances with alliance_id,
 *   alliance_name and display_name keys
 * @property {string} selectedAllianceId Currently selected alliance identifier
 * @property {string} selectEndpoint API endpoint for selecting alliance
 */
export class AllianceSelector extends LitWrapper {
  static properties = {
    alliances: {
      attribute: "alliances",
      type: Array,
    },
    selectedAllianceId: { type: String, attribute: "selected-alliance-id" },
    selectEndpoint: { type: String, attribute: "select-endpoint" },
    _isSubmitting: { state: true },
  };

  constructor() {
    super();
    this.alliances = [];
    this.selectedAllianceId = "";
    this.selectEndpoint = "/dashboard/alliance";
    this._isSubmitting = false;
    this._pendingQuery = "";
    this._combobox = new ComboboxController(this, {
      getItemCount: () => this._filteredAlliances.length,
      isInteractionBlocked: () => this._isSubmitting,
      canOpen: () => this.alliances.length > 0,
      resetQueryOnToggle: true,
      onOpen: () => {
        this._pendingQuery = "";
        this.updateComplete.then(() => {
          focusElementById(this, "alliance-search-input");
        });
      },
      onClose: () => {
        this._pendingQuery = "";
      },
      onSelect: (index, event) => {
        const alliance = this._filteredAlliances[index];
        if (alliance && !this._isSelected(alliance)) {
          this._handleAllianceClick(event, alliance);
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
   * Gets filtered alliances based on current query.
   */
  get _filteredAlliances() {
    const normalized = (this._combobox.query || "").trim().toLowerCase();
    if (!normalized) {
      return this.alliances;
    }
    return this.alliances.filter((alliance) => {
      const name = (alliance.display_name || alliance.name || "").toLowerCase();
      return name.includes(normalized);
    });
  }

  /**
   * Triggers dashboard alliance selection and lets HTMX refresh the current URL.
   * @param {string|number} allianceId Identifier of the alliance to select
   * @returns {Promise<void>}
   */
  async _selectDashboardAlliance(allianceId) {
    const url = `${this.selectEndpoint}/${allianceId}/select`;
    await selectDashboardAndKeepTab(url);
  }

  /**
   * Handles clicks on a alliance option and closes the dropdown.
   * @param {MouseEvent} event Option click event
   * @param {object} alliance Associated alliance data
   */
  async _handleAllianceClick(event, alliance) {
    if (this._isSelected(alliance) || this._isSubmitting) {
      event.preventDefault();
      return;
    }
    event.preventDefault();
    this._isSubmitting = true;
    this._combobox.close();
    try {
      await this._selectDashboardAlliance(alliance.alliance_id);
    } catch (_) {
      showErrorAlert("Something went wrong selecting the alliance. Please try again later.");
    } finally {
      this._isSubmitting = false;
    }
  }

  /**
   * Returns the selected alliance object, or null when none is selected.
   * @returns {object|null}
   */
  _findSelectedAlliance() {
    const alliances = this.alliances;
    if (!alliances || alliances.length === 0) {
      return null;
    }
    const targetId = this.selectedAllianceId != null ? String(this.selectedAllianceId) : "";
    return alliances.find((alliance) => String(alliance.alliance_id) === targetId) || null;
  }

  /**
   * Checks whether the provided alliance matches the selected identifier.
   * @param {object} alliance Alliance metadata
   * @returns {boolean}
   */
  _isSelected(alliance) {
    return String(alliance.alliance_id) === String(this.selectedAllianceId || "");
  }

  render() {
    const selectedAlliance = this._findSelectedAlliance();
    const isDisabled = this._isSubmitting;

    return html`
      <div class="relative">
        <button
          id="alliance-selector-button"
          type="button"
          class="select select-primary relative text-left pe-9 ${isDisabled
            ? "opacity-80 cursor-not-allowed"
            : "cursor-pointer"}"
          ?disabled=${isDisabled}
          aria-haspopup="listbox"
          aria-expanded=${this._combobox.isOpen ? "true" : "false"}
          @click=${() => this._combobox.toggle()}
        >
          <div class="flex flex-col justify-center min-h-10">
            <div class="text-xs/4 text-stone-900 line-clamp-2">
              ${selectedAlliance
                ? selectedAlliance.display_name || selectedAlliance.name
                : "Select a alliance"}
            </div>
          </div>
          <div class="absolute inset-y-0 end-0 flex items-center pe-3 pointer-events-none">
            <div class="svg-icon size-3 icon-caret-down bg-stone-600"></div>
          </div>
        </button>

        <div
          class="absolute top-14 left-0 right-0 z-10 bg-white rounded-lg shadow-sm border border-stone-200 ${this
            ._combobox.isOpen
            ? ""
            : "hidden"}"
        >
          <div class="p-3 border-b border-stone-200">
            <div class="relative">
              <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
                <div class="svg-icon size-4 icon-search bg-stone-300"></div>
              </div>
              <input
                id="alliance-search-input"
                type="search"
                class="input-primary w-full ps-9"
                placeholder="Search alliances"
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                spellcheck="false"
                .value=${this._combobox.query}
                @input=${(event) => this._handleSearchInput(event)}
              />
            </div>
          </div>

          ${this._filteredAlliances.length > 0
            ? html`
                <ul
                  id="alliance-selector-list"
                  class="max-h-48 overflow-y-auto text-stone-700"
                  role="listbox"
                >
                  ${repeat(
                    this._filteredAlliances,
                    (alliance) => alliance.alliance_id,
                    (alliance, index) => {
                      const isSelected = this._isSelected(alliance);
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
                            id="alliance-option-${alliance.alliance_id}"
                            type="button"
                            class="alliance-button w-full px-4 py-2 whitespace-normal min-h-10 flex flex-col justify-center text-left focus:outline-none ${statusClass}"
                            role="option"
                            ?disabled=${isDisabled}
                            @click=${(event) => this._handleAllianceClick(event, alliance)}
                            @mouseover=${() => this._combobox.setActiveIndex(index)}
                          >
                            <div class="text-xs/4 line-clamp-2">
                              ${alliance.display_name || alliance.name}
                            </div>
                          </button>
                        </li>
                      `;
                    },
                  )}
                </ul>
              `
            : html`<div class="px-4 py-3 text-sm text-stone-500">No alliances found.</div>`}
        </div>
      </div>
    `;
  }
}

if (!customElements.get("alliance-selector")) {
  customElements.define("alliance-selector", AllianceSelector);
}
