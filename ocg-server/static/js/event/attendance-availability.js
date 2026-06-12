import { setElementHidden } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { getAttendanceControl, getAttendanceMeta } from "/static/js/event/attendance-dom.js";
import { restoreCheckoutModalControls } from "/static/js/event/attendance-view.js";
import "/static/js/event/attendance-ticket-card.js";

const TICKET_PRICE_BADGE_CLASSES = [
  "inline-flex",
  "w-fit",
  "shrink-0",
  "self-center",
  "rounded-full",
  "border",
  "border-green-800",
  "bg-green-100",
  "px-2",
  "py-0.5",
  "text-[11px]",
  "font-semibold",
  "text-green-800",
];
const TICKET_STATUS_CLASSES = ["bg-green-500", "bg-red-500", "bg-stone-300"];

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
 * Updates an attendance container's metadata from fresh availability.
 * @param {HTMLElement} container Attendance container element.
 * @param {Object} availability Public availability payload.
 */
const updateAvailabilityMeta = (container, availability) => {
  container.dataset.attendeeApprovalRequired = String(availability.attendee_approval_required === true);
  container.dataset.attendeeMeetingAccessOpen = String(availability.is_live === true);
  container.dataset.canceled = String(availability.canceled === true);
  container.dataset.isPast = String(availability.is_past === true);
  container.dataset.isTicketed = String(availability.is_ticketed === true);
  container.dataset.ticketPurchaseAvailable = String(availability.has_sellable_ticket_types === true);
  container.dataset.waitlistEnabled = String(availability.waitlist_enabled === true);

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
  const priceLabel = getAvailabilityStringValue(ticket.current_price_label);
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
 * Updates a ticket status label and marker from fresh availability.
 * @param {HTMLInputElement} option Ticket radio input.
 * @param {Object} ticket Public ticket availability payload.
 * @returns {boolean} Whether the ticket is currently sellable.
 */
const renderTicketAvailability = (option, ticket) => {
  const card = option.closest('[data-attendance-role="ticket-type-card"]');
  const cardBody = card?.querySelector('[data-attendance-role="ticket-type-card-body"]');
  const statusDot = card?.querySelector('[data-attendance-role="ticket-type-status-dot"]');
  const statusLabel = card?.querySelector('[data-attendance-role="ticket-type-status-label"]');
  const hasCurrentPriceBadge = renderTicketPriceBadge(card, ticket);
  const isSellableNow = ticket.is_sellable_now === true && hasCurrentPriceBadge;

  option.dataset.ticketPurchasable = String(isSellableNow);
  if (!isSellableNow && option.checked) {
    option.checked = false;
  }

  if (cardBody instanceof HTMLElement) {
    cardBody.classList.toggle("bg-white", isSellableNow);
    cardBody.classList.toggle("cursor-pointer", isSellableNow);
    cardBody.classList.toggle("hover:border-primary-300", isSellableNow);
    cardBody.classList.toggle("bg-stone-50", !isSellableNow);
    cardBody.classList.toggle("cursor-not-allowed", !isSellableNow);
    cardBody.classList.toggle("opacity-60", !isSellableNow);
  }

  if (statusDot instanceof HTMLElement) {
    statusDot.classList.remove(...TICKET_STATUS_CLASSES);
    if (ticket.sold_out === true) {
      statusDot.classList.add("bg-red-500");
    } else if (isSellableNow) {
      statusDot.classList.add("bg-green-500");
    } else {
      statusDot.classList.add("bg-stone-300");
    }
  }

  if (statusLabel instanceof HTMLElement) {
    if (ticket.sold_out === true) {
      statusLabel.textContent = "Sold out";
    } else if (isSellableNow) {
      statusLabel.textContent = "Available now";
    } else if (!isSellableNow) {
      statusLabel.textContent = "Not on sale";
    }
  }

  return isSellableNow;
};

/**
 * Creates a ticket card for availability entries missing from cached markup.
 * @param {HTMLElement} container Attendance container element.
 * @param {Object} ticket Public ticket availability payload.
 * @param {{canceled: boolean, ticketPurchaseAvailable: boolean}} meta Attendance metadata.
 * @returns {HTMLInputElement|null} The created ticket option, if any.
 */
const createTicketAvailabilityCard = (container, ticket, meta) => {
  if (ticket.active === false) {
    return null;
  }

  const ticketTypeList = getAttendanceControl(container, "ticket-type-list");
  const eventTicketTypeId = getAvailabilityStringValue(ticket.event_ticket_type_id);
  if (!(ticketTypeList instanceof HTMLElement) || !eventTicketTypeId) {
    return null;
  }

  const card = document.createElement("attendance-ticket-card");
  card.ticket = ticket;
  card.canceled = meta.canceled;
  card.ticketPurchaseAvailable = meta.ticketPurchaseAvailable;
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

    const ticket = ticketsById.get(option.value) || {
      event_ticket_type_id: option.value,
      is_sellable_now: false,
      sold_out: false,
    };
    const isSellableNow = renderTicketAvailability(option, ticket);
    option.disabled = meta.canceled || !meta.ticketPurchaseAvailable || !isSellableNow;
  });

  restoreCheckoutModalControls(container);
};
