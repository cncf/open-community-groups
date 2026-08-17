import { getElementById } from "/static/js/common/dom.js";

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
  const list = fieldset?.querySelector('[data-tax-rates-role="list"]');
  const retryButton = fieldset?.querySelector('[data-tax-rates-action="retry"]');
  const state = fieldset?.querySelector('[data-tax-rates-role="state"]');
  const taxBehaviorField = getElementById(root, "tax_behavior");
  const taxBehaviorWrapper = root.querySelector('[data-tax-control="behavior"]');
  const taxModeField = getElementById(root, "tax_calculation_mode");
  const ticketTypesEditor = getElementById(root, "ticket-types-ui");

  if (!fieldset || !list || !retryButton || !state || !taxBehaviorField || !taxModeField) {
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
    const hasSelection = list.querySelector(`input[name="${RATE_FIELD_NAME}"]:checked`) !== null;
    taxModeField.setCustomValidity(
      requiresSelection && (!hasSelection || unavailableSelection)
        ? "Select at least one available Stripe Tax Rate for paid tickets."
        : "",
    );
  };

  const loadRates = async () => {
    const behavior = taxBehaviorField.value;
    abortController?.abort();
    abortController = new AbortController();
    renderStatus({ retryButton, state }, "loading", behavior);
    list.replaceChildren();
    syncValidity();

    try {
      // Load every active compatible rate from the current fiscal sponsor
      const url = new URL(fieldset.dataset.taxRatesUrl, window.location.origin);
      url.searchParams.set("tax_behavior", behavior);
      const response = await fetch(url, {
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
      unavailableSelection = renderRates({
        behavior,
        disabled: fieldset.dataset.disabled === "true",
        list,
        rates,
        selectedRateIds,
      });
      if (fieldset.dataset.disabled !== "true") {
        initialHiddenInputs.splice(0).forEach((input) => input.remove());
      }
      renderStatus(
        { retryButton, state },
        unavailableSelection ? "unavailable" : rates.length === 0 ? "empty" : "ready",
        behavior,
        rates.length,
      );
      syncValidity();
    } catch (error) {
      if (error.name === "AbortError") {
        return;
      }
      renderStatus({ retryButton, state }, "error", behavior);
      syncValidity();
    }
  };

  const syncTaxControls = ({ behaviorChanged = false } = {}) => {
    const mode = taxModeField.value;
    const isManual = mode === MANUAL_MODE;
    const hasTax = mode !== "none";

    taxBehaviorWrapper?.classList.toggle("hidden", !hasTax);
    taxBehaviorField.disabled = !hasTax || fieldset.dataset.disabled === "true";
    if (!hasTax) {
      taxBehaviorField.value = "inclusive";
    }
    fieldset.hidden = !isManual;

    if (!isManual) {
      abortController?.abort();
      loadedBehavior = null;
      selectedRateIds.clear();
      initialHiddenInputs.splice(0).forEach((input) => input.remove());
      list.replaceChildren();
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
  list.addEventListener("change", (event) => {
    if (event.target?.matches(`input[name="${RATE_FIELD_NAME}"]`)) {
      unavailableSelection = false;
      syncValidity();
    }
  });
  retryButton.addEventListener("click", () => {
    loadedBehavior = null;
    void loadRates();
  });
  fieldset.addEventListener("tax-rate-selection-updated", (event) => {
    selectedRateIds.clear();
    for (const rateId of event.detail?.rateIds || []) {
      if (typeof rateId === "string" && rateId.trim() !== "") {
        selectedRateIds.add(rateId);
      }
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
 * Renders active Tax Rate checkboxes and reports missing prior selections.
 * @param {Object} config Render configuration.
 * @returns {boolean} Whether a previously selected rate is unavailable.
 */
const renderRates = ({ behavior, disabled, list, rates, selectedRateIds }) => {
  const availableIds = new Set();
  const fragment = document.createDocumentFragment();

  for (const rate of rates) {
    if (!rate || typeof rate.id !== "string") {
      continue;
    }
    availableIds.add(rate.id);
    const label = document.createElement("label");
    label.className = "flex items-start gap-3 rounded-md border border-stone-200 bg-white p-4";

    const checkbox = document.createElement("input");
    checkbox.className = "checkbox-primary mt-1";
    checkbox.type = "checkbox";
    checkbox.name = RATE_FIELD_NAME;
    checkbox.value = rate.id;
    checkbox.checked = selectedRateIds.has(rate.id);
    checkbox.disabled = disabled;

    const description = document.createElement("span");
    description.className = "min-w-0 text-sm/6 text-stone-600";
    const title = document.createElement("span");
    title.className = "block font-medium text-stone-900";
    title.textContent = `${rate.display_name || "Tax Rate"} — ${rate.percentage}%`;
    const detail = document.createElement("span");
    detail.className = "block";
    detail.textContent = `${rate.jurisdiction || "Jurisdiction not specified"} · Tax ${
      behavior === "inclusive" ? "included in the ticket price" : "added at Checkout"
    }`;
    description.append(title, detail);
    label.append(checkbox, description);
    fragment.append(label);
  }

  list.replaceChildren(fragment);
  return Array.from(selectedRateIds).some((id) => !availableIds.has(id));
};

/**
 * Renders the accessible loading, empty, error, ready, or unavailable state.
 * @param {Object} elements State elements.
 * @param {string} status Current state.
 * @param {string} behavior Requested tax behavior.
 * @param {number} [count=0] Available rate count.
 */
const renderStatus = ({ retryButton, state }, status, behavior, count = 0) => {
  retryButton.hidden = status !== "error";
  state.classList.toggle("text-red-700", status === "error" || status === "unavailable");

  const behaviorLabel = behavior === "inclusive" ? "inclusive" : "exclusive";
  const messages = {
    empty: `No active ${behaviorLabel} Tax Rates are available. Create rates in the fiscal sponsor's Stripe account, then retry.`,
    error:
      "Stripe Tax Rates are unavailable right now. Retry the request before saving paid manual-tax tickets.",
    loading: `Loading active ${behaviorLabel} Stripe Tax Rates…`,
    ready: `${count} active ${behaviorLabel} Stripe Tax Rate${count === 1 ? "" : "s"} available.`,
    unavailable:
      "One or more previously selected Tax Rates are inactive, missing, or belong to another account. Select available rates before saving.",
  };
  state.textContent = messages[status] || "";
};
