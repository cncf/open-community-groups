import { toTrimmedString } from "/static/js/common/utils.js";

const DEFAULT_CURRENCY_PLACEHOLDER = "USD";
const STRIPE_MAXIMUM_CHARGE_AMOUNTS_MINOR = {
  COP: 9999999999999,
  HUF: 9999999999999,
  IDR: 999999999999,
  INR: 999999999,
  JPY: 9999999999999,
  LBP: 999999999999,
};
const STRIPE_MINIMUM_CHARGE_AMOUNTS_MINOR = {
  AED: 200,
  ARS: 50,
  AUD: 50,
  BRL: 50,
  CAD: 50,
  CHF: 50,
  COP: 50,
  CZK: 1500,
  DKK: 250,
  EUR: 50,
  GBP: 30,
  HKD: 400,
  HUF: 17500,
  IDR: 50,
  ILS: 50,
  INR: 50,
  JPY: 50,
  KRW: 50,
  MXN: 1000,
  MYR: 200,
  NOK: 300,
  NZD: 50,
  PHP: 50,
  PLN: 200,
  RON: 200,
  RUB: 50,
  SEK: 300,
  SGD: 50,
  THB: 1000,
  USD: 50,
  ZAR: 50,
};
const STRIPE_STANDARD_MAXIMUM_CHARGE_AMOUNT_MINOR = 99999999;

/**
 * Resolves the event currency from the shared event form.
 * @param {HTMLInputElement|HTMLSelectElement|null} [currencyField]
 * @returns {string}
 */
export const resolveEventCurrencyCode = (
  currencyField = document.getElementById("payment_currency_code"),
) => {
  const currencyCode = toTrimmedString(currencyField?.value).toUpperCase();

  return currencyCode || DEFAULT_CURRENCY_PLACEHOLDER;
};

/**
 * Resolves the number of fraction digits for a currency.
 * @param {string} currencyCode ISO currency code
 * @returns {number}
 */
const resolveCurrencyFractionDigits = (currencyCode) => {
  try {
    return new Intl.NumberFormat("en", {
      currency: currencyCode,
      style: "currency",
    }).resolvedOptions().maximumFractionDigits;
  } catch (_) {
    return 2;
  }
};

/**
 * Formats a minor-unit amount for a currency input.
 * @param {number} amountMinor Amount in minor units
 * @param {string} currencyCode ISO currency code
 * @returns {string}
 */
export const formatMinorUnitsForInput = (amountMinor, currencyCode) => {
  if (!Number.isFinite(amountMinor)) {
    return "";
  }

  const fractionDigits = resolveCurrencyFractionDigits(currencyCode);
  if (fractionDigits === 0) {
    return String(amountMinor);
  }

  const divisor = 10 ** fractionDigits;
  const isNegative = amountMinor < 0;
  const normalizedAmount = Math.abs(amountMinor);
  const whole = Math.floor(normalizedAmount / divisor);
  const fraction = String(normalizedAmount % divisor).padStart(fractionDigits, "0");

  return `${isNegative ? "-" : ""}${whole}.${fraction}`;
};

/**
 * Returns Stripe's maximum charge amount for a currency input.
 * @param {string} currencyCode ISO currency code
 * @returns {string}
 */
export const resolveStripeMaximumChargeInput = (currencyCode) =>
  formatMinorUnitsForInput(resolveStripeMaximumChargeMinor(currencyCode), currencyCode);

/**
 * Returns Stripe's maximum charge amount in minor units.
 * @param {string} currencyCode ISO currency code
 * @returns {number}
 */
export const resolveStripeMaximumChargeMinor = (currencyCode) =>
  STRIPE_MAXIMUM_CHARGE_AMOUNTS_MINOR[toTrimmedString(currencyCode).toUpperCase()] ||
  STRIPE_STANDARD_MAXIMUM_CHARGE_AMOUNT_MINOR;

/**
 * Returns Stripe's minimum non-zero charge amount for a currency input.
 * @param {string} currencyCode ISO currency code
 * @returns {string}
 */
export const resolveStripeMinimumChargeInput = (currencyCode) => {
  const amountMinor = resolveStripeMinimumChargeMinor(currencyCode);
  return amountMinor === null ? "" : formatMinorUnitsForInput(amountMinor, currencyCode);
};

/**
 * Returns Stripe's minimum non-zero charge amount in minor units.
 * @param {string} currencyCode ISO currency code
 * @returns {number|null}
 */
export const resolveStripeMinimumChargeMinor = (currencyCode) =>
  STRIPE_MINIMUM_CHARGE_AMOUNTS_MINOR[toTrimmedString(currencyCode).toUpperCase()] || null;

/**
 * Parses a currency input string into minor units.
 * @param {string} value Currency input value
 * @param {string} currencyCode ISO currency code
 * @returns {number|null}
 */
export const parseCurrencyInputToMinorUnits = (value, currencyCode) => {
  const trimmedValue = toTrimmedString(value);
  if (!trimmedValue) {
    return null;
  }

  const match = trimmedValue.match(/^(-)?(?:(\d+)(?:\.(\d+))?|\.(\d+))$/);
  if (!match) {
    return null;
  }

  const fractionDigits = resolveCurrencyFractionDigits(currencyCode);
  const sign = match[1] ? -1 : 1;
  const wholePart = match[2] || "0";
  const fractionPart = match[3] || match[4] || "";

  if (fractionPart.length > fractionDigits) {
    return null;
  }

  const paddedFraction = fractionPart.padEnd(fractionDigits, "0") || "0";
  const divisor = 10 ** fractionDigits;
  const wholeMinor = Number.parseInt(wholePart, 10) * divisor;
  const fractionMinor = fractionDigits === 0 ? 0 : Number.parseInt(paddedFraction, 10);

  return sign * (wholeMinor + fractionMinor);
};

/**
 * Returns an example placeholder for currency amount inputs.
 * @param {string} currencyCode ISO currency code
 * @returns {string}
 */
export const resolveCurrencyInputPlaceholder = (currencyCode) => {
  const fractionDigits = resolveCurrencyFractionDigits(currencyCode);
  return fractionDigits === 0 ? "5000" : `25.${"0".repeat(fractionDigits)}`;
};

/**
 * Returns a step value for currency amount inputs.
 * @param {string} currencyCode ISO currency code
 * @returns {string}
 */
export const resolveCurrencyInputStep = (currencyCode) => {
  const fractionDigits = resolveCurrencyFractionDigits(currencyCode);
  if (fractionDigits === 0) {
    return "1";
  }

  return `0.${"0".repeat(fractionDigits - 1)}1`;
};

/**
 * Returns a validation message when an amount falls outside Stripe charge limits.
 * @param {number|null} amountMinor Amount in minor units
 * @param {string} currencyCode ISO currency code
 * @returns {string}
 */
export const validateStripePaymentAmountMinor = (amountMinor, currencyCode) => {
  if (amountMinor === null || !Number.isFinite(amountMinor) || amountMinor === 0) {
    return "";
  }

  const normalizedCurrencyCode = toTrimmedString(currencyCode).toUpperCase();
  const maximumAmountMinor = resolveStripeMaximumChargeMinor(normalizedCurrencyCode);
  const minimumAmountMinor = resolveStripeMinimumChargeMinor(normalizedCurrencyCode);

  if (amountMinor < 0) {
    return "Payment amount must be 0 or greater.";
  }

  if (minimumAmountMinor !== null && amountMinor < minimumAmountMinor) {
    const minimumAmount = formatMinorUnitsForInput(minimumAmountMinor, normalizedCurrencyCode);
    return `Use 0 for free tickets, or at least ${minimumAmount} ${normalizedCurrencyCode}.`;
  }

  if (amountMinor > maximumAmountMinor) {
    const maximumAmount = formatMinorUnitsForInput(maximumAmountMinor, normalizedCurrencyCode);
    return `Stripe allows up to ${maximumAmount} ${normalizedCurrencyCode}.`;
  }

  return "";
};
