import { parseJsonText } from "/static/js/common/utils.js";

// Maps capacity conflicts from ticket allocation to organizer guidance.
const TICKET_ALLOCATION_CONFLICT_MESSAGES = {
  "queue-has-priority":
    "The remaining seats for this ticket type were offered to people on the waiting list. Add seats to allocate another ticket.",
  "ticket-type-sold-out":
    "This ticket type is sold out. Add seats or cancel a pending offer before allocating another ticket.",
};

/**
 * Resolves organizer guidance for a ticket allocation capacity conflict.
 * @param {XMLHttpRequest|undefined|null} xhr HTMX response XHR.
 * @returns {string|null} Conflict guidance, or null for other responses.
 */
export const getTicketAllocationConflictMessage = (xhr) => {
  if (xhr?.status !== 409) {
    return null;
  }

  const conflict = parseJsonText(xhr.responseText, {})?.conflict;
  return Object.hasOwn(TICKET_ALLOCATION_CONFLICT_MESSAGES, conflict)
    ? TICKET_ALLOCATION_CONFLICT_MESSAGES[conflict]
    : null;
};
