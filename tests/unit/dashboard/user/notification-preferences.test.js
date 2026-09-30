import { expect } from "@open-wc/testing";

import { initializeNotificationPreferences } from "/static/js/dashboard/user/notification-preferences.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

describe("dashboard user notification preferences", () => {
  afterEach(() => {
    resetDom();
  });

  it("syncs preference toggle changes to their hidden inputs", () => {
    // Build the DOM fixture with one preference hidden input and toggle.
    document.body.innerHTML = `
      <form>
        <input type="hidden" id="preference-new-events" value="false" />
        <input type="checkbox" id="toggle-preference-new-events" data-preference-input="preference-new-events" />
      </form>
    `;

    // Initialize preferences and change the toggle.
    initializeNotificationPreferences();
    const toggle = document.getElementById("toggle-preference-new-events");
    toggle.checked = true;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // The hidden input mirrors the checkbox state for form submission.
    expect(document.getElementById("preference-new-events")?.value).to.equal("true");
  });

  it("syncs preference state when a swapped root initializes", () => {
    // Build a swapped notifications fixture with the toggle already checked.
    const pageRoot = document.createElement("section");
    pageRoot.innerHTML = `
      <input type="hidden" id="preference-badges" value="false" />
      <input type="checkbox" id="toggle-preference-badges" data-preference-input="preference-badges" checked />
    `;
    document.body.append(pageRoot);

    // Initialize the swapped root through the same HTMX load path used in production.
    dispatchHtmxLoad(pageRoot);

    // The hidden input mirrors the checked state before the user changes it.
    expect(pageRoot.querySelector("#preference-badges")?.value).to.equal("true");
  });

  it("keeps independent preference toggles scoped to their own hidden inputs", () => {
    // Build two matching preference controls.
    document.body.innerHTML = `
      <form>
        <input type="hidden" id="preference-new-events" value="false" />
        <input type="checkbox" id="toggle-preference-new-events" data-preference-input="preference-new-events" />
        <input type="hidden" id="preference-badges" value="true" />
        <input type="checkbox" id="toggle-preference-badges" data-preference-input="preference-badges" checked />
      </form>
    `;

    // Initialize preferences and change each toggle to a different state.
    initializeNotificationPreferences();
    const newEvents = document.getElementById("toggle-preference-new-events");
    const badges = document.getElementById("toggle-preference-badges");
    newEvents.checked = true;
    badges.checked = false;
    newEvents.dispatchEvent(new Event("change", { bubbles: true }));
    badges.dispatchEvent(new Event("change", { bubbles: true }));

    // Each hidden input reflects only its paired toggle.
    expect(document.getElementById("preference-new-events")?.value).to.equal("true");
    expect(document.getElementById("preference-badges")?.value).to.equal("false");
  });

  it("resolves duplicate preference input ids within the closest form", () => {
    // Build duplicate IDs to verify delegated changes use the toggle form as the root.
    document.body.innerHTML = `
      <input type="hidden" id="preference-group-announcements" value="outside" />
      <form>
        <input type="hidden" id="preference-group-announcements" value="false" />
        <input
          type="checkbox"
          id="toggle-preference-group-announcements"
          data-preference-input="preference-group-announcements"
        />
      </form>
    `;

    // Initialize preferences and change the in-form toggle.
    const form = document.querySelector("form");
    initializeNotificationPreferences(form);
    const toggle = form.querySelector("#toggle-preference-group-announcements");
    toggle.checked = true;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // The form field changes while the unrelated matching id remains untouched.
    expect(form.querySelector("#preference-group-announcements")?.value).to.equal("true");
    expect(document.body.firstElementChild?.value).to.equal("outside");
  });
});
