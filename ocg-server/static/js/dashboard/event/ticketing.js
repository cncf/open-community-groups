import { getElementById } from "/static/js/common/dom.js";

const PAID_EVENT_KINDS = new Set(["hybrid", "in-person"]);
const PAID_VENUE_FIELDS = [
  {
    inputName: "venue_name",
    message: "Paid tickets require a venue name.",
    valueName: "venue_name",
  },
  {
    inputName: "venue_address",
    message: "Paid tickets require a venue address.",
    valueName: "venue_address",
  },
  {
    inputName: "venue_city",
    message: "Paid tickets require a venue city.",
    valueName: "venue_city",
  },
  {
    inputName: "venue_zip_code",
    message: "Paid tickets require a venue postal code.",
    valueName: "venue_zip_code",
  },
  {
    inputName: "venue_country_name",
    message: "Paid tickets require a country selected from the location search results.",
    valueName: "venue_country_code",
  },
];
const PAID_VENUE_FIELD_NAMES = new Set(
  PAID_VENUE_FIELDS.flatMap(({ inputName, valueName }) => [inputName, valueName]),
);

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
 * @returns {() => void} Enrollment state synchronization callback.
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

  const syncPaidEventRequirements = () => {
    const hasPositivePrices =
      typeof ticketTypesEditor?.hasConfiguredPositivePrices === "function"
        ? ticketTypesEditor.hasConfiguredPositivePrices()
        : false;
    const kindInput = getElementById(root, "kind_id");
    const hasEligibleKind = PAID_EVENT_KINDS.has(kindInput?.value || "");

    kindInput?.setCustomValidity(
      hasPositivePrices && !hasEligibleKind ? "Paid tickets require an in-person or hybrid event." : "",
    );

    for (const requirement of PAID_VENUE_FIELDS) {
      const input = root.querySelector(`[name="${requirement.inputName}"]`);
      if (!input || typeof input.setCustomValidity !== "function") {
        continue;
      }

      const requiresCompleteVenue = hasPositivePrices && hasEligibleKind;
      const valueInput = root.querySelector(`[name="${requirement.valueName}"]`);
      const hasValue = valueInput?.value.trim() !== "";

      input.required = requiresCompleteVenue && requirement.inputName === requirement.valueName;
      input.setCustomValidity(requiresCompleteVenue && !hasValue ? requirement.message : "");
    }
  };

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
    syncPaidEventRequirements();

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

  root.addEventListener("input", (event) => {
    if (PAID_VENUE_FIELD_NAMES.has(event.target?.name)) {
      syncEventEnrollmentState();
    }
  });

  syncEventEnrollmentState();
  return syncEventEnrollmentState;
}
