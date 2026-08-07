import { localizeCurrencyLabel } from "/static/js/common/currency.js";
import { setElementHidden } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { getAttendanceControl, getAttendanceMeta } from "/static/js/event/attendance-dom.js";
import {
  applyTicketCardState,
  deriveTicketCardState,
  TICKET_PRICE_BADGE_CLASSES,
} from "/static/js/event/attendance-ticket-state.js";
import { restoreCheckoutModalControls } from "/static/js/event/attendance-ticket-view.js";
import "/static/js/event/attendance-ticket-card.js";

/**
 * Returns a trimmed string value from an availability payload field.
 * @param {unknown} value Availability payload field.
 * @returns {string} Trimmed field value, or an empty string.
 */
export const getAvailabilityStringValue = (value) => (typeof value === "string" ? value.trim() : "");

/**
 * Returns true when a payload value is a finite number.
 * @param {unknown} value Payload value.
 * @returns {boolean} Whether the value is numeric.
 */
export const isFiniteNumberValue = (value) =>
  value !== null && value !== undefined && Number.isFinite(Number(value));

/**
 * Loads fresh public availability for the event page.
 * @param {HTMLElement} container Attendance container element.
 * @returns {Promise<Object|null>} Availability payload, or null when unavailable.
 */
export const fetchAttendanceAvailability = async (container) => {
  const availabilityUrl = container?.dataset?.availabilityUrl;
  if (!availabilityUrl) {
    return null;
  }

  const response = await ocgFetch(availabilityUrl, {
    cache: "no-store",
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    throw new Error("failed to load availability");
  }

  return response.json();
};

/**
 * Applies a fresh public availability payload to the event page.
 * @param {HTMLElement} container Attendance container element.
 * @param {Object} availability Public availability payload.
 * @returns {void}
 */
export const renderAttendanceAvailability = (container, availability) => {
  updateAvailabilityMeta(container, availability);
  renderAvailabilityCaptions(availability);
  renderRegistrationWindowMessage(availability);
  renderAvailabilityRibbon(availability);
  renderTicketAvailabilities(container, availability.ticket_types || []);
};

/**
 * Toggles an availability caption's responsive display classes.
 * @param {string} caption Availability caption key.
 * @param {boolean} visible Whether the caption should be visible.
 * @param {string[]} displayClasses Classes used when visible.
 */
const renderAvailabilityCaption = (caption, visible, displayClasses) => {
  document.querySelectorAll(`[data-availability-caption="${caption}"]`).forEach((node) => {
    setElementHidden(node, !visible);
    displayClasses.forEach((className) => {
      node.classList.toggle(className, visible);
    });
    node.classList.toggle("opacity-0", !visible);
    if (visible) {
      const fadeCaptionIn = () => node.classList.add("opacity-100");
      if (typeof window.requestAnimationFrame === "function") {
        window.requestAnimationFrame(fadeCaptionIn);
      } else {
        fadeCaptionIn();
      }
    } else {
      node.classList.remove("opacity-100");
    }
  });
};

/**
 * Updates the public attendance, capacity and waitlist counters.
 * @param {Object} availability Public availability payload.
 */
const renderAvailabilityCaptions = (availability) => {
  const attendeeCount = Number(availability?.attendee_count);
  const capacity = Number(availability?.capacity);
  const remainingCapacity = Number(availability?.remaining_capacity);
  const waitlistCount = Number(availability?.waitlist_count);
  const hasCapacity = isFiniteNumberValue(availability?.capacity);
  const hasAttendeeCount =
    !hasCapacity && isFiniteNumberValue(availability?.attendee_count) && attendeeCount > 0;
  const hasRemainingCapacity = isFiniteNumberValue(availability?.remaining_capacity) && remainingCapacity > 0;
  const hasWaitlistCount =
    isFiniteNumberValue(availability?.remaining_capacity) &&
    remainingCapacity <= 0 &&
    isFiniteNumberValue(availability?.waitlist_count) &&
    waitlistCount > 0;

  document.querySelectorAll("[data-availability-capacity]").forEach((node) => {
    node.textContent = hasCapacity ? String(capacity) : "";
  });
  document.querySelectorAll("[data-availability-attendee-count]").forEach((node) => {
    node.textContent = hasAttendeeCount ? String(attendeeCount) : "";
  });
  document.querySelectorAll("[data-availability-remaining]").forEach((node) => {
    node.textContent = hasRemainingCapacity ? String(remainingCapacity) : "";
  });
  document.querySelectorAll("[data-availability-waitlist]").forEach((node) => {
    node.textContent = hasWaitlistCount ? String(waitlistCount) : "";
  });
  renderAvailabilityCaption("attendees", hasAttendeeCount, ["flex"]);
  renderAvailabilityCaption("capacity", hasCapacity, ["flex"]);
  renderAvailabilityCaption("remaining", hasRemainingCapacity, ["inline"]);
  renderAvailabilityCaption("waitlist", hasWaitlistCount, ["inline"]);
};

/**
 * Updates the public sold-out ribbon from fresh availability.
 * @param {Object} availability Public availability payload.
 */
const renderAvailabilityRibbon = (availability) => {
  const capacity = Number(availability?.capacity);
  const remainingCapacity = Number(availability?.remaining_capacity);
  const isSoldOut =
    availability?.canceled !== true &&
    isFiniteNumberValue(availability?.capacity) &&
    capacity > 0 &&
    isFiniteNumberValue(availability?.remaining_capacity) &&
    remainingCapacity <= 0;

  document.querySelectorAll("[data-availability-sold-out-ribbon]").forEach((node) => {
    setElementHidden(node, !isSoldOut);
  });
};

/**
 * Updates the public registration window message.
 * @param {Object} availability Public availability payload.
 */
const renderRegistrationWindowMessage = (availability) => {
  const message = getAvailabilityStringValue(availability?.registration_window_message);

  document.querySelectorAll("[data-registration-window-message-display]").forEach((node) => {
    const container = node.closest("[data-registration-window-message-container]") || node;
    const datePanel = node.closest("[data-registration-window-date-panel]");
    node.textContent = message;
    if (message) {
      container.title = message;
    } else {
      container.removeAttribute("title");
    }
    datePanel?.classList?.toggle("justify-center", !message);
    setElementHidden(container, !message);
  });
};

/**
 * Updates an attendance container's metadata from fresh availability.
 * @param {HTMLElement} container Attendance container element.
 * @param {Object} availability Public availability payload.
 */
const updateAvailabilityMeta = (container, availability) => {
  container.dataset.attendeeApprovalRequired = String(availability.attendee_approval_required === true);
  container.dataset.attendeeMeetingAccessOpen = String(availability.is_live === true);
  container.dataset.canceled = String(availability.canceled === true);
  container.dataset.hasSoldOutTicketTypes = String(availability.has_sold_out_ticket_types === true);
  container.dataset.hasVisibleTicketTypes = String(availability.has_visible_ticket_types === true);
  container.dataset.isPast = String(availability.is_past === true);
  container.dataset.isSimpleRsvp = String(availability.is_simple_rsvp === true);
  container.dataset.paidCapable = String(availability.paid_capable === true);
  container.dataset.registrationWindowOpen = String(availability.registration_window_open !== false);
  container.dataset.ticketPurchaseAvailable = String(availability.has_sellable_ticket_types === true);
  container.dataset.ticketIsFreeOnly = String(availability.has_only_free_ticket_types === true);
  container.dataset.waitlistEnabled = String(availability.waitlist_enabled === true);

  const registrationMessage = getAvailabilityStringValue(availability.registration_window_message);
  if (registrationMessage) {
    container.dataset.registrationWindowMessage = registrationMessage;
  } else {
    delete container.dataset.registrationWindowMessage;
  }

  const registrationUnavailableTitle = getAvailabilityStringValue(
    availability.registration_window_unavailable_title,
  );
  if (registrationUnavailableTitle) {
    container.dataset.registrationWindowUnavailableTitle = registrationUnavailableTitle;
  } else {
    delete container.dataset.registrationWindowUnavailableTitle;
  }

  if (isFiniteNumberValue(availability.capacity)) {
    container.dataset.capacity = String(availability.capacity);
  } else {
    delete container.dataset.capacity;
  }

  if (isFiniteNumberValue(availability.remaining_capacity)) {
    container.dataset.remainingCapacity = String(availability.remaining_capacity);
  } else {
    delete container.dataset.remainingCapacity;
  }
};

/**
 * Updates a ticket price badge from fresh availability.
 * @param {HTMLElement|null|undefined} card Ticket card element.
 * @param {Object} ticket Public ticket availability payload.
 * @returns {boolean} True when the card displays a current price badge.
 */
const renderTicketPriceBadge = (card, ticket) => {
  const priceLabel = localizeCurrencyLabel(getAvailabilityStringValue(ticket.current_price_label));
  const priceBadge = card?.querySelector('[data-attendance-role="ticket-type-price-badge"]');
  const summary = card?.querySelector('[data-attendance-role="ticket-type-summary"]');

  if (!priceLabel) {
    priceBadge?.remove();
    return false;
  }

  if (priceBadge instanceof HTMLElement) {
    priceBadge.textContent = priceLabel;
    return true;
  }

  if (!(summary instanceof HTMLElement)) {
    return false;
  }

  const nextPriceBadge = document.createElement("div");
  nextPriceBadge.dataset.attendanceRole = "ticket-type-price-badge";
  nextPriceBadge.classList.add(...TICKET_PRICE_BADGE_CLASSES);
  nextPriceBadge.textContent = priceLabel;
  summary.append(nextPriceBadge);
  return true;
};

/**
 * Updates a ticket description from fresh availability.
 * @param {HTMLElement|null|undefined} card Ticket card element.
 * @param {Object} ticket Public ticket availability payload.
 * @returns {void}
 */
const renderTicketDescription = (card, ticket) => {
  const descriptionText = getAvailabilityStringValue(ticket.description);
  const currentDescription = card?.querySelector('[data-attendance-role="ticket-type-description"]');
  if (!descriptionText) {
    currentDescription?.remove();
    return;
  }

  if (currentDescription instanceof HTMLElement) {
    currentDescription.textContent = descriptionText;
    return;
  }

  const statusLabel = card?.querySelector('[data-attendance-role="ticket-type-status-label"]');
  const statusRow = statusLabel?.closest("div");
  if (!(statusRow instanceof HTMLElement)) {
    return;
  }

  const nextDescription = document.createElement("p");
  nextDescription.dataset.attendanceRole = "ticket-type-description";
  nextDescription.className = "col-start-2 form-legend min-w-0";
  nextDescription.textContent = descriptionText;
  statusRow.before(nextDescription);
};

/**
 * Updates a ticket status label and marker from fresh availability.
 * @param {HTMLInputElement} option Ticket radio input.
 * @param {Object} ticket Public ticket availability payload.
 * @param {object} meta Attendance metadata.
 * @param {boolean} meta.attendeeApprovalRequired Whether approval is required.
 * @param {boolean} meta.canceled Whether the event is canceled.
 * @param {boolean} meta.registrationWindowOpen Whether registration is open.
 * @param {boolean} meta.ticketPurchaseAvailable Whether tickets can be purchased.
 * @param {boolean} meta.waitlistEnabled Whether the waitlist is enabled.
 * @returns {boolean} Whether the ticket is currently selectable.
 */
const renderTicketAvailability = (option, ticket, meta) => {
  const card = option.closest('[data-attendance-role="ticket-type-card"]');
  const title = card?.querySelector('[data-attendance-role="ticket-type-title"]');
  const state = deriveTicketCardState(ticket, meta);

  renderTicketPriceBadge(card, ticket);
  if (title instanceof HTMLElement) {
    title.textContent = getAvailabilityStringValue(ticket.title) || "Ticket";
  }
  renderTicketDescription(card, ticket);
  applyTicketCardState(option, state);

  return state.selectable;
};

/**
 * Creates a ticket card for availability entries missing from cached markup.
 * @param {HTMLElement} container Attendance container element.
 * @param {Object} ticket Public ticket availability payload.
 * @param {object} meta Attendance metadata.
 * @param {boolean} meta.attendeeApprovalRequired Whether approval is required.
 * @param {boolean} meta.canceled Whether the event is canceled.
 * @param {boolean} meta.registrationWindowOpen Whether registration is open.
 * @param {boolean} meta.ticketPurchaseAvailable Whether tickets can be purchased.
 * @param {boolean} meta.waitlistEnabled Whether the waitlist is enabled.
 * @returns {HTMLInputElement|null} The created ticket option, if any.
 */
const createTicketAvailabilityCard = (container, ticket, meta) => {
  if (ticket.active === false || !getAvailabilityStringValue(ticket.current_price_label)) {
    return null;
  }

  const ticketTypeList = getAttendanceControl(container, "ticket-type-list");
  const eventTicketTypeId = getAvailabilityStringValue(ticket.event_ticket_type_id);
  if (!(ticketTypeList instanceof HTMLElement) || !eventTicketTypeId) {
    return null;
  }

  const card = document.createElement("attendance-ticket-card");
  card.ticket = ticket;
  card.attendeeApprovalRequired = meta.attendeeApprovalRequired;
  card.canceled = meta.canceled;
  card.registrationWindowOpen = meta.registrationWindowOpen;
  card.ticketPurchaseAvailable = meta.ticketPurchaseAvailable;
  card.waitlistEnabled = meta.waitlistEnabled;
  card.addEventListener("change", () => {
    restoreCheckoutModalControls(container);
  });
  ticketTypeList.append(card);
  card.performUpdate?.();

  return card.querySelector('[data-attendance-role="ticket-type-option"]');
};

/**
 * Updates ticket controls from fresh availability.
 * @param {HTMLElement} container Attendance container element.
 * @param {Object[]} ticketTypes Public ticket availability payloads.
 */
const renderTicketAvailabilities = (container, ticketTypes = []) => {
  const meta = getAttendanceMeta(container);
  const ticketsById = new Map(ticketTypes.map((ticket) => [String(ticket.event_ticket_type_id), ticket]));
  const existingTicketIds = new Set(
    Array.from(container.querySelectorAll('[data-attendance-role="ticket-type-option"]'))
      .filter((option) => option instanceof HTMLInputElement)
      .map((option) => option.value),
  );

  ticketTypes.forEach((ticket) => {
    const eventTicketTypeId = getAvailabilityStringValue(ticket.event_ticket_type_id);
    if (eventTicketTypeId && !existingTicketIds.has(eventTicketTypeId)) {
      const option = createTicketAvailabilityCard(container, ticket, meta);
      if (option instanceof HTMLInputElement) {
        existingTicketIds.add(option.value);
      }
    }
  });

  container.querySelectorAll('[data-attendance-role="ticket-type-option"]').forEach((option) => {
    if (!(option instanceof HTMLInputElement)) {
      return;
    }

    const ticket = ticketsById.get(option.value);
    if (!ticket) {
      option.closest('[data-attendance-role="ticket-type-card"]')?.remove();
      return;
    }

    renderTicketAvailability(option, ticket, meta);
  });

  restoreCheckoutModalControls(container);
};
