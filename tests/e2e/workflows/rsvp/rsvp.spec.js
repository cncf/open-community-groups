import { expect, test } from "../../fixtures.js";

import {
  createApprovalRequiredEvent,
  deleteEventFromList,
} from "../../dashboard/group/events/helpers.js";
import {
  buildE2eUrl,
  navigateToPath,
  TEST_COMMUNITY_NAME,
  TEST_USER_IDS,
  waitForActionResponse,
} from "../../utils.js";

test.describe("rsvp approval workflow", () => {
  test("approved RSVP requests are claimed through checkout", async ({
    organizerGroupPage,
    pending1Page,
  }) => {
    const eventName = `E2E Approved RSVP Claim ${Date.now()}`;
    const { eventId } = await createApprovalRequiredEvent(
      organizerGroupPage,
      eventName,
    );

    try {
      // Create and approve a tier-scoped RSVP request.
      const requestResponse = await pending1Page.request.post(
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
        { form: {} },
      );
      expect(requestResponse.ok()).toBeTruthy();
      const approvalResponse = await organizerGroupPage.request.put(
        buildE2eUrl(
          `/dashboard/group/events/${eventId}/attendees/${TEST_USER_IDS.pending1}/invitation-request/accept`,
        ),
        { form: {} },
      );
      expect(approvalResponse.ok()).toBeTruthy();

      // Claim the approved RSVP offer through the unified checkout endpoint.
      await navigateToPath(pending1Page, "/dashboard/user?tab=invitations");
      const approvedOfferRow = pending1Page
        .locator("#dashboard-content tr")
        .filter({ hasText: eventName });
      await expect(approvedOfferRow).toContainText("RSVP request approved");
      await approvedOfferRow.getByLabel(/Open offer actions/).click();
      await approvedOfferRow
        .getByRole("menuitem", { name: "Claim offer" })
        .click();
      const claimModal = pending1Page.getByRole("dialog", {
        name: "Claim offer",
      });
      await expect(claimModal).toBeVisible();
      await waitForActionResponse(
        pending1Page,
        () => claimModal.getByRole("button", { name: "Claim offer", exact: true }).click(),
        {
          method: "POST",
          urlIncludes: `/event/${eventId}/checkout`,
        },
      );
      await expect(approvedOfferRow).toHaveCount(0);
    } finally {
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });
});
