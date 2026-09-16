import { expect } from "../../../fixtures.js";

import { routeNextRequestWithQuery, waitForActionResponse } from "../../../utils.js";
import { openGroupEventsTabWithEvent } from "./helpers.js";

/** Returns visible status badges matching the supplied text within a root locator. */
export const getVisibleStatusBadge = (root, text) =>
  root.locator(".custom-badge").filter({ hasText: text }).filter({ visible: true });

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
