import { getElementById } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import "/static/js/common/svg-spinner.js";

const MANUAL_MODE = "manual";
const PRESENCE_FIELD_NAME = "manual_tax_rate_ids_present";
const RATE_FIELD_NAME = "manual_tax_rate_ids[]";

/**
 * Initializes event-level manual Stripe Tax Rate selection.
 * @param {Document|Element} [root=document] Event page root.
 * @returns {() => void} Tax control synchronization callback.
 */
export const initializeManualTaxRates = (root = document) => {
  const fieldset = getElementById(root, "manual-tax-rates-fieldset");
  const select = fieldset?.querySelector('[data-tax-rates-role="select"]');
  const retryButton = fieldset?.querySelector('[data-tax-rates-action="retry"]');
  const retryLabel = fieldset?.querySelector('[data-tax-rates-role="retry-label"]');
  const retryLoading = fieldset?.querySelector('[data-tax-rates-role="retry-loading"]');
  const state = fieldset?.querySelector('[data-tax-rates-role="state"]');
  const taxBehaviorField = getElementById(root, "tax_behavior");
  const taxModeField = getElementById(root, "tax_calculation_mode");
  const ticketTypesEditor = getElementById(root, "ticket-types-ui");

  if (
    !fieldset ||
    !select ||
    !retryButton ||
    !retryLabel ||
    !retryLoading ||
    !state ||
    !taxBehaviorField ||
    !taxModeField
  ) {
    return () => {};
  }

  const selectedRateIds = new Set(parseSelectedRateIds(fieldset.dataset.selectedRateIds));
  if (fieldset.dataset.disabled !== "true") {
    const presenceInput = document.createElement("input");
    presenceInput.type = "hidden";
    presenceInput.name = PRESENCE_FIELD_NAME;
    presenceInput.value = "true";
    fieldset.append(presenceInput);
  }
  const initialHiddenInputs = Array.from(selectedRateIds, (rateId) => {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = RATE_FIELD_NAME;
    input.value = rateId;
    fieldset.append(input);
    return input;
  });
  let abortController = null;
  let loadedBehavior = null;
  let unavailableSelection = false;

  const syncValidity = () => {
    const hasPositivePrices = ticketTypesEditor?.hasConfiguredPositivePrices?.() === true;
    const requiresSelection = taxModeField.value === MANUAL_MODE && hasPositivePrices;
    const hasSelection = select.value !== "";
    select.name = hasSelection ? RATE_FIELD_NAME : "";
    taxModeField.setCustomValidity(
      requiresSelection && (!hasSelection || unavailableSelection)
        ? "Select an available Stripe Tax Rate for paid tickets."
        : "",
    );
  };

  const loadRates = async ({ showRetryLoading = false } = {}) => {
    const behavior = taxBehaviorField.value;
    abortController?.abort();
    abortController = new AbortController();
    renderStatus({ retryButton, select, state }, "loading", behavior);
    if (showRetryLoading) {
      setRetryLoading({ retryButton, retryLabel, retryLoading }, true);
    }
    syncValidity();

    try {
      // Load every active compatible rate from the current fiscal sponsor
      const url = new URL(fieldset.dataset.taxRatesUrl, window.location.origin);
      url.searchParams.set("tax_behavior", behavior);
      const response = await ocgFetch(url, {
        headers: { Accept: "application/json" },
        signal: abortController.signal,
      });
      if (!response.ok) {
        throw new Error(`Tax Rate request failed with status ${response.status}`);
      }
      const rates = await response.json();
      if (!Array.isArray(rates)) {
        throw new Error("Tax Rate response is invalid");
      }

      // Ignore results superseded by a newer mode or behavior request
      if (taxModeField.value !== MANUAL_MODE || taxBehaviorField.value !== behavior) {
        return;
      }

      loadedBehavior = behavior;
      const disabled = fieldset.dataset.disabled === "true";
      unavailableSelection = renderRates({
        behavior,
        disabled,
        rates,
        select,
        selectedRateIds,
      });
      if (!disabled) {
        initialHiddenInputs.splice(0).forEach((input) => input.remove());
      }
      const status = disabled
        ? "read-only"
        : unavailableSelection
          ? "unavailable"
          : rates.length === 0
            ? "empty"
            : "ready";
      renderStatus({ retryButton, select, state }, status, behavior);
      syncValidity();
    } catch (error) {
      if (error.name === "AbortError") {
        return;
      }
      renderStatus({ retryButton, select, state }, "error", behavior);
      syncValidity();
    } finally {
      if (showRetryLoading) {
        setRetryLoading({ retryButton, retryLabel, retryLoading }, false);
      }
    }
  };

  const syncTaxControls = ({ behaviorChanged = false } = {}) => {
    const mode = taxModeField.value;
    const isManual = mode === MANUAL_MODE;
    const hasTax = mode !== "none";

    taxBehaviorField.disabled = !hasTax || fieldset.dataset.disabled === "true";
    fieldset.hidden = !isManual;

    if (!isManual) {
      abortController?.abort();
      loadedBehavior = null;
      selectedRateIds.clear();
      initialHiddenInputs.splice(0).forEach((input) => input.remove());
      select.replaceChildren();
      select.disabled = true;
      unavailableSelection = false;
      syncValidity();
      return;
    }

    if (behaviorChanged) {
      selectedRateIds.clear();
      loadedBehavior = null;
      unavailableSelection = false;
    }
    if (loadedBehavior !== taxBehaviorField.value) {
      void loadRates();
    }
    syncValidity();
  };

  taxModeField.addEventListener("change", () => syncTaxControls());
  taxBehaviorField.addEventListener("change", () => syncTaxControls({ behaviorChanged: true }));
  ticketTypesEditor?.addEventListener("ticket-types-changed", syncValidity);
  select.addEventListener("change", () => {
    unavailableSelection = false;
    renderStatus({ retryButton, select, state }, "ready", taxBehaviorField.value);
    syncValidity();
  });
  retryButton.addEventListener("click", () => {
    loadedBehavior = null;
    void loadRates({ showRetryLoading: true });
  });
  fieldset.addEventListener("tax-rate-selection-updated", (event) => {
    selectedRateIds.clear();
    const selectedRateId = Array.isArray(event.detail?.rateIds)
      ? event.detail.rateIds.find((rateId) => typeof rateId === "string" && rateId.trim() !== "")
      : undefined;
    if (selectedRateId) {
      selectedRateIds.add(selectedRateId);
    }
    initialHiddenInputs.splice(0).forEach((input) => input.remove());
    for (const rateId of selectedRateIds) {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = RATE_FIELD_NAME;
      input.value = rateId;
      fieldset.append(input);
      initialHiddenInputs.push(input);
    }
    loadedBehavior = null;
    unavailableSelection = false;
    syncTaxControls();
  });

  syncTaxControls();
  return () => syncTaxControls();
};

/**
 * Parses server-rendered selected Tax Rate identifiers.
 * @param {string|undefined} value JSON-encoded identifier array.
 * @returns {string[]} Normalized identifiers.
 */
const parseSelectedRateIds = (value) => {
  try {
    const parsed = JSON.parse(value || "[]");
    return Array.isArray(parsed) ? parsed.filter((id) => typeof id === "string" && id.trim() !== "") : [];
  } catch {
    return [];
  }
};

/**
 * Renders active Tax Rate options and reports missing prior selections.
 * @param {Object} config Render configuration.
 * @returns {boolean} Whether a previously selected rate is unavailable.
 */
const renderRates = ({ behavior, disabled, rates, select, selectedRateIds }) => {
  const availableIds = new Set();
  const fragment = document.createDocumentFragment();
  const selectedRateId = selectedRateIds.values().next().value;
  const placeholder = document.createElement("option");
  placeholder.disabled = true;
  placeholder.selected = true;
  placeholder.value = "";
  placeholder.textContent = "Select a Stripe Tax Rate";
  fragment.append(placeholder);

  for (const rate of rates) {
    if (!rate || typeof rate.id !== "string") {
      continue;
    }
    availableIds.add(rate.id);
    const option = document.createElement("option");
    option.value = rate.id;
    option.selected = rate.id === selectedRateId;
    if (option.selected) {
      placeholder.selected = false;
    }
    option.textContent = `${rate.display_name || "Tax Rate"} — ${rate.percentage}% · ${
      rate.jurisdiction || "Jurisdiction not specified"
    } · Tax ${behavior === "inclusive" ? "included in the ticket price" : "added at Checkout"}`;
    fragment.append(option);
  }

  select.replaceChildren(fragment);
  select.disabled = disabled;
  return Array.from(selectedRateIds).some((id) => !availableIds.has(id));
};

/**
 * Shows a non-selectable status inside the Tax Rate selector.
 * @param {HTMLSelectElement} select Tax Rate selector.
 * @param {string} message Status message.
 */
const renderSelectMessage = (select, message) => {
  const option = document.createElement("option");
  option.disabled = true;
  option.selected = true;
  option.value = "";
  option.textContent = message;
  select.replaceChildren(option);
  select.disabled = true;
};

/**
 * Renders the Tax Rate loading, empty, error, ready, unavailable, or read-only state.
 * @param {Object} elements State elements.
 * @param {string} status Current state.
 * @param {string} behavior Requested tax behavior.
 */
const renderStatus = ({ retryButton, select, state }, status, behavior) => {
  retryButton.hidden = status !== "error";
  retryButton.title = status === "error" ? "Retry the request before saving paid manual-tax tickets." : "";
  const showUnavailable = status === "unavailable";
  const showReadOnly = status === "read-only";
  state.hidden = !showUnavailable && !showReadOnly;
  state.classList.toggle("text-red-700", showUnavailable);
  state.classList.toggle("text-stone-600", showReadOnly);

  const behaviorLabel = behavior === "inclusive" ? "inclusive" : "exclusive";
  const messages = {
    empty: `No active ${behaviorLabel} Tax Rates are available.`,
    error:
      "Stripe Tax Rates are unavailable right now. Retry the request before saving paid manual-tax tickets.",
    loading: `Loading active ${behaviorLabel} Stripe Tax Rates…`,
    "read-only": "Manual Tax Rate selection is currently read-only.",
    unavailable:
      "A previously selected Tax Rate is inactive, missing, or belongs to another account. Select an available rate before saving.",
  };
  state.textContent = state.hidden ? "" : messages[status];

  if (status === "loading" || status === "empty" || status === "error") {
    renderSelectMessage(
      select,
      status === "error" ? "Stripe Tax Rates are unavailable right now." : messages[status],
    );
  }
};

/**
 * Synchronizes the Retry button's pending state.
 * @param {Object} elements Retry button elements.
 * @param {boolean} loading Whether a retry request is pending.
 */
const setRetryLoading = ({ retryButton, retryLabel, retryLoading }, loading) => {
  retryButton.disabled = loading;
  retryButton.toggleAttribute("aria-busy", loading);
  retryLabel.hidden = loading;
  retryLoading.hidden = !loading;
  if (loading) {
    retryButton.hidden = false;
  }
};
