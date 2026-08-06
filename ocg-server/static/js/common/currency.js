const CURRENCY_LABEL_PATTERN = /^(From )?([A-Z]{3})\s+(-?\d+(?:\.\d+)?)$/;

/**
 * Formats a server currency label for the browser locale.
 * @param {unknown} value Currency label such as "USD 5.00".
 * @param {string|string[]|undefined} locale Optional locale override.
 * @returns {string} Localized label, or the original value when it cannot be formatted.
 */
export const localizeCurrencyLabel = (value, locale = undefined) => {
  const label = typeof value === "string" ? value.trim() : "";
  const match = label.match(CURRENCY_LABEL_PATTERN);
  if (!match) {
    return label;
  }

  const [, prefix = "", currency, amountText] = match;
  const amount = Number(amountText);
  if (!Number.isFinite(amount)) {
    return label;
  }

  try {
    return `${prefix}${new Intl.NumberFormat(locale, { currency, style: "currency" }).format(amount)}`;
  } catch (_) {
    return label;
  }
};

/**
 * Localizes marked currency labels within a document or swapped fragment.
 * @param {Document|Element} root Root containing currency labels.
 * @returns {void}
 */
export const localizeCurrencyElements = (root = document) => {
  const elements = [];
  if (root instanceof Element && root.matches("[data-localized-currency]")) {
    elements.push(root);
  }
  elements.push(...(root.querySelectorAll?.("[data-localized-currency]") ?? []));

  elements.forEach((element) => {
    element.textContent = localizeCurrencyLabel(element.textContent);
  });
};
