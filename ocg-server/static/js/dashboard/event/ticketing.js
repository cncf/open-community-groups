import { queryElementById } from "/static/js/common/dom.js";

/**
 * Collects the shared ticketing controls used across the form.
 * @param {Document|Element} [root=document] Root container
 * @returns {{
 *   capacityInput: HTMLElement|null,
 *   clearTicketingInput: HTMLElement|null,
 *   discountCodesRoot: HTMLElement|null,
 *   paymentCurrencyInput: HTMLElement|null,
 *   ticketTypesRoot: HTMLElement|null,
 *   timezoneInput: HTMLElement|null,
 *   toggleClearTicketing: HTMLElement|null,
 *   toggleWaitlistEnabled: HTMLElement|null,
 *   waitlistEnabledInput: HTMLElement|null,
 *   waitlistToggleLabel: HTMLElement|null
 * }}
 */
const resolveTicketingControls = (root = document) => ({
  capacityInput: queryElementById(root, "capacity"),
  clearTicketingInput: queryElementById(root, "clear_ticketing"),
  discountCodesRoot: queryElementById(root, "discount-codes-ui"),
  paymentCurrencyInput: queryElementById(root, "payment_currency_code"),
  ticketTypesRoot: queryElementById(root, "ticket-types-ui"),
  timezoneInput: root.querySelector('[name="timezone"]'),
  toggleClearTicketing: queryElementById(root, "toggle_clear_ticketing"),
  toggleWaitlistEnabled: queryElementById(root, "toggle_waitlist_enabled"),
  waitlistEnabledInput: queryElementById(root, "waitlist_enabled"),
  waitlistToggleLabel: queryElementById(root, "waitlist-toggle-label"),
});

/**
 * Synchronizes capacity, waitlist, and currency validation with ticket types.
 * @param {Document|Element} [root=document] Root container
 * @returns {void}
 */
export function initializeTicketingWaitlistState(root = document) {
  const {
    capacityInput,
    clearTicketingInput,
    paymentCurrencyInput,
    ticketTypesRoot,
    toggleClearTicketing,
    toggleWaitlistEnabled,
    waitlistEnabledInput,
    waitlistToggleLabel,
  } = resolveTicketingControls(root);
  const ticketTypesEditor = ticketTypesRoot;

  const syncPaymentCurrencyValidity = (hasTicketTypes) => {
    if (!paymentCurrencyInput) {
      return;
    }

    const requiresCurrency = hasTicketTypes && !paymentCurrencyInput.disabled;
    const hasCurrency = paymentCurrencyInput.value.trim() !== "";

    paymentCurrencyInput.required = requiresCurrency;
    paymentCurrencyInput.setCustomValidity(
      requiresCurrency && !hasCurrency ? "Ticketed events require an event currency." : "",
    );
  };

  const syncWaitlistToggleState = () => {
    const clearingTicketing = toggleClearTicketing?.checked === true;
    const hasTicketTypes =
      typeof ticketTypesEditor?.hasConfiguredTicketTypes === "function"
        ? ticketTypesEditor.hasConfiguredTicketTypes() && !clearingTicketing
        : false;
    syncPaymentCurrencyValidity(hasTicketTypes);

    if (!toggleWaitlistEnabled || !waitlistEnabledInput || !capacityInput) {
      return;
    }

    const configuredSeatTotal =
      typeof ticketTypesEditor?.getConfiguredSeatTotal === "function"
        ? ticketTypesEditor.getConfiguredSeatTotal()
        : null;

    if (hasTicketTypes) {
      if (!capacityInput.disabled) {
        capacityInput.dataset.manualValue = capacityInput.value;
      }

      capacityInput.disabled = true;
      capacityInput.placeholder = "Derived from ticket seats";
      capacityInput.value =
        Number.isFinite(configuredSeatTotal) && configuredSeatTotal > 0 ? String(configuredSeatTotal) : "";
    } else {
      capacityInput.disabled = false;
      capacityInput.placeholder = "100";

      if (capacityInput.dataset.manualValue !== undefined) {
        capacityInput.value = capacityInput.dataset.manualValue;
        delete capacityInput.dataset.manualValue;
      }
    }

    const capacityValue = Number.parseInt(capacityInput.value, 10);
    const capacityIsValid = Number.isFinite(capacityValue) && capacityValue > 0;
    const canEnableWaitlist = capacityIsValid && !hasTicketTypes;

    toggleWaitlistEnabled.disabled = !canEnableWaitlist;
    if (!canEnableWaitlist) {
      toggleWaitlistEnabled.checked = false;
      waitlistEnabledInput.value = "false";
    } else {
      waitlistEnabledInput.value = String(toggleWaitlistEnabled.checked);
    }

    if (waitlistToggleLabel) {
      waitlistToggleLabel.classList.toggle("cursor-pointer", canEnableWaitlist);
      waitlistToggleLabel.classList.toggle("cursor-not-allowed", !canEnableWaitlist);
      waitlistToggleLabel.classList.toggle("opacity-50", !canEnableWaitlist);
    }
  };

  if (toggleWaitlistEnabled && waitlistEnabledInput) {
    toggleWaitlistEnabled.addEventListener("change", () => {
      waitlistEnabledInput.value = String(toggleWaitlistEnabled.checked);
    });
  }

  if (capacityInput) {
    capacityInput.addEventListener("input", syncWaitlistToggleState);
  }

  if (ticketTypesRoot) {
    ticketTypesRoot.addEventListener("ticket-types-changed", syncWaitlistToggleState);
  }

  if (paymentCurrencyInput) {
    paymentCurrencyInput.addEventListener("input", syncWaitlistToggleState);
    paymentCurrencyInput.addEventListener("change", syncWaitlistToggleState);
  }

  if (toggleClearTicketing && clearTicketingInput) {
    toggleClearTicketing.addEventListener("change", () => {
      clearTicketingInput.value = String(toggleClearTicketing.checked);
      syncWaitlistToggleState();
    });
  }

  syncWaitlistToggleState();
}
