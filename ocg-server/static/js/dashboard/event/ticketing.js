import { getElementById } from "/static/js/common/dom.js";

/**
 * Collects the shared event enrollment controls used across the form.
 * @param {Document|Element} [root=document] Root container
 * @returns {{
 *   attendeeApprovalRequiredInput: HTMLElement|null,
 *   attendeeApprovalToggleLabel: HTMLElement|null,
 *   discountCodesRoot: HTMLElement|null,
 *   paymentCurrencyInput: HTMLElement|null,
 *   ticketTypesRoot: HTMLElement|null,
 *   timezoneInput: HTMLElement|null,
 *   toggleAttendeeApprovalRequired: HTMLElement|null,
 *   toggleWaitlistEnabled: HTMLElement|null,
 *   waitlistEnabledInput: HTMLElement|null,
 *   waitlistToggleLabel: HTMLElement|null
 * }}
 */
const resolveEventEnrollmentControls = (root = document) => ({
  attendeeApprovalRequiredInput: getElementById(root, "attendee_approval_required"),
  attendeeApprovalToggleLabel: root.querySelector('[data-enrollment-toggle-label="attendee-approval"]'),
  discountCodesRoot: getElementById(root, "discount-codes-ui"),
  paymentCurrencyInput: getElementById(root, "payment_currency_code"),
  ticketTypesRoot: getElementById(root, "ticket-types-ui"),
  timezoneInput: root.querySelector('[name="timezone"]'),
  toggleAttendeeApprovalRequired: getElementById(root, "toggle_attendee_approval_required"),
  toggleWaitlistEnabled: getElementById(root, "toggle_waitlist_enabled"),
  waitlistEnabledInput: getElementById(root, "waitlist_enabled"),
  waitlistToggleLabel: root.querySelector('[data-enrollment-toggle-label="waitlist"]'),
});

/**
 * Synchronizes event enrollment controls and derived form state.
 * @param {Document|Element} [root=document] Root container
 * @returns {void}
 */
export function initializeEventEnrollmentState(root = document) {
  const {
    attendeeApprovalRequiredInput,
    attendeeApprovalToggleLabel,
    paymentCurrencyInput,
    ticketTypesRoot,
    toggleAttendeeApprovalRequired,
    toggleWaitlistEnabled,
    waitlistEnabledInput,
    waitlistToggleLabel,
  } = resolveEventEnrollmentControls(root);
  const ticketTypesEditor = ticketTypesRoot;

  const syncPaymentCurrencyValidity = (hasTicketTypes) => {
    if (!paymentCurrencyInput) {
      return;
    }

    const hasPositivePrices =
      typeof ticketTypesEditor?.hasConfiguredPositivePrices === "function"
        ? ticketTypesEditor.hasConfiguredPositivePrices()
        : false;
    const requiresCurrency = hasTicketTypes && hasPositivePrices && !paymentCurrencyInput.disabled;
    const hasCurrency = paymentCurrencyInput.value.trim() !== "";

    paymentCurrencyInput.required = requiresCurrency;
    paymentCurrencyInput.setCustomValidity(
      requiresCurrency && !hasCurrency ? "Paid ticket prices require an event currency." : "",
    );
  };

  const syncEventEnrollmentState = () => {
    const hasTicketTypes =
      typeof ticketTypesEditor?.hasConfiguredTicketTypes === "function"
        ? ticketTypesEditor.hasConfiguredTicketTypes()
        : false;
    syncPaymentCurrencyValidity(hasTicketTypes);

    if (!toggleWaitlistEnabled || !waitlistEnabledInput) {
      return;
    }

    const configuredSeatTotal =
      typeof ticketTypesEditor?.getConfiguredSeatTotal === "function"
        ? ticketTypesEditor.getConfiguredSeatTotal()
        : null;

    const capacityIsValid =
      hasTicketTypes && Number.isFinite(configuredSeatTotal) && configuredSeatTotal >= 0;
    const attendeeApprovalRequired = toggleAttendeeApprovalRequired?.checked === true;
    const canEnableWaitlist = capacityIsValid && !attendeeApprovalRequired;
    const canRequireApproval = !toggleWaitlistEnabled.checked;

    if (toggleAttendeeApprovalRequired && attendeeApprovalRequiredInput) {
      toggleAttendeeApprovalRequired.disabled = !canRequireApproval;
      if (!canRequireApproval) {
        toggleAttendeeApprovalRequired.checked = false;
        attendeeApprovalRequiredInput.value = "false";
      } else {
        attendeeApprovalRequiredInput.value = String(toggleAttendeeApprovalRequired.checked);
      }
    }

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

    if (attendeeApprovalToggleLabel) {
      attendeeApprovalToggleLabel.classList.toggle("cursor-pointer", canRequireApproval);
      attendeeApprovalToggleLabel.classList.toggle("cursor-not-allowed", !canRequireApproval);
      attendeeApprovalToggleLabel.classList.toggle("opacity-50", !canRequireApproval);
    }
  };

  if (toggleAttendeeApprovalRequired && attendeeApprovalRequiredInput) {
    toggleAttendeeApprovalRequired.addEventListener("change", () => {
      attendeeApprovalRequiredInput.value = String(toggleAttendeeApprovalRequired.checked);
      syncEventEnrollmentState();
    });
  }

  if (toggleWaitlistEnabled && waitlistEnabledInput) {
    toggleWaitlistEnabled.addEventListener("change", () => {
      waitlistEnabledInput.value = String(toggleWaitlistEnabled.checked);
      syncEventEnrollmentState();
    });
  }

  if (ticketTypesRoot) {
    ticketTypesRoot.addEventListener("ticket-types-changed", syncEventEnrollmentState);
  }

  if (paymentCurrencyInput) {
    paymentCurrencyInput.addEventListener("input", syncEventEnrollmentState);
    paymentCurrencyInput.addEventListener("change", syncEventEnrollmentState);
  }

  syncEventEnrollmentState();
}
