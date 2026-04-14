import "/static/js/dashboard/event/ticketing/discount-codes-editor.js";
import "/static/js/dashboard/event/ticketing/ticket-types-editor.js";

export function initializeTicketingWaitlistState() {
  const capacityInput = document.getElementById("capacity");
  const clearTicketingInput = document.getElementById("clear_ticketing");
  const paymentCurrencyInput = document.getElementById("payment_currency_code");
  const ticketTypesEditor = document.querySelector("ticket-types-editor");
  const toggleClearTicketing = document.getElementById("toggle_clear_ticketing");
  const toggleWaitlistEnabled = document.getElementById("toggle_waitlist_enabled");
  const waitlistEnabledInput = document.getElementById("waitlist_enabled");
  const waitlistToggleLabel = document.getElementById("waitlist-toggle-label");

  const syncWaitlistToggleState = () => {
    if (!toggleWaitlistEnabled || !waitlistEnabledInput || !capacityInput) {
      return;
    }

    const clearingTicketing = toggleClearTicketing?.checked === true;
    const hasTicketTypes =
      typeof ticketTypesEditor?.hasConfiguredTicketTypes === "function"
        ? ticketTypesEditor.hasConfiguredTicketTypes() && !clearingTicketing
        : false;
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

    if (paymentCurrencyInput) {
      paymentCurrencyInput.required = hasTicketTypes && !paymentCurrencyInput.disabled;
      paymentCurrencyInput.placeholder = "USD";
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

  if (ticketTypesEditor) {
    ticketTypesEditor.addEventListener("ticket-types-changed", syncWaitlistToggleState);
  }

  if (toggleClearTicketing && clearTicketingInput) {
    toggleClearTicketing.addEventListener("change", () => {
      clearTicketingInput.value = String(toggleClearTicketing.checked);
      syncWaitlistToggleState();
    });
  }

  syncWaitlistToggleState();
}
