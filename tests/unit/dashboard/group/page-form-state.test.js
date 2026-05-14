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
    document.body.innerHTML = `
      <button data-section="details" data-active="true" class="active">Details</button>
      <button data-section="sessions" data-active="false">Sessions</button>
      <section data-content="details">Details content</section>
      <section data-content="sessions" class="hidden">Sessions content</section>
    `;

    const visitedSections = [];
    const { displayActiveSection } = initializeSectionTabs({
      onSectionChange: (sectionName) => visitedSections.push(sectionName),
    });

    displayActiveSection("sessions");

    const detailsButton = document.querySelector('[data-section="details"]');
    const sessionsButton = document.querySelector('[data-section="sessions"]');
    const detailsSection = document.querySelector('[data-content="details"]');
    const sessionsSection = document.querySelector('[data-content="sessions"]');

    expect(detailsButton.getAttribute("data-active")).to.equal("false");
    expect(detailsButton.classList.contains("active")).to.equal(false);
    expect(sessionsButton.getAttribute("data-active")).to.equal("true");
    expect(sessionsButton.classList.contains("active")).to.equal(true);
    expect(detailsSection.classList.contains("hidden")).to.equal(true);
    expect(sessionsSection.classList.contains("hidden")).to.equal(false);
    expect(visitedSections).to.deep.equal(["sessions"]);
  });

  it("handles section buttons added after initialization", () => {
    document.body.innerHTML = `
      <div id="page-root">
        <button data-section="details" data-active="true" class="active">Details</button>
        <section data-content="details">Details content</section>
      </div>
    `;

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

    pageRoot.querySelector('[data-section="date-venue"] span').click();

    expect(pageRoot.querySelector('[data-section="details"]').getAttribute("data-active")).to.equal(
      "false",
    );
    expect(pageRoot.querySelector('[data-section="date-venue"]').getAttribute("data-active")).to.equal(
      "true",
    );
    expect(pageRoot.querySelector('[data-content="details"]').classList.contains("hidden")).to.equal(
      true,
    );
    expect(pageRoot.querySelector('[data-content="date-venue"]').classList.contains("hidden")).to.equal(
      false,
    );
  });

  it("advances to the next section from bottom navigation", () => {
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

    const pageRoot = document.getElementById("page-root");
    const nextButton = pageRoot.querySelector("[data-section-next]");
    const dateSection = pageRoot.querySelector('[data-content="date-venue"]');
    const cfsSection = pageRoot.querySelector('[data-content="cfs"]');
    const scrollOptions = [];
    const originalScrollTo = window.scrollTo;

    window.scrollTo = (options) => scrollOptions.push(options);

    try {
      initializeSectionTabs({ root: pageRoot });

      expect(nextButton.disabled).to.equal(false);
      nextButton.click();

      expect(pageRoot.querySelector('[data-section="date-venue"]').getAttribute("data-active")).to.equal(
        "true",
      );
      expect(dateSection.classList.contains("hidden")).to.equal(false);
      expect(nextButton.classList.contains("hidden")).to.equal(false);
      expect(nextButton.disabled).to.equal(false);

      nextButton.click();

      expect(pageRoot.querySelector('[data-section="cfs"]').getAttribute("data-active")).to.equal("true");
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

    const pageRoot = document.getElementById("page-root");
    initializeSectionTabs({ root: pageRoot });

    pageRoot.querySelector("[data-section-next]").click();

    expect(pageRoot.querySelector('[data-section="payments"]').getAttribute("data-active")).to.equal(
      "true",
    );
    expect(pageRoot.querySelector('[data-content="payments"]').classList.contains("hidden")).to.equal(
      false,
    );
  });

  it("hides bottom navigation when initialized on the final section", () => {
    document.body.innerHTML = `
      <div id="page-root">
        <button data-section="details" data-active="false">Details</button>
        <button data-section="cfs" data-active="true" class="active">CFS</button>
        <section data-content="details" class="hidden">Details content</section>
        <section data-content="cfs">CFS content</section>
        <button data-section-next type="button">Next</button>
      </div>
    `;

    const pageRoot = document.getElementById("page-root");
    const nextButton = pageRoot.querySelector("[data-section-next]");

    initializeSectionTabs({ root: pageRoot });

    expect(nextButton.classList.contains("hidden")).to.equal(true);
    expect(nextButton.disabled).to.equal(true);
  });

  it("syncs checkbox toggles into hidden boolean inputs", () => {
    document.body.innerHTML = `
      <input id="toggle_registration_required" type="checkbox" />
      <input id="registration_required" type="hidden" value="false" />
    `;

    const toggle = document.getElementById("toggle_registration_required");
    const hiddenInput = document.getElementById("registration_required");
    const seenValues = [];

    bindBooleanToggle({
      toggle,
      hiddenInput,
      onChange: (enabled) => seenValues.push(enabled),
    });

    toggle.checked = true;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    expect(hiddenInput.value).to.equal("true");
    expect(seenValues).to.deep.equal([true]);
  });

  it("collects only forms that exist in the current page root", () => {
    document.body.innerHTML = `
      <form id="details-form"></form>
      <form id="sessions-form"></form>
      <div id="other-content"></div>
    `;

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
