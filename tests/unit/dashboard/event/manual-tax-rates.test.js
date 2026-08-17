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

const mountControls = ({ disabled = false, mode = "automatic", selectedRateIds = [] } = {}) => {
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
      <fieldset
        id="manual-tax-rates-fieldset"
        data-disabled="${disabled}"
        data-selected-rate-ids='${JSON.stringify(selectedRateIds)}'
        data-tax-rates-url="/dashboard/group/events/tax-rates"
        hidden
      >
        <p data-tax-rates-role="state" aria-live="polite"></p>
        <div data-tax-rates-role="list"></div>
        <button data-tax-rates-action="retry" type="button" hidden>Retry</button>
      </fieldset>
      <ticket-types-editor id="ticket-types-ui"></ticket-types-editor>
    </form>
  `;
  document.getElementById("tax_calculation_mode").value = mode;

  return {
    behavior: document.getElementById("tax_behavior"),
    behaviorWrapper: document.querySelector('[data-tax-control="behavior"]'),
    fieldset: document.getElementById("manual-tax-rates-fieldset"),
    form: document.getElementById("event-form"),
    list: document.querySelector('[data-tax-rates-role="list"]'),
    mode: document.getElementById("tax_calculation_mode"),
    retry: document.querySelector('[data-tax-rates-action="retry"]'),
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
    expect(formData.getAll("manual_tax_rate_ids[]")).to.deep.equal(["txr_state"]);
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
    expect(controls.fieldset.hidden).to.equal(false);
    expect(controls.list.querySelector('input[value="txr_state"]')).to.exist;
    expect(controls.list.textContent).to.include("State sales tax — 8.875%");
    expect(controls.list.textContent).to.include("Tax included in the ticket price");
    expect(controls.state.textContent).to.equal("1 active inclusive Stripe Tax Rate available.");
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

    expect(controls.list.querySelector('input[value="txr_inclusive"]').checked).to.equal(true);
    controls.behavior.value = "exclusive";
    controls.behavior.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    expect(fetchMock.calls).to.have.length(2);
    expect(controls.list.querySelector('input[value="txr_exclusive"]').checked).to.equal(false);
    expect(
      controls.fieldset.querySelectorAll('input[type="hidden"][name="manual_tax_rate_ids[]"]'),
    ).to.have.length(0);
  });

  it("reports empty, unavailable, and retryable error states", async () => {
    const controls = mountControls({
      mode: "manual",
      selectedRateIds: ["txr_missing"],
    });
    fetchMock = mockFetch({ response: rateResponse([]) });
    initializeManualTaxRates(document);
    await waitForMicrotask();

    expect(controls.state.textContent).to.include("previously selected Tax Rates");
    expect(controls.state.classList.contains("text-red-700")).to.equal(true);

    fetchMock.setImpl(async () => rateResponse([], { ok: false, status: 503 }));
    controls.retry.click();
    await waitForMicrotask();

    expect(controls.state.textContent).to.include("unavailable right now");
    expect(controls.retry.hidden).to.equal(false);

    fetchMock.setImpl(async () => rateResponse([]));
    controls.fieldset.dispatchEvent(
      new CustomEvent("tax-rate-selection-updated", {
        detail: { rateIds: [] },
      }),
    );
    await waitForMicrotask();

    expect(controls.state.textContent).to.include("No active inclusive Tax Rates");
    expect(controls.state.textContent).to.include("fiscal sponsor's Stripe account");
  });

  it("requires a selection for paid manual tickets and normalizes no-tax mode", async () => {
    const controls = mountControls({ mode: "manual" });
    controls.ticketTypes.hasConfiguredPositivePrices = () => true;
    fetchMock = mockFetch({ response: rateResponse([]) });
    initializeManualTaxRates(document);
    await waitForMicrotask();

    expect(controls.mode.validationMessage).to.include("Select at least one");

    controls.behavior.value = "exclusive";
    controls.mode.value = "none";
    controls.mode.dispatchEvent(new Event("change", { bubbles: true }));

    expect(controls.behavior.value).to.equal("inclusive");
    expect(controls.behavior.disabled).to.equal(true);
    expect(controls.behaviorWrapper.classList.contains("hidden")).to.equal(true);
    expect(controls.fieldset.hidden).to.equal(true);
    expect(controls.mode.validationMessage).to.equal("");
    expect(controls.list.children).to.have.length(0);
  });

  it("submits a presence marker when every editable rate is unchecked", async () => {
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

    const checkbox = controls.list.querySelector('input[value="txr_state"]');
    checkbox.checked = false;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    const formData = new FormData(controls.form);

    expect(formData.get("manual_tax_rate_ids_present")).to.equal("true");
    expect(formData.getAll("manual_tax_rate_ids[]")).to.deep.equal([]);
  });
});
