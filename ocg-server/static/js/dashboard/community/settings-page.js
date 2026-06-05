import {
  getElementById,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { bindBooleanToggle } from "/static/js/dashboard/group/page-form-state.js";

const SETTINGS_FORM_ID = "settings-form";
const GROUP_TEAM_RESTRICTION_TOGGLE_ID = "toggle_group_team_management_restricted";
const GROUP_TEAM_RESTRICTION_INPUT_ID = "group_team_management_restricted";
const SETTINGS_BOUND_KEY = "communitySettingsBound";

/**
 * Initializes community settings form behavior.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
export const initializeCommunitySettings = (root = document) => {
  const settingsForm = getElementById(root, SETTINGS_FORM_ID);
  if (!markDatasetReady(settingsForm, SETTINGS_BOUND_KEY)) {
    return;
  }

  const groupTeamRestrictionToggle = getElementById(root, GROUP_TEAM_RESTRICTION_TOGGLE_ID);
  const groupTeamRestrictionInput = getElementById(root, GROUP_TEAM_RESTRICTION_INPUT_ID);

  bindBooleanToggle({
    toggle: groupTeamRestrictionToggle,
    hiddenInput: groupTeamRestrictionInput,
    syncOnInit: true,
  });
};

initializeOnReadyAndHtmxLoad(initializeCommunitySettings);
