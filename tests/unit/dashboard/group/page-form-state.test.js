import { expect } from "@open-wc/testing";

import {
  bindBooleanToggle,
  collectExistingFormIds,
  initializeSectionTabs,
} from "/static/js/dashboard/group/page-form-state.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("page form state helpers", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("toggles active sections and notifies section hooks", () => {
    // Render two tabs with the details section active by default.
    document.body.innerHTML = `
      <button data-section="details" data-active="true" class="active">Details</button>
      <button data-section="sessions" data-active="false">Sessions</button>
      <section data-content="details">Details content</section>
      <section data-content="sessions" class="hidden">Sessions content</section>
    `;

    // Track the section names reported by the tab helper.
    const visitedSections = [];
    const { displayActiveSection } = initializeSectionTabs({
      onSectionChange: (sectionName) => visitedSections.push(sectionName),
    });

    // Switch to the sessions section programmatically.
    displayActiveSection("sessions");

    // Read the tab and panel state after the section changes.
    const detailsButton = document.querySelector('[data-section="details"]');
    const sessionsButton = document.querySelector('[data-section="sessions"]');
    const detailsSection = document.querySelector('[data-content="details"]');
    const sessionsSection = document.querySelector('[data-content="sessions"]');

    // The selected tab, visible panel, and hook call all match the new section.
    expect(detailsButton.getAttribute("data-active")).to.equal("false");
    expect(detailsButton.classList.contains("active")).to.equal(false);
    expect(sessionsButton.getAttribute("data-active")).to.equal("true");
    expect(sessionsButton.classList.contains("active")).to.equal(true);
    expect(detailsSection.classList.contains("hidden")).to.equal(true);
    expect(sessionsSection.classList.contains("hidden")).to.equal(false);
    expect(visitedSections).to.deep.equal(["sessions"]);
  });

  it("handles section buttons added after initialization", () => {
    // Start with a single initialized section in the page root.
    document.body.innerHTML = `
      <div id="page-root">
        <button data-section="details" data-active="true" class="active">Details</button>
        <section data-content="details">Details content</section>
      </div>
    `;

    // Add another section after the click handler has already been registered.
    const pageRoot = document.getElementById("page-root");
    initializeSectionTabs({ root: pageRoot });
    pageRoot.insertAdjacentHTML(
      "beforeend",
      `
        <button data-section="date-venue" data-active="false">
          <span>Date & Venue</span>
        </button>
        <section data-content="date-venue" class="hidden">Date content</section>
      `,
    );

    // Click inside the new tab to exercise the delegated handler.
    pageRoot.querySelector('[data-section="date-venue"] span').click();

    // The dynamically-added tab becomes active and its panel is shown.
    expect(
      pageRoot
        .querySelector('[data-section="details"]')
        .getAttribute("data-active"),
    ).to.equal("false");
    expect(
      pageRoot
        .querySelector('[data-section="date-venue"]')
        .getAttribute("data-active"),
    ).to.equal("true");
    expect(
      pageRoot
        .querySelector('[data-content="details"]')
        .classList.contains("hidden"),
    ).to.equal(true);
    expect(
      pageRoot
        .querySelector('[data-content="date-venue"]')
        .classList.contains("hidden"),
    ).to.equal(false);
  });

  it("syncs section selects with active sections", () => {
    // Render compact select navigation beside the desktop tab buttons.
    document.body.innerHTML = `
      <div id="page-root">
        <select data-section-select>
          <option value="details" selected>Details</option>
          <option value="sessions">Sessions</option>
        </select>
        <button data-section="details" data-active="true" class="active">Details</button>
        <button data-section="sessions" data-active="false">Sessions</button>
        <section data-content="details">Details content</section>
        <section data-content="sessions" class="hidden">Sessions content</section>
      </div>
    `;

    // Initialize navigation against the page root.
    const pageRoot = document.getElementById("page-root");
    const sectionSelect = pageRoot.querySelector("[data-section-select]");
    const { displayActiveSection } = initializeSectionTabs({ root: pageRoot });

    // Change the compact navigation to the sessions section.
    sectionSelect.value = "sessions";
    sectionSelect.dispatchEvent(new Event("change", { bubbles: true }));

    // The matching tab state and content panel follow the select.
    expect(
      pageRoot
        .querySelector('[data-section="sessions"]')
        .getAttribute("data-active"),
    ).to.equal("true");
    expect(
      pageRoot
        .querySelector('[data-content="sessions"]')
        .classList.contains("hidden"),
    ).to.equal(false);

    // Programmatic tab changes keep the compact select in sync too.
    displayActiveSection("details");
    expect(sectionSelect.value).to.equal("details");
  });

  it("advances to the next section from bottom navigation", () => {
    // Render three ordered sections with bottom navigation.
    document.body.innerHTML = `
      <div id="page-root">
        <button data-section="details" data-active="true" class="active">Details</button>
        <button data-section="date-venue" data-active="false">Date & Venue</button>
        <button data-section="cfs" data-active="false">CFS</button>
        <section data-content="details">Details content</section>
        <section data-content="date-venue" class="hidden">Date content</section>
        <section data-content="cfs" class="hidden">CFS content</section>
        <button data-section-next type="button">Next</button>
      </div>
    `;

    // Capture the navigation button, destination sections, and scroll calls.
    const pageRoot = document.getElementById("page-root");
    const nextButton = pageRoot.querySelector("[data-section-next]");
    const dateSection = pageRoot.querySelector('[data-content="date-venue"]');
    const cfsSection = pageRoot.querySelector('[data-content="cfs"]');
    const scrollOptions = [];
    const originalScrollTo = window.scrollTo;

    // Replace scrolling so the test can assert when the page would move upward.
    window.scrollTo = (options) => scrollOptions.push(options);

    // Initialize section tabs while scroll is mocked.
    try {
      initializeSectionTabs({ root: pageRoot });

      // The first click moves from details to date and venue.
      expect(nextButton.disabled).to.equal(false);
      nextButton.click();

      // Bottom navigation remains available while another section follows.
      expect(
        pageRoot
          .querySelector('[data-section="date-venue"]')
          .getAttribute("data-active"),
      ).to.equal("true");
      expect(dateSection.classList.contains("hidden")).to.equal(false);
      expect(nextButton.classList.contains("hidden")).to.equal(false);
      expect(nextButton.disabled).to.equal(false);

      // The second click moves to the final section.
      nextButton.click();

      // The final section hides bottom navigation and records both scrolls.
      expect(
        pageRoot
          .querySelector('[data-section="cfs"]')
          .getAttribute("data-active"),
      ).to.equal("true");
      expect(cfsSection.classList.contains("hidden")).to.equal(false);
      expect(nextButton.classList.contains("hidden")).to.equal(true);
      expect(nextButton.disabled).to.equal(true);
      expect(scrollOptions).to.deep.equal([
        { behavior: "instant", left: 0, top: 0 },
        { behavior: "instant", left: 0, top: 0 },
      ]);
    } finally {
      window.scrollTo = originalScrollTo;
    }
  });

  it("follows the current tab order when optional sections exist", () => {
    // Render optional sections around the current sessions tab.
    document.body.innerHTML = `
      <div id="page-root">
        <button data-section="details" data-active="false">Details</button>
        <button data-section="sessions" data-active="true" class="active">Sessions</button>
        <button data-section="payments" data-active="false">Payments</button>
        <button data-section="cfs" data-active="false">CFS</button>
        <section data-content="details" class="hidden">Details content</section>
        <section data-content="sessions">Sessions content</section>
        <section data-content="payments" class="hidden">Payments content</section>
        <section data-content="cfs" class="hidden">CFS content</section>
        <button data-section-next type="button">Next</button>
      </div>
    `;

    // Initialize the helper from the sessions tab.
    const pageRoot = document.getElementById("page-root");
    initializeSectionTabs({ root: pageRoot });

    // Move forward using the next button.
    pageRoot.querySelector("[data-section-next]").click();

    // The next visible tab in the DOM order becomes active.
    expect(
      pageRoot
        .querySelector('[data-section="payments"]')
        .getAttribute("data-active"),
    ).to.equal("true");
    expect(
      pageRoot
        .querySelector('[data-content="payments"]')
        .classList.contains("hidden"),
    ).to.equal(false);
  });

  it("hides bottom navigation when initialized on the final section", () => {
    // Render the final section as the active tab from the start.
    document.body.innerHTML = `
      <div id="page-root">
        <button data-section="details" data-active="false">Details</button>
        <button data-section="cfs" data-active="true" class="active">CFS</button>
        <section data-content="details" class="hidden">Details content</section>
        <section data-content="cfs">CFS content</section>
        <button data-section-next type="button">Next</button>
      </div>
    `;

    // Keep a reference to the next button before initializing the helper.
    const pageRoot = document.getElementById("page-root");
    const nextButton = pageRoot.querySelector("[data-section-next]");

    // Initialize tab behavior with the last section already active.
    initializeSectionTabs({ root: pageRoot });

    // Bottom navigation is hidden because there is nowhere else to advance.
    expect(nextButton.classList.contains("hidden")).to.equal(true);
    expect(nextButton.disabled).to.equal(true);
  });

  it("binds section tab clicks once per page root", () => {
    // Render a page root with two sections.
    document.body.innerHTML = `
      <div id="page-root">
        <button data-section="details" data-active="true" class="active">Details</button>
        <button data-section="sessions" data-active="false">Sessions</button>
        <section data-content="details">Details content</section>
        <section data-content="sessions" class="hidden">Sessions content</section>
      </div>
    `;

    // Initialize the same root twice with separate section hooks.
    const pageRoot = document.getElementById("page-root");
    const visitedSections = [];
    initializeSectionTabs({
      root: pageRoot,
      onSectionChange: (sectionName) => visitedSections.push(sectionName),
    });
    initializeSectionTabs({
      root: pageRoot,
      onSectionChange: (sectionName) =>
        visitedSections.push(`again:${sectionName}`),
    });

    // Click the sessions tab after duplicate initialization.
    pageRoot.querySelector('[data-section="sessions"]').click();

    // Only the first delegated click handler is bound to the page root.
    expect(visitedSections).to.deep.equal(["sessions"]);
  });

  it("syncs checkbox toggles into hidden boolean inputs", () => {
    // Render the visible checkbox and the hidden field submitted with the form.
    document.body.innerHTML = `
      <input id="toggle_registration_required" type="checkbox" />
      <input id="registration_required" type="hidden" value="false" />
    `;

    // Track the hidden input and callback values after binding the toggle.
    const toggle = document.getElementById("toggle_registration_required");
    const hiddenInput = document.getElementById("registration_required");
    const seenValues = [];

    // Wire the visible checkbox to the hidden boolean input.
    bindBooleanToggle({
      toggle,
      hiddenInput,
      onChange: (enabled) => seenValues.push(enabled),
    });

    // Turn the checkbox on and emit the same change event the browser would send.
    toggle.checked = true;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // The hidden field and change callback both receive the enabled state.
    expect(hiddenInput.value).to.equal("true");
    expect(seenValues).to.deep.equal([true]);
  });

  it("binds boolean toggle changes once per checkbox", () => {
    // Render the visible checkbox and hidden field.
    document.body.innerHTML = `
      <input id="toggle_registration_required" type="checkbox" />
      <input id="registration_required" type="hidden" value="false" />
    `;

    // Bind the same toggle twice with separate callbacks.
    const toggle = document.getElementById("toggle_registration_required");
    const hiddenInput = document.getElementById("registration_required");
    const seenValues = [];
    bindBooleanToggle({
      toggle,
      hiddenInput,
      onChange: (enabled) => seenValues.push(enabled),
    });
    bindBooleanToggle({
      toggle,
      hiddenInput,
      onChange: (enabled) => seenValues.push(`again:${enabled}`),
    });

    // Turn the checkbox on and emit the browser change event.
    toggle.checked = true;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Only the first listener runs for duplicate bindings on the same checkbox.
    expect(hiddenInput.value).to.equal("true");
    expect(seenValues).to.deep.equal([true]);
  });

  it("collects only forms that exist in the current page root", () => {
    // Render only the forms that are present on this page variant.
    document.body.innerHTML = `
      <form id="details-form"></form>
      <form id="sessions-form"></form>
      <div id="other-content"></div>
    `;

    // Missing optional form ids are skipped.
    expect(
      collectExistingFormIds([
        "details-form",
        "payments-form",
        "sessions-form",
        "cfs-form",
      ]),
    ).to.deep.equal(["details-form", "sessions-form"]);
  });
});
