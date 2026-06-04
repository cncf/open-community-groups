import { expect } from "@open-wc/testing";

import { initializeUserAccountSettings } from "/static/js/dashboard/user/account-settings.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard user account settings", () => {
  afterEach(() => {
    resetDom();
    delete document.documentElement.dataset.userAccountSettingsReady;
  });

  it("syncs optional notification toggle changes to the hidden input", () => {
    // Build the DOM fixture with the notifications hidden input and toggle.
    document.body.innerHTML = `
      <input type="hidden" id="optional_notifications_enabled" value="false" />
      <input type="checkbox" id="toggle_optional_notifications_enabled" />
    `;
    delete document.documentElement.dataset.userAccountSettingsReady;

    // Initialize account settings and change the toggle.
    initializeUserAccountSettings();
    const toggle = document.getElementById("toggle_optional_notifications_enabled");
    toggle.checked = true;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // The hidden input mirrors the checkbox state for form submission.
    expect(document.getElementById("optional_notifications_enabled")?.value).to.equal("true");
  });
});
