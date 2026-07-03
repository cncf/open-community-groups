import { getElementById, initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";
import { bindBooleanToggle } from "/static/js/dashboard/group/page-form-state.js";

const GROUPS_FORM_ID = "groups-form";
const COFFEE_MEET_TOGGLE_ID = "toggle_coffee_meet_enabled";
const COFFEE_MEET_INPUT_ID = "coffee_meet_enabled";
const GROUP_SETTINGS_BOUND_KEY = "groupSettingsBound";

/**
 * Initializes group settings form behavior.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
export const initializeGroupSettings = (root = document) => {
  const groupsForm = getElementById(root, GROUPS_FORM_ID);
  if (!markDatasetReady(groupsForm, GROUP_SETTINGS_BOUND_KEY)) {
    return;
  }

  bindBooleanToggle({
    toggle: getElementById(root, COFFEE_MEET_TOGGLE_ID),
    hiddenInput: getElementById(root, COFFEE_MEET_INPUT_ID),
    syncOnInit: true,
  });
};

initializeOnReadyAndHtmxLoad(initializeGroupSettings);
