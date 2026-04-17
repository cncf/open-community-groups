import { initializeDiscountCodesController } from "/static/js/dashboard/event/ticketing/discount-codes-editor.js";
import { initializeTicketTypesController } from "/static/js/dashboard/event/ticketing/ticket-types-editor.js";

const ticketingControllerConfigs = [
  {
    controllerKey: "_discountCodesController",
    rootId: "discount-codes-ui",
  },
  {
    controllerKey: "_ticketTypesController",
    rootId: "ticket-types-ui",
  },
];

let hasBoundTicketingCleanup = false;

const queryControlById = (root, id) => {
  if (typeof root.getElementById === "function") {
    return root.getElementById(id);
  }

  return root.querySelector(`#${id}`);
};

const resolveTicketingControls = (root = document) => ({
  capacityInput: queryControlById(root, "capacity"),
  clearTicketingInput: queryControlById(root, "clear_ticketing"),
  discountCodesRoot: queryControlById(root, "discount-codes-ui"),
  paymentCurrencyInput: queryControlById(root, "payment_currency_code"),
  ticketTypesRoot: queryControlById(root, "ticket-types-ui"),
  timezoneInput: root.querySelector('[name="timezone"]'),
  toggleClearTicketing: queryControlById(root, "toggle_clear_ticketing"),
  toggleWaitlistEnabled: queryControlById(root, "toggle_waitlist_enabled"),
  waitlistEnabledInput: queryControlById(root, "waitlist_enabled"),
  waitlistToggleLabel: queryControlById(root, "waitlist-toggle-label"),
});

const destroyTicketingControllersWithin = (container) => {
  if (!(container instanceof Element)) {
    return;
  }

  ticketingControllerConfigs.forEach(({ controllerKey, rootId }) => {
    const root = container.id === rootId ? container : container.querySelector(`#${rootId}`);
    const controller = root?.[controllerKey];

    if (typeof controller?.destroy === "function") {
      controller.destroy();
    }

    if (root && controllerKey in root) {
      delete root[controllerKey];
    }
  });
};

const bindTicketingCleanup = () => {
  if (hasBoundTicketingCleanup || !document.body) {
    return;
  }

  document.body.addEventListener("htmx:beforeCleanupElement", (event) => {
    destroyTicketingControllersWithin(event.target);
  });
  hasBoundTicketingCleanup = true;
};

export function initializeTicketingControllers(root = document) {
  bindTicketingCleanup();

  const { discountCodesRoot, paymentCurrencyInput, ticketTypesRoot, timezoneInput } =
    resolveTicketingControls(root);

  const discountCodesController = initializeDiscountCodesController({
    addButton: queryControlById(root, "add-discount-code-button"),
    currencyInput: paymentCurrencyInput,
    root: discountCodesRoot,
    timezoneInput,
  });
  const ticketTypesController = initializeTicketTypesController({
    addButton: queryControlById(root, "add-ticket-type-button"),
    currencyInput: paymentCurrencyInput,
    root: ticketTypesRoot,
    timezoneInput,
  });

  return {
    discountCodesController,
    ticketTypesController,
  };
}

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
  const { ticketTypesController } = initializeTicketingControllers(root);

  const syncWaitlistToggleState = () => {
    if (!toggleWaitlistEnabled || !waitlistEnabledInput || !capacityInput) {
      return;
    }

    const clearingTicketing = toggleClearTicketing?.checked === true;
    const hasTicketTypes =
      typeof ticketTypesController?.hasConfiguredTicketTypes === "function"
        ? ticketTypesController.hasConfiguredTicketTypes() && !clearingTicketing
        : false;
    const configuredSeatTotal =
      typeof ticketTypesController?.getConfiguredSeatTotal === "function"
        ? ticketTypesController.getConfiguredSeatTotal()
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

  if (toggleClearTicketing && clearTicketingInput) {
    toggleClearTicketing.addEventListener("change", () => {
      clearTicketingInput.value = String(toggleClearTicketing.checked);
      syncWaitlistToggleState();
    });
  }

  syncWaitlistToggleState();
}
