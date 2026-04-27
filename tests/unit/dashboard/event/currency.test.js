import { expect } from "@open-wc/testing";

import {
  formatMinorUnitsForInput,
  parseCurrencyInputToMinorUnits,
  resolveCurrencyInputPlaceholder,
  resolveCurrencyInputStep,
  resolveEventCurrencyCode,
  resolveStripeMaximumChargeInput,
  resolveStripeMaximumChargeMinor,
  resolveStripeMinimumChargeInput,
  resolveStripeMinimumChargeMinor,
  validateStripePaymentAmountMinor,
} from "/static/js/dashboard/event/ticketing/currency.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("ticketing currency helpers", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("resolves the event currency code with a fallback", () => {
    const currencyField = document.createElement("input");
    currencyField.value = " eur ";
    document.body.append(currencyField);

    expect(resolveEventCurrencyCode(currencyField)).to.equal("EUR");
    expect(resolveEventCurrencyCode(null)).to.equal("USD");
  });

  it("resolves input metadata for decimal and zero-decimal currencies", () => {
    expect(resolveCurrencyInputPlaceholder("USD")).to.equal("25.00");
    expect(resolveCurrencyInputPlaceholder("JPY")).to.equal("5000");

    expect(resolveCurrencyInputStep("USD")).to.equal("0.01");
    expect(resolveCurrencyInputStep("JPY")).to.equal("1");
  });

  it("resolves Stripe charge limits for supported currencies", () => {
    expect(resolveStripeMaximumChargeInput("USD")).to.equal("999999.99");
    expect(resolveStripeMaximumChargeInput("JPY")).to.equal("9999999999999");
    expect(resolveStripeMaximumChargeMinor("INR")).to.equal(999999999);

    expect(resolveStripeMinimumChargeInput("USD")).to.equal("0.50");
    expect(resolveStripeMinimumChargeInput("JPY")).to.equal("50");
    expect(resolveStripeMinimumChargeMinor("GBP")).to.equal(30);
    expect(resolveStripeMinimumChargeMinor("VND")).to.equal(null);
  });

  it("formats and parses minor units for different currencies", () => {
    expect(formatMinorUnitsForInput(1234, "USD")).to.equal("12.34");
    expect(formatMinorUnitsForInput(-1234, "USD")).to.equal("-12.34");
    expect(formatMinorUnitsForInput(5000, "JPY")).to.equal("5000");
    expect(formatMinorUnitsForInput(Number.NaN, "USD")).to.equal("");

    expect(parseCurrencyInputToMinorUnits("12.34", "USD")).to.equal(1234);
    expect(parseCurrencyInputToMinorUnits(".5", "USD")).to.equal(50);
    expect(parseCurrencyInputToMinorUnits("5000", "JPY")).to.equal(5000);
    expect(parseCurrencyInputToMinorUnits("12.345", "USD")).to.equal(null);
    expect(parseCurrencyInputToMinorUnits("abc", "USD")).to.equal(null);
    expect(parseCurrencyInputToMinorUnits("", "USD")).to.equal(null);
  });

  it("validates Stripe charge limits", () => {
    expect(validateStripePaymentAmountMinor(0, "USD")).to.equal("");
    expect(validateStripePaymentAmountMinor(50, "USD")).to.equal("");
    expect(validateStripePaymentAmountMinor(49, "USD")).to.equal(
      "Use 0 for free tickets, or at least 0.50 USD.",
    );
    expect(validateStripePaymentAmountMinor(100000000, "USD")).to.equal("Stripe allows up to 999999.99 USD.");
  });
});
