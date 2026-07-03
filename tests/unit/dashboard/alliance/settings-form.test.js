import { expect } from "@open-wc/testing";

import { initializeAllianceSettings } from "/static/js/dashboard/alliance/settings-form.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard alliance settings page", () => {
  const renderSettingsForm = ({ checked = false, coffeeMeetChecked = false, mentorshipChecked = false } = {}) => {
    document.body.innerHTML = `
      <form id="settings-form">
        <input
          id="toggle_group_team_management_restricted"
          name="toggle_group_team_management_restricted"
          type="checkbox"
          ${checked ? "checked" : ""}
        >
        <input
          id="group_team_management_restricted"
          name="group_team_management_restricted"
          type="hidden"
          value="stale"
        >
        <input
          id="toggle_coffee_meet_enabled"
          name="toggle_coffee_meet_enabled"
          type="checkbox"
          ${coffeeMeetChecked ? "checked" : ""}
        >
        <input
          id="coffee_meet_enabled"
          name="coffee_meet_enabled"
          type="hidden"
          value="stale"
        >
        <input
          id="toggle_mentorship_enabled"
          name="toggle_mentorship_enabled"
          type="checkbox"
          ${mentorshipChecked ? "checked" : ""}
        >
        <input
          id="mentorship_enabled"
          name="mentorship_enabled"
          type="hidden"
          value="stale"
        >
      </form>
    `;
  };

  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("syncs the group team restriction value on init and change", () => {
    // Prepare the settings form with the restriction toggle enabled.
    renderSettingsForm({ checked: true });

    // Initialize settings behavior twice to verify duplicate handlers are guarded.
    initializeAllianceSettings();
    initializeAllianceSettings();

    const toggle = document.getElementById("toggle_group_team_management_restricted");
    const hiddenInput = document.getElementById("group_team_management_restricted");

    // Verify initialization mirrors the toggle state.
    expect(hiddenInput.value).to.equal("true");

    // Disable the toggle.
    toggle.checked = false;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Verify the hidden input changes once with the toggle state.
    expect(hiddenInput.value).to.equal("false");
  });

  it("syncs the CoffeeMeet value on init and change", () => {
    // Prepare the settings form with CoffeeMeet enabled.
    renderSettingsForm({ coffeeMeetChecked: true });

    // Initialize settings behavior.
    initializeAllianceSettings();

    const toggle = document.getElementById("toggle_coffee_meet_enabled");
    const hiddenInput = document.getElementById("coffee_meet_enabled");

    // Verify initialization mirrors the toggle state.
    expect(hiddenInput.value).to.equal("true");

    // Disable the toggle.
    toggle.checked = false;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Verify the submitted hidden field carries the disabled value.
    expect(hiddenInput.value).to.equal("false");
  });

  it("initializes swapped settings content on htmx load", () => {
    // Prepare the settings form as swapped dashboard content.
    renderSettingsForm({ checked: true });

    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.body);

    // Verify the hidden input is synced from the swapped form state.
    expect(document.getElementById("group_team_management_restricted").value).to.equal("true");
  });

  it("syncs CoffeeMeet and mentorship feature values", () => {
    // Prepare both feature toggles in opposite initial states.
    renderSettingsForm({ coffeeMeetChecked: true, mentorshipChecked: false });

    // Initialize settings behavior.
    initializeAllianceSettings();

    const coffeeMeetToggle = document.getElementById("toggle_coffee_meet_enabled");
    const coffeeMeetInput = document.getElementById("coffee_meet_enabled");
    const mentorshipToggle = document.getElementById("toggle_mentorship_enabled");
    const mentorshipInput = document.getElementById("mentorship_enabled");

    // Verify initialization mirrors each toggle state.
    expect(coffeeMeetInput.value).to.equal("true");
    expect(mentorshipInput.value).to.equal("false");

    // Flip both feature toggles.
    coffeeMeetToggle.checked = false;
    mentorshipToggle.checked = true;
    coffeeMeetToggle.dispatchEvent(new Event("change", { bubbles: true }));
    mentorshipToggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Verify hidden values match the current feature states.
    expect(coffeeMeetInput.value).to.equal("false");
    expect(mentorshipInput.value).to.equal("true");
  });
});
