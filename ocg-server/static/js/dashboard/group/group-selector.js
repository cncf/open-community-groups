import { html } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { DashboardSelectorBase } from "/static/js/dashboard/dashboard-selector-base.js";

/**
 * GroupSelector renders a searchable dropdown to pick a single group.
 *
 * @property {Array<object>} groups List of groups for the selected community
 * @property {string} selectedGroupId Currently selected group identifier
 */
export class GroupSelector extends DashboardSelectorBase {
  static properties = {
    groups: { type: Array, attribute: "groups" },
    selectedGroupId: { type: String, attribute: "selected-group-id" },
  };

  constructor() {
    super({
      selectorName: "group",
      itemsProperty: "groups",
      selectedIdProperty: "selectedGroupId",
      idField: "group_id",
      defaultLabel: "Select a group",
      searchPlaceholder: "Search groups",
      emptyLabel: "No groups found.",
      errorLabel: "group",
      endpointBase: "/dashboard/group",
      getItemLabel: (group) => group.name || "",
      optionHandlerName: "_handleGroupClick",
      disableWhenEmpty: true,
      disabledOpacityClass: "opacity-60",
      wrapperClass: "my-4",
    });
    this.groups = [];
    this.selectedGroupId = "";
  }

  /**
   * Gets filtered groups based on current query.
   * @returns {Array<object>}
   */
  get _filteredGroups() {
    return this._filteredItems;
  }

  /**
   * Triggers dashboard group selection and lets HTMX refresh the current URL.
   * @param {string|number} groupId Identifier of the group to select
   * @returns {Promise<void>}
   */
  async _selectDashboardGroup(groupId) {
    await this._selectDashboardItem(groupId);
  }

  /**
   * Handles clicks on a group option and closes the dropdown.
   * @param {MouseEvent} event Option click event
   * @param {object} group Associated group data
   */
  async _handleGroupClick(event, group) {
    await this._handleItemClick(event, group);
  }

  /**
   * Returns the selected group object, or null when none is selected.
   * @returns {object|null}
   */
  _findSelectedGroup() {
    return this._findSelectedItem();
  }

  /**
   * Checks whether the provided group matches the selected identifier.
   * @param {object} group Group metadata
   * @returns {boolean}
   */
  _isSelected(group) {
    return super._isSelected(group);
  }

  /**
   * Renders a warning when the selected group has been deactivated.
   * @param {object|null} selectedGroup Selected group metadata
   * @returns {import("lit").TemplateResult|string}
   */
  _renderAfterSelector(selectedGroup) {
    if (!selectedGroup || selectedGroup.active) {
      return "";
    }
    return html`<div
      class="mt-2 text-xs text-orange-700 bg-orange-50 border border-orange-200 rounded px-3 py-2"
    >
      This group has been deactivated. Please contact to a community admin.
    </div>`;
  }
}

if (!customElements.get("group-selector")) {
  customElements.define("group-selector", GroupSelector);
}
