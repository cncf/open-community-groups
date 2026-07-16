import { getElementById, initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";
import { bindBooleanToggle } from "/static/js/dashboard/group/page-form-state.js";

const SETTINGS_FORM_ID = "settings-form";
const COFFEE_MEET_TOGGLE_ID = "toggle_coffee_meet_enabled";
const COFFEE_MEET_INPUT_ID = "coffee_meet_enabled";
const MENTORSHIP_TOGGLE_ID = "toggle_mentorship_enabled";
const MENTORSHIP_INPUT_ID = "mentorship_enabled";
const MOCK_INTERVIEWS_TOGGLE_ID = "toggle_mock_interviews_enabled";
const MOCK_INTERVIEWS_INPUT_ID = "mock_interviews_enabled";
const INTENTIONAL_DATING_TOGGLE_ID = "toggle_intentional_dating_enabled";
const INTENTIONAL_DATING_INPUT_ID = "intentional_dating_enabled";
const GROUP_TEAM_RESTRICTION_TOGGLE_ID = "toggle_group_team_management_restricted";
const GROUP_TEAM_RESTRICTION_INPUT_ID = "group_team_management_restricted";
const SETTINGS_BOUND_KEY = "allianceSettingsBound";

/**
 * Initializes alliance settings form behavior.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
export const initializeAllianceSettings = (root = document) => {
  const settingsForm = getElementById(root, SETTINGS_FORM_ID);
  if (!markDatasetReady(settingsForm, SETTINGS_BOUND_KEY)) {
    return;
  }

  const groupTeamRestrictionToggle = getElementById(root, GROUP_TEAM_RESTRICTION_TOGGLE_ID);
  const groupTeamRestrictionInput = getElementById(root, GROUP_TEAM_RESTRICTION_INPUT_ID);
  const coffeeMeetToggle = getElementById(root, COFFEE_MEET_TOGGLE_ID);
  const coffeeMeetInput = getElementById(root, COFFEE_MEET_INPUT_ID);
  const mentorshipToggle = getElementById(root, MENTORSHIP_TOGGLE_ID);
  const mentorshipInput = getElementById(root, MENTORSHIP_INPUT_ID);
  const mockInterviewsToggle = getElementById(root, MOCK_INTERVIEWS_TOGGLE_ID);
  const mockInterviewsInput = getElementById(root, MOCK_INTERVIEWS_INPUT_ID);
  const intentionalDatingToggle = getElementById(root, INTENTIONAL_DATING_TOGGLE_ID);
  const intentionalDatingInput = getElementById(root, INTENTIONAL_DATING_INPUT_ID);

  bindBooleanToggle({
    toggle: groupTeamRestrictionToggle,
    hiddenInput: groupTeamRestrictionInput,
    syncOnInit: true,
  });

  bindBooleanToggle({
    toggle: coffeeMeetToggle,
    hiddenInput: coffeeMeetInput,
    syncOnInit: true,
  });

  bindBooleanToggle({
    toggle: mentorshipToggle,
    hiddenInput: mentorshipInput,
    syncOnInit: true,
  });

  bindBooleanToggle({
    toggle: mockInterviewsToggle,
    hiddenInput: mockInterviewsInput,
    syncOnInit: true,
  });

  bindBooleanToggle({
    toggle: intentionalDatingToggle,
    hiddenInput: intentionalDatingInput,
    syncOnInit: true,
  });
};

initializeOnReadyAndHtmxLoad(initializeAllianceSettings);
