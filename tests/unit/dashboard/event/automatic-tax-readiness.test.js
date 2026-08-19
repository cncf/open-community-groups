import { expect } from "@open-wc/testing";

import { initializeAutomaticTaxReadiness } from "/static/js/dashboard/event/automatic-tax-readiness.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

const readinessResponse = (body, { ok = true, status = 200 } = {}) => ({
  headers: new Headers(),
  json: async () => body,
  ok,
  status,
});

const mountReadiness = ({ saved = true } = {}) => {
  document.body.innerHTML = `
    <main data-event-page="update">
      <select name="tax_calculation_mode">
        <option value="automatic" selected>Automatic</option>
        <option value="manual">Manual</option>
      </select>
      <input name="venue_address" value="123 Example Street">
      <location-search-field></location-search-field>
      ${saved ? '<button type="button" data-automatic-tax-readiness-action="check">Check readiness</button>' : ""}
      <section
        class="${saved ? "hidden" : ""}"
        data-automatic-tax-readiness
        data-saved="${saved}"
        ${saved ? 'data-readiness-url="/dashboard/group/events/event-id/automatic-tax/readiness"' : ""}
      >
        ${saved ? '<button type="button" data-automatic-tax-readiness-action="review-state" hidden>Review State code</button>' : ""}
        <p data-automatic-tax-readiness-role="status" role="status" aria-live="polite">
          ${saved ? "" : "Save the event before checking readiness."}
        </p>
        ${saved ? '<a href="/docs#/guides/event-operations?id=tickets-discounts-and-refunds" data-automatic-tax-readiness-role="manual-tax-help" hidden>Learn how to configure manual tax</a>' : ""}
      </section>
    </main>
  `;

  const locationField = document.querySelector("location-search-field");
  const shadowRoot = locationField.attachShadow({ mode: "open" });
  shadowRoot.innerHTML = '<input name="venue_state_code">';

  return {
    check: document.querySelector('[data-automatic-tax-readiness-action="check"]'),
    locationField,
    manualTaxHelp: document.querySelector('[data-automatic-tax-readiness-role="manual-tax-help"]'),
    mode: document.querySelector('[name="tax_calculation_mode"]'),
    panel: document.querySelector("[data-automatic-tax-readiness]"),
    review: document.querySelector('[data-automatic-tax-readiness-action="review-state"]'),
    stateCode: shadowRoot.querySelector('[name="venue_state_code"]'),
    status: document.querySelector('[data-automatic-tax-readiness-role="status"]'),
  };
};

describe("automatic tax readiness", () => {
  let fetchMock;

  beforeEach(() => resetDom());

  afterEach(() => {
    fetchMock?.restore();
    fetchMock = null;
    resetDom();
  });

  it("checks persisted data and announces ready cache responses", async () => {
    const controls = mountReadiness();
    fetchMock = mockFetch({
      response: readinessResponse({ cached: true, state_code: "MA", status: "ready" }),
    });
    initializeAutomaticTaxReadiness({ pageRoot: document.body, displayActiveSection: () => {} });

    controls.check.click();
    expect(controls.check.textContent).to.equal("Check readiness");
    expect(controls.panel.classList.contains("border-stone-300")).to.equal(true);
    expect(controls.panel.classList.contains("bg-stone-50")).to.equal(true);
    expect(controls.panel.classList.contains("text-stone-700")).to.equal(true);
    await waitForMicrotask();

    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][1].method).to.equal("POST");
    expect(controls.status.getAttribute("aria-live")).to.equal("polite");
    expect(controls.status.textContent).to.include("state code MA");
    expect(controls.status.textContent).to.include("reused");
    expect(controls.check.disabled).to.equal(false);
    expect(controls.check.textContent).to.equal("Check readiness");
    expect(controls.panel.classList.contains("hidden")).to.equal(false);
    expect(controls.panel.classList.contains("border-green-800")).to.equal(true);
    expect(controls.panel.classList.contains("bg-green-100")).to.equal(true);
  });

  it("marks readiness stale after a relevant unsaved change", async () => {
    const controls = mountReadiness();
    fetchMock = mockFetch({
      response: readinessResponse({ cached: false, state_code: null, status: "ready" }),
    });
    initializeAutomaticTaxReadiness({ pageRoot: document.body, displayActiveSection: () => {} });

    document.querySelector('[name="venue_address"]').dispatchEvent(
      new Event("input", { bubbles: true, composed: true }),
    );
    controls.check.click();
    await waitForMicrotask();

    expect(controls.check.disabled).to.equal(true);
    expect(controls.check.textContent).to.equal("Check readiness");
    expect(controls.status.textContent).to.include("Save these changes");
    expect(fetchMock.calls).to.have.length(0);
  });

  it("opens Location and focuses State code for exact state failures", async () => {
    const controls = mountReadiness();
    const displayedSections = [];
    fetchMock = mockFetch({
      response: readinessResponse(
        {
          code: "state_code_invalid",
          fields: ["venue_state_code"],
          message: "The state code ZZ is invalid for ES.",
          status: "not_ready",
        },
        { ok: false, status: 422 },
      ),
    });
    initializeAutomaticTaxReadiness({
      pageRoot: document.body,
      displayActiveSection: (section) => displayedSections.push(section),
    });

    controls.check.click();
    await waitForMicrotask();
    expect(controls.review.hidden).to.equal(false);
    expect(controls.check.textContent).to.equal("Check readiness");
    expect(controls.status.textContent).to.equal("The state code ZZ is invalid for ES.");

    controls.review.click();
    await waitForMicrotask();
    expect(displayedSections).to.deep.equal(["date-venue"]);
    expect(controls.locationField.shadowRoot.activeElement).to.equal(controls.stateCode);
  });

  it("offers manual-tax guidance for unsupported venue countries", async () => {
    const controls = mountReadiness();
    fetchMock = mockFetch({
      response: readinessResponse(
        {
          code: "unsupported_country",
          fields: ["venue_country_code"],
          message:
            "Stripe automatic tax is not supported for this venue country. Select Manual Stripe Tax Rates instead.",
          status: "not_ready",
        },
        { ok: false, status: 422 },
      ),
    });
    initializeAutomaticTaxReadiness({ pageRoot: document.body, displayActiveSection: () => {} });

    controls.check.click();
    await waitForMicrotask();

    expect(controls.status.textContent).to.include("Select Manual Stripe Tax Rates instead");
    expect(controls.manualTaxHelp.hidden).to.equal(false);
    expect(controls.manualTaxHelp.getAttribute("href")).to.equal(
      "/docs#/guides/event-operations?id=tickets-discounts-and-refunds",
    );
    expect(controls.review.hidden).to.equal(true);
  });

  it("uses warning feedback when readiness cannot be confirmed", async () => {
    const controls = mountReadiness();
    fetchMock = mockFetch({
      impl: async () => {
        throw new Error("Provider unavailable");
      },
    });
    initializeAutomaticTaxReadiness({ pageRoot: document.body, displayActiveSection: () => {} });

    controls.check.click();
    await waitForMicrotask();

    expect(controls.status.textContent).to.equal(
      "Automatic tax readiness could not be confirmed. Try again later.",
    );
    expect(controls.panel.classList.contains("border-amber-600")).to.equal(true);
    expect(controls.panel.classList.contains("bg-amber-50")).to.equal(true);
    expect(controls.panel.classList.contains("text-amber-900")).to.equal(true);
    expect(controls.check.disabled).to.equal(false);
  });

  it("hides the control outside automatic mode and keeps add-page guidance", () => {
    const controls = mountReadiness({ saved: false });
    initializeAutomaticTaxReadiness({ pageRoot: document.body, displayActiveSection: () => {} });

    expect(controls.status.textContent).to.include("Save the event");
    expect(controls.check).to.equal(null);
    controls.mode.value = "manual";
    controls.mode.dispatchEvent(new Event("change", { bubbles: true }));
    expect(controls.panel.classList.contains("hidden")).to.equal(true);
  });
});
