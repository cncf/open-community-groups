import { expect } from "@open-wc/testing";

import { initializeManualTaxRates } from "/static/js/dashboard/event/manual-tax-rates.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

const rateResponse = (rates, { ok = true, status = 200 } = {}) => ({
  ok,
  status,
  json: async () => rates,
});

const mountControls = ({
  disabled = false,
  mode = "automatic",
  selectedRateIds = [],
} = {}) => {
  document.body.innerHTML = `
    <form id="event-form">
      <div data-tax-control="behavior">
        <select id="tax_behavior">
          <option value="inclusive">Inclusive</option>
          <option value="exclusive">Exclusive</option>
        </select>
      </div>
      <select id="tax_calculation_mode">
        <option value="automatic">Automatic</option>
        <option value="manual">Manual rates</option>
        <option value="none">No tax</option>
      </select>
      <div
        id="manual-tax-rates-fieldset"
        data-disabled="${disabled}"
        data-selected-rate-ids='${JSON.stringify(selectedRateIds)}'
        data-tax-rates-url="/dashboard/group/events/tax-rates"
        hidden
      >
        <p data-tax-rates-role="state" aria-live="polite" hidden></p>
        <select
          name="manual_tax_rate_ids[]"
          data-tax-rates-role="select"
        ></select>
        <button data-tax-rates-action="retry" type="button" hidden>
          <span data-tax-rates-role="retry-label">Retry</span>
          <span data-tax-rates-role="retry-loading" hidden>
            <svg-spinner size="size-4" label="Loading Stripe Tax Rates"></svg-spinner>
          </span>
        </button>
      </div>
      <ticket-types-editor id="ticket-types-ui"></ticket-types-editor>
    </form>
  `;
  document.getElementById("tax_calculation_mode").value = mode;

  return {
    behavior: document.getElementById("tax_behavior"),
    behaviorWrapper: document.querySelector('[data-tax-control="behavior"]'),
    fieldset: document.getElementById("manual-tax-rates-fieldset"),
    form: document.getElementById("event-form"),
    mode: document.getElementById("tax_calculation_mode"),
    retry: document.querySelector('[data-tax-rates-action="retry"]'),
    select: document.querySelector('[data-tax-rates-role="select"]'),
    state: document.querySelector('[data-tax-rates-role="state"]'),
    ticketTypes: document.getElementById("ticket-types-ui"),
  };
};

describe("manual Stripe Tax Rates", () => {
  let fetchMock;

  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    fetchMock?.restore();
    fetchMock = null;
    resetDom();
  });

  it("does not mark read-only selections as submitted", async () => {
    const controls = mountControls({
      disabled: true,
      mode: "manual",
      selectedRateIds: ["txr_state"],
    });
    fetchMock = mockFetch({
      response: rateResponse([
        {
          display_name: "State sales tax",
          id: "txr_state",
          inclusive: true,
          jurisdiction: "California",
          percentage: "8.875",
        },
      ]),
    });
    initializeManualTaxRates(document);
    await waitForMicrotask();

    const formData = new FormData(controls.form);
    expect(formData.get("manual_tax_rate_ids_present")).to.equal(null);
    expect(formData.getAll("manual_tax_rate_ids[]")).to.deep.equal([
      "txr_state",
    ]);
    expect(controls.select.disabled).to.equal(true);
    expect(controls.select.value).to.equal("txr_state");
    expect(controls.state.hidden).to.equal(false);
    expect(controls.state.classList.contains("text-stone-600")).to.equal(true);
    expect(controls.state.textContent).to.equal(
      "Manual Tax Rate selection is currently read-only.",
    );
  });

  it("lazy-loads compatible account rates when manual mode is selected", async () => {
    const controls = mountControls();
    fetchMock = mockFetch({
      response: rateResponse([
        {
          display_name: "State sales tax",
          id: "txr_state",
          inclusive: true,
          jurisdiction: "California",
          percentage: "8.875",
        },
      ]),
    });
    initializeManualTaxRates(document);

    expect(fetchMock.calls).to.have.length(0);
    controls.mode.value = "manual";
    controls.mode.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    expect(fetchMock.calls).to.have.length(1);
    expect(String(fetchMock.calls[0][0])).to.include("tax_behavior=inclusive");
    expect(fetchMock.calls[0][1].headers.get("X-OCG-Fetch")).to.equal("true");
    expect(controls.fieldset.hidden).to.equal(false);
    expect(controls.select.querySelector('option[value="txr_state"]')).to.exist;
    expect(controls.select.multiple).to.equal(false);
    expect(controls.select.disabled).to.equal(false);
    expect(controls.select.textContent).to.include("State sales tax — 8.875%");
    expect(controls.select.textContent).to.include(
      "Tax included in the ticket price",
    );
    expect(controls.state.hidden).to.equal(true);
    expect(controls.state.textContent).to.equal("");
  });

  it("reloads for behavior changes and clears incompatible selections", async () => {
    const controls = mountControls({
      mode: "manual",
      selectedRateIds: ["txr_inclusive"],
    });
    fetchMock = mockFetch({
      impl: async (url) =>
        String(url).includes("tax_behavior=exclusive")
          ? rateResponse([
              {
                display_name: "Exclusive rate",
                id: "txr_exclusive",
                inclusive: false,
                jurisdiction: null,
                percentage: "5",
              },
            ])
          : rateResponse([
              {
                display_name: "Inclusive rate",
                id: "txr_inclusive",
                inclusive: true,
                jurisdiction: "Oregon",
                percentage: "1",
              },
            ]),
    });
    initializeManualTaxRates(document);
    await waitForMicrotask();

    expect(
      controls.select.querySelector('option[value="txr_inclusive"]').selected,
    ).to.equal(true);
    controls.behavior.value = "exclusive";
    controls.behavior.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    expect(fetchMock.calls).to.have.length(2);
    expect(
      controls.select.querySelector('option[value="txr_exclusive"]').selected,
    ).to.equal(false);
    expect(
      controls.fieldset.querySelectorAll(
        'input[type="hidden"][name="manual_tax_rate_ids[]"]',
      ),
    ).to.have.length(0);
  });

  it("keeps only the first configured rate in the standard selector", async () => {
    const controls = mountControls({
      mode: "manual",
      selectedRateIds: ["txr_state", "txr_local"],
    });
    fetchMock = mockFetch({
      response: rateResponse([
        {
          display_name: "State sales tax",
          id: "txr_state",
          inclusive: true,
          jurisdiction: "California",
          percentage: "8.875",
        },
        {
          display_name: "Local sales tax",
          id: "txr_local",
          inclusive: true,
          jurisdiction: "San Francisco",
          percentage: "1",
        },
      ]),
    });
    initializeManualTaxRates(document);
    await waitForMicrotask();

    const formData = new FormData(controls.form);
    expect(controls.select.value).to.equal("txr_state");
    expect(formData.getAll("manual_tax_rate_ids[]")).to.deep.equal([
      "txr_state",
    ]);
  });

  it("keeps invalid state inline and operational states in the selector", async () => {
    const controls = mountControls({
      mode: "manual",
      selectedRateIds: ["txr_missing"],
    });
    fetchMock = mockFetch({
      response: rateResponse([
        {
          display_name: "State sales tax",
          id: "txr_state",
          inclusive: true,
          jurisdiction: "California",
          percentage: "8.875",
        },
      ]),
    });
    initializeManualTaxRates(document);
    await waitForMicrotask();

    expect(controls.state.hidden).to.equal(false);
    expect(controls.state.textContent).to.include(
      "previously selected Tax Rate",
    );
    expect(controls.state.classList.contains("text-red-700")).to.equal(true);

    controls.select.value = "txr_state";
    controls.select.dispatchEvent(new Event("change", { bubbles: true }));

    expect(controls.state.hidden).to.equal(true);
    expect(controls.state.textContent).to.equal("");

    fetchMock.setImpl(async () => rateResponse([], { ok: false, status: 503 }));
    controls.behavior.value = "exclusive";
    controls.behavior.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    expect(controls.state.hidden).to.equal(true);
    expect(controls.state.textContent).to.equal("");
    expect(controls.retry.hidden).to.equal(false);
    expect(controls.retry.title).to.equal(
      "Retry the request before saving paid manual-tax tickets.",
    );
    expect(controls.select.disabled).to.equal(true);
    expect(controls.select.textContent).to.equal(
      "Stripe Tax Rates are unavailable right now.",
    );

    fetchMock.setImpl(async () => rateResponse([]));
    controls.fieldset.dispatchEvent(
      new CustomEvent("tax-rate-selection-updated", {
        detail: { rateIds: [] },
      }),
    );
    await waitForMicrotask();

    expect(controls.state.hidden).to.equal(true);
    expect(controls.state.textContent).to.equal("");
    expect(controls.select.textContent).to.include(
      "No active exclusive Tax Rates",
    );
    expect(controls.select.textContent).not.to.include("Create rates in");
  });

  it("shows spinner-only button loading for an explicit retry", async () => {
    const controls = mountControls({ mode: "manual" });
    fetchMock = mockFetch({
      response: rateResponse([], { ok: false, status: 503 }),
    });
    initializeManualTaxRates(document);
    await waitForMicrotask();

    let resolveRetry;
    fetchMock.setImpl(
      () =>
        new Promise((resolve) => {
          resolveRetry = resolve;
        }),
    );
    controls.retry.click();

    expect(controls.retry.disabled).to.equal(true);
    expect(controls.retry.hasAttribute("aria-busy")).to.equal(true);
    expect(
      controls.retry.querySelector('[data-tax-rates-role="retry-label"]')
        .hidden,
    ).to.equal(true);
    expect(
      controls.retry.querySelector('[data-tax-rates-role="retry-loading"]')
        .hidden,
    ).to.equal(false);
    expect(
      Array.from(
        controls.retry.querySelector('[data-tax-rates-role="retry-loading"]')
          .children,
        (element) => element.tagName,
      ),
    ).to.deep.equal(["SVG-SPINNER"]);

    resolveRetry(
      rateResponse([
        {
          display_name: "State sales tax",
          id: "txr_state",
          inclusive: true,
          jurisdiction: "California",
          percentage: "8.875",
        },
      ]),
    );
    await waitForMicrotask();

    expect(controls.retry.disabled).to.equal(false);
    expect(controls.retry.hasAttribute("aria-busy")).to.equal(false);
    expect(controls.state.hidden).to.equal(true);
    expect(controls.state.textContent).to.equal("");
  });

  it("requires a selection and disables tax display for no-tax mode", async () => {
    const controls = mountControls({ mode: "manual" });
    controls.ticketTypes.hasConfiguredPositivePrices = () => true;
    fetchMock = mockFetch({ response: rateResponse([]) });
    initializeManualTaxRates(document);
    await waitForMicrotask();

    expect(controls.mode.validationMessage).to.include("Select an available");

    controls.behavior.value = "exclusive";
    controls.mode.value = "none";
    controls.mode.dispatchEvent(new Event("change", { bubbles: true }));

    expect(controls.behavior.value).to.equal("exclusive");
    expect(controls.behavior.disabled).to.equal(true);
    expect(controls.behaviorWrapper.classList.contains("hidden")).to.equal(
      false,
    );
    expect(controls.fieldset.hidden).to.equal(true);
    expect(controls.mode.validationMessage).to.equal("");
    expect(controls.select.children).to.have.length(0);
  });

  it("submits a presence marker when the editable rate is cleared", async () => {
    const controls = mountControls({
      mode: "manual",
      selectedRateIds: ["txr_state"],
    });
    fetchMock = mockFetch({
      response: rateResponse([
        {
          display_name: "State sales tax",
          id: "txr_state",
          inclusive: true,
          jurisdiction: "California",
          percentage: "8.875",
        },
      ]),
    });
    initializeManualTaxRates(document);
    await waitForMicrotask();

    controls.select.value = "";
    controls.select.dispatchEvent(new Event("change", { bubbles: true }));
    const formData = new FormData(controls.form);

    expect(formData.get("manual_tax_rate_ids_present")).to.equal("true");
    expect(formData.getAll("manual_tax_rate_ids[]")).to.deep.equal([]);
  });
});
