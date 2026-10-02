import { expect } from "@open-wc/testing";

import { resetRestoredModalState } from "/static/js/common/modals/modal-lifecycle.js";
import { initializeNotificationPreferences } from "/static/js/dashboard/user/notification-preferences.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

describe("dashboard user notification preferences", () => {
  afterEach(() => {
    // Close open modals so scroll locks do not leak into other tests
    resetRestoredModalState(document);
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

  it("opens the always-sent modal from its description trigger and closes it from the header", () => {
    // Render the always-sent modal fixture
    const { modal, opener } = renderAlwaysSentModalFixture();
    initializeNotificationPreferences();

    // Open the modal from the description trigger
    opener.click();

    // The modal is visible, announced, and focused on its first control
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(modal.getAttribute("aria-hidden")).to.equal("false");
    expect(document.activeElement?.id).to.equal("close-always-sent-modal");

    // Close the modal from the header close control
    document.getElementById("close-always-sent-modal")?.click();

    // The modal hides and focus returns to the trigger
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(modal.getAttribute("aria-hidden")).to.equal("true");
    expect(document.activeElement).to.equal(opener);
  });

  it("closes the always-sent modal from the overlay and footer controls", () => {
    // Render the always-sent modal fixture
    const { modal, opener } = renderAlwaysSentModalFixture();
    initializeNotificationPreferences();

    // Open and close the modal from the overlay
    opener.click();
    document.getElementById("overlay-always-sent-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);

    // Open and close the modal from the footer button
    opener.click();
    document.getElementById("footer-close-always-sent-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.dataset.modalOpenCount).to.equal("0");
  });

  it("closes the always-sent modal with Escape and traps Tab inside it", () => {
    // Render the always-sent modal fixture and open it
    const { modal, opener } = renderAlwaysSentModalFixture();
    initializeNotificationPreferences();
    opener.click();

    // Press Tab on the last control
    document.getElementById("footer-close-always-sent-modal")?.focus();
    const tab = pressKey("Tab");

    // Focus wraps to the first control
    expect(tab.defaultPrevented).to.equal(true);
    expect(document.activeElement?.id).to.equal("close-always-sent-modal");

    // Press Escape
    const escape = pressKey("Escape");

    // The modal closes and focus returns to the trigger
    expect(escape.defaultPrevented).to.equal(true);
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.activeElement).to.equal(opener);
  });

  it("ignores Escape while the always-sent modal is closed", () => {
    // Render the always-sent modal fixture without opening it
    const { modal } = renderAlwaysSentModalFixture();
    initializeNotificationPreferences();

    // Press Escape
    const escape = pressKey("Escape");

    // The closed modal is unchanged and the key is left to other handlers
    expect(escape.defaultPrevented).to.equal(false);
    expect(modal.classList.contains("hidden")).to.equal(true);
  });
});

// Helpers.

/**
 * Dispatches a keydown event from the focused element.
 * @param {string} key Keyboard key.
 * @returns {KeyboardEvent} Dispatched event.
 */
const pressKey = (key) => {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key });
  (document.activeElement || document).dispatchEvent(event);
  return event;
};

/**
 * Renders the always-sent modal and its description trigger.
 * @returns {{modal: HTMLElement, opener: HTMLElement}} Fixture elements.
 */
const renderAlwaysSentModalFixture = () => {
  document.body.innerHTML = `
    <p>
      Emails about
      <button id="always-sent-opener" type="button" data-always-sent-modal-open>
        things that need your attention are always sent
      </button>.
    </p>
    <div id="always-sent-modal" class="hidden" role="dialog" aria-modal="true" aria-hidden="true">
      <div id="overlay-always-sent-modal" class="modal-overlay" data-always-sent-modal-close></div>
      <button id="close-always-sent-modal" type="button" data-always-sent-modal-close>Close modal</button>
      <ul><li>Account</li></ul>
      <button id="footer-close-always-sent-modal" type="button" data-always-sent-modal-close>Close</button>
    </div>
  `;

  return {
    modal: document.getElementById("always-sent-modal"),
    opener: document.getElementById("always-sent-opener"),
  };
};
