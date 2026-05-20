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
    // Build the DOM fixture to check it toggles active sections and notifies section.
    document.body.innerHTML = `
      <button data-section="details" data-active="true" class="active">Details</button>
      <button data-section="sessions" data-active="false">Sessions</button>
      <section data-content="details">Details content</section>
      <section data-content="sessions" class="hidden">Sessions content</section>
    `;

    // Prepare visited sections to check it toggles active sections and notifies section.
    const visitedSections = [];
    const { displayActiveSection } = initializeSectionTabs({
      onSectionChange: (sectionName) => visitedSections.push(sectionName),
    });

    // Exercise the flow to check it toggles active sections and notifies section hooks.
    displayActiveSection("sessions");

    // Read the section= element to check it toggles active sections and notifies section.
    const detailsButton = document.querySelector('[data-section="details"]');
    const sessionsButton = document.querySelector('[data-section="sessions"]');
    const detailsSection = document.querySelector('[data-content="details"]');
    const sessionsSection = document.querySelector('[data-content="sessions"]');

    // Confirm it toggles active sections and notifies section hooks.
    expect(detailsButton.getAttribute("data-active")).to.equal("false");
    expect(detailsButton.classList.contains("active")).to.equal(false);
    expect(sessionsButton.getAttribute("data-active")).to.equal("true");
    expect(sessionsButton.classList.contains("active")).to.equal(true);
    expect(detailsSection.classList.contains("hidden")).to.equal(true);
    expect(sessionsSection.classList.contains("hidden")).to.equal(false);
    expect(visitedSections).to.deep.equal(["sessions"]);
  });

  it("handles section buttons added after initialization", () => {
    // Build the DOM fixture to check it handles section buttons added.
    document.body.innerHTML = `
      <div id="page-root">
        <button data-section="details" data-active="true" class="active">Details</button>
        <section data-content="details">Details content</section>
      </div>
    `;

    // Read the page root element to check it handles section buttons added.
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

    // Trigger the user interaction to check it handles section buttons added.
    pageRoot.querySelector('[data-section="date-venue"] span').click();

    // Confirm it handles section buttons added after initialization.
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

  it("advances to the next section from bottom navigation", () => {
    // Build the DOM fixture to check it advances to the next section from bottom.
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

    // Read the page root element to check it advances to the next section from bottom.
    const pageRoot = document.getElementById("page-root");
    const nextButton = pageRoot.querySelector("[data-section-next]");
    const dateSection = pageRoot.querySelector('[data-content="date-venue"]');
    const cfsSection = pageRoot.querySelector('[data-content="cfs"]');
    const scrollOptions = [];
    const originalScrollTo = window.scrollTo;

    // Exercise the flow to check it advances to the next section from bottom navigation.
    window.scrollTo = (options) => scrollOptions.push(options);

    // Exercise the flow to check it advances to the next section from bottom navigation.
    try {
      initializeSectionTabs({ root: pageRoot });

      // Confirm it advances to the next section from bottom navigation.
      expect(nextButton.disabled).to.equal(false);
      nextButton.click();

      // Confirm it advances to the next section from bottom navigation.
      expect(
        pageRoot
          .querySelector('[data-section="date-venue"]')
          .getAttribute("data-active"),
      ).to.equal("true");
      expect(dateSection.classList.contains("hidden")).to.equal(false);
      expect(nextButton.classList.contains("hidden")).to.equal(false);
      expect(nextButton.disabled).to.equal(false);

      // Trigger the user interaction to check it advances to the next section.
      nextButton.click();

      // Confirm it advances to the next section from bottom navigation.
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
    // Build the DOM fixture to check it follows the current tab order when optional.
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

    // Read the page root element to check it follows the current tab order when optional.
    const pageRoot = document.getElementById("page-root");
    initializeSectionTabs({ root: pageRoot });

    // Trigger the user interaction to check it follows the current tab order.
    pageRoot.querySelector("[data-section-next]").click();

    // Confirm it follows the current tab order when optional sections exist.
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
    // Build the DOM fixture to check it hides bottom navigation when initialized.
    document.body.innerHTML = `
      <div id="page-root">
        <button data-section="details" data-active="false">Details</button>
        <button data-section="cfs" data-active="true" class="active">CFS</button>
        <section data-content="details" class="hidden">Details content</section>
        <section data-content="cfs">CFS content</section>
        <button data-section-next type="button">Next</button>
      </div>
    `;

    // Read the page root element to check it hides bottom navigation when initialized.
    const pageRoot = document.getElementById("page-root");
    const nextButton = pageRoot.querySelector("[data-section-next]");

    // Exercise the flow to check it hides bottom navigation when initialized.
    initializeSectionTabs({ root: pageRoot });

    // Confirm it hides bottom navigation when initialized on the final section.
    expect(nextButton.classList.contains("hidden")).to.equal(true);
    expect(nextButton.disabled).to.equal(true);
  });

  it("syncs checkbox toggles into hidden boolean inputs", () => {
    // Build the DOM fixture to check it syncs checkbox toggles into hidden boolean.
    document.body.innerHTML = `
      <input id="toggle_registration_required" type="checkbox" />
      <input id="registration_required" type="hidden" value="false" />
    `;

    // Read the toggle registration required element to check it syncs checkbox toggles.
    const toggle = document.getElementById("toggle_registration_required");
    const hiddenInput = document.getElementById("registration_required");
    const seenValues = [];

    // Exercise the flow to check it syncs checkbox toggles into hidden boolean inputs.
    bindBooleanToggle({
      toggle,
      hiddenInput,
      onChange: (enabled) => seenValues.push(enabled),
    });

    // Update the checkbox state to check it syncs checkbox toggles into hidden boolean.
    toggle.checked = true;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Confirm it syncs checkbox toggles into hidden boolean inputs.
    expect(hiddenInput.value).to.equal("true");
    expect(seenValues).to.deep.equal([true]);
  });

  it("collects only forms that exist in the current page root", () => {
    // Build the DOM fixture to check it collects only forms that exist in the current.
    document.body.innerHTML = `
      <form id="details-form"></form>
      <form id="sessions-form"></form>
      <div id="other-content"></div>
    `;

    // Confirm it collects only forms that exist in the current page root.
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
