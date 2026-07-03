import { expect } from "@open-wc/testing";

import { initializeGroupSettings } from "/static/js/dashboard/group/settings-form.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard group settings page", () => {
  const renderSettingsForm = ({ checked = false } = {}) => {
    document.body.innerHTML = `
      <form id="groups-form">
        <input
          id="coffee_meet_enabled"
          name="coffee_meet_enabled"
          type="hidden"
          value="stale"
        >
        <input
          id="toggle_coffee_meet_enabled"
          name="toggle_coffee_meet_enabled"
          type="checkbox"
          ${checked ? "checked" : ""}
        >
      </form>
    `;
  };

  afterEach(() => {
    resetDom();
  });

  it("syncs the CoffeeMeet value on init and change", () => {
    // Prepare the group settings form with CoffeeMeet enabled.
    renderSettingsForm({ checked: true });

    // Initialize settings behavior.
    initializeGroupSettings();

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
    // Prepare the group settings form as swapped dashboard content.
    renderSettingsForm({ checked: true });

    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.body);

    // Verify the hidden input is synced from the swapped form state.
    expect(document.getElementById("coffee_meet_enabled").value).to.equal("true");
  });
});
