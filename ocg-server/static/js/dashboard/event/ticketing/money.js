import {
  DEFAULT_CURRENCY_PLACEHOLDER,
  toTrimmedString,
} from "/static/js/dashboard/event/ticketing/shared.js";

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
export const resolveCurrencyFractionDigits = (currencyCode) => {
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
