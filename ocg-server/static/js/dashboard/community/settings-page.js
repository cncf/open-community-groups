import { bindBooleanToggle } from "/static/js/dashboard/group/page-form-state.js";

const SETTINGS_FORM_ID = "settings-form";
const GROUP_TEAM_RESTRICTION_TOGGLE_ID = "toggle_group_team_management_restricted";
const GROUP_TEAM_RESTRICTION_INPUT_ID = "group_team_management_restricted";
const SETTINGS_BOUND_KEY = "communitySettingsBound";

/**
 * Returns an element by ID from a document or element root.
 * @param {Document|Element} root - Root element to search from.
 * @param {string} id - Element ID.
 * @returns {HTMLElement|null} Matching element.
 */
const getElementById = (root, id) => {
  if (root instanceof HTMLElement && root.id === id) {
    return root;
  }

  const element = root.getElementById?.(id) || root.querySelector?.(`#${id}`);
  return element instanceof HTMLElement ? element : null;
};

/**
 * Initializes community settings form behavior.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
export const initializeCommunitySettings = (root = document) => {
  const settingsForm = getElementById(root, SETTINGS_FORM_ID);
  if (!settingsForm || settingsForm.dataset[SETTINGS_BOUND_KEY] === "true") {
    return;
  }

  const groupTeamRestrictionToggle = getElementById(root, GROUP_TEAM_RESTRICTION_TOGGLE_ID);
  const groupTeamRestrictionInput = getElementById(root, GROUP_TEAM_RESTRICTION_INPUT_ID);

  settingsForm.dataset[SETTINGS_BOUND_KEY] = "true";
  bindBooleanToggle({
    toggle: groupTeamRestrictionToggle,
    hiddenInput: groupTeamRestrictionInput,
    syncOnInit: true,
  });
};

const initializeCommunitySettingsWhenReady = () => {
  // Initialize current settings form on first load and after HTMX swaps.
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => initializeCommunitySettings(document), {
      once: true,
    });
  } else {
    initializeCommunitySettings(document);
  }

  document.addEventListener("htmx:load", (event) => {
    const root = event.target instanceof Element ? event.target : document;
    initializeCommunitySettings(root);
  });
};

initializeCommunitySettingsWhenReady();
