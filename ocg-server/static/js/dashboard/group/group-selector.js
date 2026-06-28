import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { showErrorAlert } from "/static/js/common/alerts.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { selectDashboardAndKeepTab } from "/static/js/common/dashboard-selection.js";
import { focusElementById } from "/static/js/common/dom.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * GroupSelector renders a searchable dropdown to pick a single group.
 *
 * Keyboard interactions follow the ARIA combobox pattern. Down and Up move the
 * highlight, Enter selects the highlighted item and Escape closes the menu.
 * Typing in the search field filters results with a debounce to reduce
 * re-render pressure while the user is typing.
 *
 * @property {Array<object>} groups List of groups for the selected alliance
 * @property {string} selectedGroupId Currently selected group identifier
 */
export class GroupSelector extends LitWrapper {
  static properties = {
    groups: { type: Array, attribute: "groups" },
    selectedGroupId: { type: String, attribute: "selected-group-id" },
    _isSubmitting: { state: true },
  };

  constructor() {
    super();
    this.groups = [];
    this.selectedGroupId = "";
    this._isSubmitting = false;
    this._combobox = new ComboboxController(this, {
      getItemCount: () => this._filteredGroups.length,
      isInteractionBlocked: () => this._isSubmitting,
      canOpen: () => this.groups.length > 0,
      resetQueryOnToggle: true,
      onOpen: () => {
        this.updateComplete.then(() => {
          focusElementById(this, "group-search-input");
        });
      },
      onSelect: (index, event) => {
        const group = this._filteredGroups[index];
        if (group && !this._isSelected(group)) {
          this._handleGroupClick(event, group);
        }
      },
    });
  }

  /**
   * Stores the current query and triggers filtering with simple debounce.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    this._combobox.setQuery(event.target.value || "");
    this._combobox.scheduleSearchUpdate(() => {
      this._combobox.setActiveIndex(null);
    }, 200);
  }

  /**
   * Gets filtered groups based on current query.
   */
  get _filteredGroups() {
    const normalized = (this._combobox.query || "").trim().toLowerCase();
    if (!normalized) {
      return this.groups;
    }
    return this.groups.filter((group) => {
      return (group.name || "").toLowerCase().includes(normalized);
    });
  }

  /**
   * Triggers dashboard group selection and lets HTMX refresh the current URL.
   * @param {string|number} groupId Identifier of the group to select
   * @returns {Promise<void>}
   */
  async _selectDashboardGroup(groupId) {
    const url = `/dashboard/group/${groupId}/select`;
    await selectDashboardAndKeepTab(url);
  }

  /**
   * Handles clicks on a group option and closes the dropdown.
   * @param {MouseEvent} event Option click event
   * @param {object} group Associated group data
   */
  async _handleGroupClick(event, group) {
    if (this._isSelected(group) || this._isSubmitting) {
      event.preventDefault();
      return;
    }
    event.preventDefault();
    this._isSubmitting = true;
    this._combobox.close();
    try {
      await this._selectDashboardGroup(group.group_id);
    } catch (_) {
      showErrorAlert("Something went wrong selecting the group. Please try again later.");
    } finally {
      this._isSubmitting = false;
    }
  }

  /**
   * Returns the selected group object, or null when none is selected.
   * @returns {object|null}
   */
  _findSelectedGroup() {
    const groups = this.groups;
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
    const isDisabled = this.groups.length === 0 || this._isSubmitting;

    return html`<div>
        <div class="my-4">
          <div class="relative">
            <button
              id="group-selector-button"
              type="button"
              class="select select-primary relative text-left pe-9 ${
                isDisabled ? "opacity-60 cursor-not-allowed" : "cursor-pointer"
              }"
              ?disabled=${isDisabled}
              aria-haspopup="listbox"
              aria-expanded=${this._combobox.isOpen ? "true" : "false"}
              @click=${() => this._combobox.toggle()}
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
                    id="group-search-input"
                    type="search"
                    class="input-primary w-full ps-9"
                    placeholder="Search groups"
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
                this._filteredGroups.length > 0
                  ? html`
                      <ul
                        id="group-selector-list"
                        class="max-h-48 overflow-y-auto text-stone-700"
                        role="listbox"
                      >
                        ${repeat(
                          this._filteredGroups,
                          (group) => group.group_id,
                          (group, index) => {
                            const isSelected = this._isSelected(group);
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
                                  id="group-option-${group.group_id}"
                                  type="button"
                                  class="group-button w-full px-4 py-2 whitespace-normal min-h-10 flex flex-col justify-center text-left focus:outline-none ${statusClass}"
                                  role="option"
                                  ?disabled=${isDisabled}
                                  @click=${(event) => this._handleGroupClick(event, group)}
                                  @mouseover=${() => this._combobox.setActiveIndex(index)}
                                >
                                  <div class="text-xs/4 line-clamp-2">${group.name}</div>
                                </button>
                              </li>
                            `;
                          },
                        )}
                      </ul>
                    `
                  : html`<div class="px-4 py-3 text-sm text-stone-500">No groups found.</div>`
              }
            </div>
          </div>
        </div>
      </div>
      ${
        selectedGroup && !selectedGroup.active
          ? html`<div
              class="mt-2 text-xs text-orange-700 bg-orange-50 border border-orange-200 rounded px-3 py-2"
            >
              This group has been deactivated. Please contact to a alliance admin.
            </div>`
          : ""
      } `;
  }
}

customElements.define("group-selector", GroupSelector);
