import { expect } from "../../../fixtures.js";

import { setupTicketOffer } from "../../../data-graphs/events.js";
import { dismissAlert, waitForActionResponse, waitForResponseMatching } from "../../../utils.js";
import { openEventSection } from "./helpers.js";

// Error shown when an organizer allocates a ticket in a sold-out tier.
const SOLD_OUT_CONFLICT_MESSAGE =
  "This ticket type is sold out. Add seats or cancel a pending offer before allocating another ticket.";

/**
 * Runs a ticket allocation against a tier that sold out after the page rendered, waits for its
 * 409 conflict response and dismisses the sold-out alert.
 * @param {import("@playwright/test").Page} page - Organizer page.
 * @param {() => Promise<unknown>|unknown} action - Click that sends the allocation request.
 * @param {{ matcher: object }} options - `waitForActionResponse` matcher without the status, which
 *   is pinned to 409.
 */
export const expectStaleCapacityConflict = async (page, action, { matcher }) => {
  await waitForActionResponse(page, action, { ...matcher, status: 409 });
  await dismissAlert(page, { message: SOLD_OUT_CONFLICT_MESSAGE });
};

/** Returns visible status badges matching the supplied text within a root locator. */
export const getVisibleStatusBadge = (root, text) =>
  root.locator(".custom-badge").filter({ hasText: text }).filter({ visible: true });

/** Reserves one seat in a ticket tier with a pending organizer invitation. */
export const holdSeat = (event, ticketTypeKey, userId) => {
  setupTicketOffer({
    eventId: event.eventId,
    source: "organizer_invitation",
    status: "pending",
    ticketTypeId: event.ticketTypeIds[ticketTypeKey],
    userId,
  });
};

/** Opens an event's attendees tab and returns the attendees content locator. */
export const openAttendeesTab = (page, eventName, eventId, query = "") =>
  openEventSection(page, {
    contentSelector: "#attendees-content",
    eventId,
    eventName,
    query,
    section: "attendees",
    tableName: "Attendees list",
  });

/** Opens an event's invitation requests tab and returns the requests content locator. */
export const openInvitationRequestsTab = (page, eventName, eventId) =>
  openEventSection(page, {
    contentSelector: "#invitation-requests-content",
    eventId,
    eventName,
    section: "invitation-requests",
    tableName: "Invitation requests",
  });

/** Submits the attendee invitation modal for one user and returns the modal locator. */
export const submitAttendeeInvitation = async (
  page,
  attendeesContent,
  eventId,
  { name, username },
  status = 201,
) => {
  // Open the invitation modal from the attendee actions menu.
  await attendeesContent.getByRole("button", { name: "Open attendee actions menu" }).click();
  await attendeesContent.getByRole("menuitem", { name: "Invite attendee" }).click();
  const modal = page.locator("#attendee-invitation-modal");
  await expect(modal).toBeVisible();

  // Select the user from the search results.
  const searchField = modal.locator("user-search-field[data-attendee-invitation-search]");
  await searchField.locator("#attendee-invitation-search-input").fill(username);
  await searchField.getByText(name).click();
  await expect(modal.locator("#attendee-invitation-selected-user")).toContainText(name);

  // Submit the invitation and require the expected response status.
  await waitForActionResponse(page, () => modal.locator("#submit-attendee-invitation").click(), {
    method: "POST",
    urlIncludes: `/dashboard/group/events/${eventId}/attendees/invite`,
    status,
  });

  return modal;
};

/** Returns a promise for the next successful refresh of one event editor section. */
export const waitForEventSectionRefresh = (page, eventId, section) =>
  waitForResponseMatching(page, {
    method: "GET",
    pathname: `/dashboard/group/events/${eventId}/${section}`,
    status: 200,
  });
