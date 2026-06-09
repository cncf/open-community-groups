import { searchOnEnter } from "/static/js/community/explore/filters.js";
import { selectDashboardAndSwapBody } from "/static/js/common/dashboard-selection.js";
import {
  closestElementWithinRoot,
  getElementById,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";

const GROUPS_SEARCH_FORM_ID = "groups-search-form";
const GROUPS_SEARCH_INPUT_ID = "search_groups";
const GROUPS_LIST_ID = "groups-list";
const GROUP_ACTION_BUTTON_SELECTOR = ".btn-group-actions";
const GROUP_SEARCH_BOUND_KEY = "groupsSearchBound";
const GROUP_SELECTION_BOUND_KEY = "groupSelectionBound";
const GROUP_ACTION_BOUND_KEY = "groupActionBound";

/**
 * Initializes search input behavior for the community groups list.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
const initializeGroupsSearch = (root = document) => {
  const searchInput = getElementById(root, GROUPS_SEARCH_INPUT_ID);
  if (!markDatasetReady(searchInput, GROUP_SEARCH_BOUND_KEY)) {
    return;
  }

  searchInput.addEventListener("keydown", (event) => {
    searchOnEnter(event, GROUPS_SEARCH_FORM_ID);
  });
};

/**
 * Initializes dashboard selection from group name buttons.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
const initializeGroupSelection = (root = document) => {
  const groupsList = getElementById(root, GROUPS_LIST_ID);
  if (!markDatasetReady(groupsList, GROUP_SELECTION_BOUND_KEY)) {
    return;
  }

  let isSelectingGroup = false;

  groupsList.addEventListener("click", async (event) => {
    const selectGroupButton = closestElementWithinRoot(event.target, "[data-select-group-id]", groupsList);
    if (!selectGroupButton) {
      return;
    }

    event.preventDefault();
    if (isSelectingGroup) {
      return;
    }

    const groupId = selectGroupButton.dataset.selectGroupId;
    if (!groupId) {
      return;
    }

    isSelectingGroup = true;
    selectGroupButton.setAttribute("disabled", "disabled");
    try {
      await selectDashboardAndSwapBody(`/dashboard/group/${groupId}/select`, "/dashboard/group");
    } catch (error) {
      console.warn("Failed to select group from groups list:", error);
    } finally {
      selectGroupButton.removeAttribute("disabled");
      isSelectingGroup = false;
    }
  });
};

/**
 * Initializes action dropdown behavior for community group rows.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
const initializeGroupActionMenus = (root = document) => {
  root.querySelectorAll?.(GROUP_ACTION_BUTTON_SELECTOR).forEach((button) => {
    if (!markDatasetReady(button, GROUP_ACTION_BOUND_KEY)) {
      return;
    }

    button.addEventListener("click", () => {
      const groupId = button.dataset.groupId;
      const dropdown = getElementById(root, `dropdown-group-actions-${groupId}`);
      if (!dropdown) {
        return;
      }

      const isHidden = isElementHidden(dropdown);
      setElementHidden(dropdown, !isHidden);

      if (isHidden) {
        const outsideClick = (event) => {
          if (!dropdown.contains(event.target) && !button.contains(event.target)) {
            setElementHidden(dropdown, true);
            document.removeEventListener("click", outsideClick);
          }
        };
        setTimeout(() => document.addEventListener("click", outsideClick), 0);
      }
    });
  });
};

/**
 * Initializes community groups list behavior for the current content root.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
export const initializeCommunityGroupsList = (root = document) => {
  initializeGroupsSearch(root);
  initializeGroupSelection(root);
  initializeGroupActionMenus(root);
};

initializeOnReadyAndHtmxLoad(initializeCommunityGroupsList);
