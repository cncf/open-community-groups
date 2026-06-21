import { expect } from "@open-wc/testing";

import { initializeAllianceSettings } from "/static/js/dashboard/alliance/settings-form.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard alliance settings page", () => {
  const renderSettingsForm = ({ checked = false } = {}) => {
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

  it("initializes swapped settings content on htmx load", () => {
    // Prepare the settings form as swapped dashboard content.
    renderSettingsForm({ checked: true });

    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.body);

    // Verify the hidden input is synced from the swapped form state.
    expect(document.getElementById("group_team_management_restricted").value).to.equal("true");
  });
});
