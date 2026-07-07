import { DashboardSelectorBase } from "/static/js/dashboard/dashboard-selector-base.js";

/**
 * CommunitySelector renders a searchable dropdown to pick a single community.
 *
 * @property {Array<object>} communities List of communities with community_id,
 *   community_name and display_name keys
 * @property {string} selectedCommunityId Currently selected community identifier
 * @property {string} selectEndpoint API endpoint for selecting community
 */
export class CommunitySelector extends DashboardSelectorBase {
  static properties = {
    communities: {
      attribute: "communities",
      type: Array,
    },
    selectedCommunityId: { type: String, attribute: "selected-community-id" },
    selectEndpoint: { type: String, attribute: "select-endpoint" },
  };

  constructor() {
    super({
      selectorName: "community",
      itemsProperty: "communities",
      selectedIdProperty: "selectedCommunityId",
      idField: "community_id",
      defaultLabel: "Select a community",
      searchPlaceholder: "Search communities",
      emptyLabel: "No communities found.",
      errorLabel: "community",
      endpointBase: () => this.selectEndpoint,
      getItemLabel: (community) => community.display_name || community.name || "",
      optionHandlerName: "_handleCommunityClick",
      debounceQuery: true,
    });
    this.communities = [];
    this.selectedCommunityId = "";
    this.selectEndpoint = "/dashboard/community";
  }

  /**
   * Gets filtered communities based on current query.
   * @returns {Array<object>}
   */
  get _filteredCommunities() {
    return this._filteredItems;
  }

  /**
   * Triggers dashboard community selection and lets HTMX refresh the current URL.
   * @param {string|number} communityId Identifier of the community to select
   * @returns {Promise<void>}
   */
  async _selectDashboardCommunity(communityId) {
    await this._selectDashboardItem(communityId);
  }

  /**
   * Handles clicks on a community option and closes the dropdown.
   * @param {MouseEvent} event Option click event
   * @param {object} community Associated community data
   */
  async _handleCommunityClick(event, community) {
    await this._handleItemClick(event, community);
  }

  /**
   * Returns the selected community object, or null when none is selected.
   * @returns {object|null}
   */
  _findSelectedCommunity() {
    return this._findSelectedItem();
  }

  /**
   * Checks whether the provided community matches the selected identifier.
   * @param {object} community Community metadata
   * @returns {boolean}
   */
  _isSelected(community) {
    return super._isSelected(community);
  }
}

if (!customElements.get("community-selector")) {
  customElements.define("community-selector", CommunitySelector);
}
