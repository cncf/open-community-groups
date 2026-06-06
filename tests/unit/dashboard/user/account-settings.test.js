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

  it("syncs optional notification state when a swapped root initializes", () => {
    // Build a swapped account settings fixture with the toggle already checked.
    const pageRoot = document.createElement("section");
    pageRoot.innerHTML = `
      <input type="hidden" id="optional_notifications_enabled" value="false" />
      <input type="checkbox" id="toggle_optional_notifications_enabled" checked />
    `;
    document.body.append(pageRoot);

    // Initialize the swapped root.
    initializeUserAccountSettings(pageRoot);

    // The hidden input mirrors the checked state before the user changes it.
    expect(
      pageRoot.querySelector("#optional_notifications_enabled")?.value,
    ).to.equal("true");
  });

  it("binds the account settings change listener once", () => {
    // Build the DOM fixture with the notifications hidden input and toggle.
    document.body.innerHTML = `
      <input type="hidden" id="optional_notifications_enabled" value="false" />
      <input type="checkbox" id="toggle_optional_notifications_enabled" />
    `;
    delete document.documentElement.dataset.userAccountSettingsReady;

    // Initialize account settings twice and change the toggle.
    initializeUserAccountSettings();
    initializeUserAccountSettings();
    const toggle = document.getElementById("toggle_optional_notifications_enabled");
    toggle.checked = true;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // The single document listener still keeps the hidden input in sync.
    expect(
      document.getElementById("optional_notifications_enabled")?.value,
    ).to.equal("true");
  });

  it("syncs optional notifications within the toggle form", () => {
    // Build two matching field sets to verify the form-scoped sync target.
    document.body.innerHTML = `
      <input type="hidden" id="optional_notifications_enabled" value="outside" />
      <form>
        <input type="hidden" id="optional_notifications_enabled" value="false" />
        <input type="checkbox" id="toggle_optional_notifications_enabled" />
      </form>
    `;
    delete document.documentElement.dataset.userAccountSettingsReady;

    // Initialize account settings and change the toggle inside the form.
    const form = document.querySelector("form");
    initializeUserAccountSettings(form);
    const toggle = form.querySelector("#toggle_optional_notifications_enabled");
    toggle.checked = true;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // The form field changes while the unrelated matching id remains untouched.
    expect(
      document.querySelector("form #optional_notifications_enabled")?.value,
    ).to.equal("true");
    expect(
      document.body.firstElementChild?.value,
    ).to.equal("outside");
  });
});
