import { expect } from "../../../fixtures.js";

import { setupTicketOffer } from "../../../data-graphs/events.js";
import { routeNextRequestWithQuery, waitForActionResponse } from "../../../utils.js";
import { openGroupEventsTabWithEvent } from "./helpers.js";

/** Verifies and dismisses the error alert shown for a failed ticket allocation. */
export const expectErrorAlert = async (page, message) => {
  const popup = page.locator(".swal2-popup");
  await expect(popup).toHaveCount(1);
  await expect(popup).toContainText(message);
  await page.getByRole("button", { name: "OK" }).click();
  await expect(popup).toBeHidden();
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
export const openAttendeesTab = async (page, eventName, eventId, query = "") => {
  const eventRow = await openGroupEventsTabWithEvent(page, eventName);

  await waitForActionResponse(page, () => eventRow.locator('td button[aria-label^="Edit event:"]').click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${eventId}/update`,
  });

  // The tab buttons only exist once the event update form has loaded.
  const attendeesTab = page.locator('button[data-section="attendees"]');
  if (query !== "") {
    await routeNextRequestWithQuery(page, `/dashboard/group/events/${eventId}/attendees`, query);
  }

  await waitForActionResponse(page, () => attendeesTab.click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${eventId}/attendees`,
  });

  const attendeesContent = page.locator("#attendees-content");

  // Wait until the attendees tab has swapped in its table.
  await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();

  return attendeesContent;
};

/** Opens an event's invitation requests tab and returns the requests content locator. */
export const openInvitationRequestsTab = async (page, eventName, eventId) => {
  const eventRow = await openGroupEventsTabWithEvent(page, eventName);
  await waitForActionResponse(page, () => eventRow.locator('td button[aria-label^="Edit event:"]').click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${eventId}/update`,
  });
  await waitForActionResponse(
    page,
    () => page.locator('button[data-section="invitation-requests"]').click(),
    {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${eventId}/invitation-requests`,
    },
  );

  const requestsContent = page.locator("#invitation-requests-content");
  await expect(requestsContent.getByRole("table", { name: "Invitation requests" })).toBeVisible();

  return requestsContent;
};

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
  page.waitForResponse(
    (response) =>
      response.request().method() === "GET" &&
      response.url().includes(`/dashboard/group/events/${eventId}/${section}`) &&
      response.ok(),
  );
