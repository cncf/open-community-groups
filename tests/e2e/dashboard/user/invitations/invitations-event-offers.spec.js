import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_IDS,
  TEST_GROUP_SLUGS,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_TICKETING_EVENTS,
  TEST_USER_IDS,
} from "../../../seed.js";
import { buildE2eUrl, waitForActionResponse } from "../../../utils.js";
import { clearEventAttendeeState, ensureEventInvitation, openUserDashboardPath } from "../helpers.js";
import { openEventOfferActions } from "./helpers.js";

const ENDED_PRICE_APPROVAL_OFFER_ID = "59555555-5555-5555-5555-555555555923";

const ENDED_PRICE_WAITLIST_OFFER_ID = "59555555-5555-5555-6555-555555555923";

test.describe("user dashboard invitations view — event offers", () => {
  test("paid offer claims normalize discounts and follow checkout redirects", async ({ pending1Page }) => {
    const event = TEST_TICKETING_EVENTS.paidOffers;

    // Open the seeded paid offer and launch its claim modal.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);
    const offerRow = pending1Page.locator("#dashboard-content tr", {
      hasText: event.name,
    });
    await expect(offerRow).toContainText("Private paid offer");
    await openEventOfferActions(offerRow);
    await offerRow.getByRole("menuitem", { name: "Claim offer" }).click();

    // Fill the claim modal with a padded discount code.
    const claimModal = pending1Page.getByRole("dialog", {
      name: "Claim offer",
    });
    const discountInput = claimModal.getByRole("textbox", {
      name: "Discount code (optional)",
    });
    await expect(discountInput).toBeVisible();
    await discountInput.fill("  OFFER25  ");

    // Return a local redirect so the browser handoff can be asserted deterministically.
    const checkoutUrl = `**/event/${event.id}/checkout`;
    await pending1Page.route(checkoutUrl, async (route) => {
      await route.fulfill({
        body: JSON.stringify({
          redirect_url:
            `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${event.slug}` +
            "?checkout=redirected",
        }),
        contentType: "application/json",
        status: 200,
      });
    });

    try {
      // Submit the claim and capture its checkout request payload.
      const checkoutRequest = pending1Page.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes(`/event/${event.id}/checkout`),
      );
      await Promise.all([
        pending1Page.waitForURL(/checkout=redirected/u),
        claimModal.getByRole("button", { name: "Claim offer", exact: true }).click(),
      ]);
      const requestData = new URLSearchParams((await checkoutRequest).postData() ?? "");

      // Verify the offer and trimmed discount reach the unified checkout endpoint.
      expect(requestData.get("discount_code")).toBe("OFFER25");
      expect(requestData.get("event_ticket_type_id")).toBe("56555555-5555-5555-5555-555555555916");
      expect(requestData.get("admission_offer_id")).not.toBeNull();
      await expect(pending1Page).toHaveURL(/checkout=redirected/u);
    } finally {
      // Remove the checkout route override.
      await pending1Page.unroute(checkoutUrl);
    }
  });

  test("approval snapshots remain claimable after sales end while waitlist offers do not", async ({
    pending1Page,
    pending2Page,
  }) => {
    const event = TEST_REGISTRATION_WINDOW_EVENTS.priceEnded;

    // Restore both offers before comparing their ended-price behavior.
    resetEndedPriceOffers();

    try {
      // The approval offer keeps its stored free price after the live window ends.
      await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);
      const approvalOfferRow = pending1Page.locator("#dashboard-content tr", {
        hasText: event.name,
      });
      await expect(approvalOfferRow).toContainText("Ticket request approved");
      await expect(approvalOfferRow.getByText("Free", { exact: true })).toBeVisible();
      await openEventOfferActions(approvalOfferRow);
      await approvalOfferRow.getByRole("menuitem", { name: "Claim offer" }).click();
      const approvalClaimModal = pending1Page.getByRole("dialog", {
        name: "Claim offer",
      });
      await expect(approvalClaimModal).toContainText("Ended sales pass");
      await expect(approvalClaimModal.getByText("Free", { exact: true })).toBeVisible();

      // Claim the approval offer and verify its submitted identifier.
      const approvalRequest = pending1Page.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes(`/event/${event.id}/checkout`),
      );
      await waitForActionResponse(
        pending1Page,
        () => approvalClaimModal.getByRole("button", { name: "Claim offer", exact: true }).click(),
        {
          method: "POST",
          urlIncludes: `/event/${event.id}/checkout`,
        },
      );
      const approvalRequestData = new URLSearchParams((await approvalRequest).postData() ?? "");
      expect(approvalRequestData.get("admission_offer_id")).toBe(ENDED_PRICE_APPROVAL_OFFER_ID);
      await expect(approvalOfferRow).toHaveCount(0);

      // A waiting-list offer cannot fall back to its issue-time price snapshot.
      await openUserDashboardPath("/dashboard/user?tab=invitations", pending2Page);
      const waitlistOfferRow = pending2Page.locator("#dashboard-content tr", {
        hasText: event.name,
      });
      await expect(waitlistOfferRow).toContainText("Waiting list offer");
      await expect(waitlistOfferRow.getByText("Free", { exact: true })).toHaveCount(0);
      await openEventOfferActions(waitlistOfferRow);
      await waitlistOfferRow.getByRole("menuitem", { name: "Claim offer" }).click();
      const waitlistClaimModal = pending2Page.getByRole("dialog", {
        name: "Claim offer",
      });

      // Attempt the waitlist claim and verify its price conflict contract.
      const waitlistRequest = pending2Page.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes(`/event/${event.id}/checkout`),
      );
      await waitForActionResponse(
        pending2Page,
        () => waitlistClaimModal.getByRole("button", { name: "Claim offer", exact: true }).click(),
        {
          method: "POST",
          status: 409,
          urlIncludes: `/event/${event.id}/checkout`,
        },
      );
      const waitlistRequestData = new URLSearchParams((await waitlistRequest).postData() ?? "");
      expect(waitlistRequestData.get("admission_offer_id")).toBe(ENDED_PRICE_WAITLIST_OFFER_ID);
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "This ticket offer does not have a current price.",
      );
      await expect(waitlistOfferRow).toBeVisible();
    } finally {
      // Restore both seeded offers for later tests.
      resetEndedPriceOffers();
    }
  });

  test("checkout-started offers expose continue and cancel actions", async ({ pending2Page }) => {
    const event = TEST_TICKETING_EVENTS.paidOffers;

    // Open the user dashboard for the offer whose provider checkout has started.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending2Page);
    const offerRow = pending2Page.locator("#dashboard-content tr", {
      hasText: event.name,
    });
    await openEventOfferActions(offerRow);
    await expect(offerRow.getByRole("menuitem", { name: "Continue to checkout" })).toHaveAttribute(
      "href",
      "https://example.test/checkout/paid-offer",
    );
    await offerRow.getByRole("menuitem", { name: "Cancel checkout" }).click();
    await expect(pending2Page.locator(".swal2-popup")).toContainText(
      "Are you sure you want to cancel this checkout? Your ticket hold will be released.",
    );

    // Canceling the hold keeps the underlying offer available to claim again.
    await waitForActionResponse(
      pending2Page,
      () => pending2Page.getByRole("button", { name: "Yes" }).click(),
      {
        method: "DELETE",
        urlIncludes: `/event/${event.id}/checkout`,
      },
    );
    await expect(pending2Page.locator(".swal2-popup")).toContainText(
      "Your checkout has been canceled. The offer is ready to claim again.",
    );
    await pending2Page.getByRole("button", { name: "OK" }).click();
    await openEventOfferActions(offerRow);
    await expect(offerRow.getByRole("menuitem", { name: "Claim offer" })).toBeVisible();
  });

  test("member can decline a waiting-list ticket offer", async ({ member1Page }) => {
    const event = TEST_TICKETING_EVENTS.paidOffers;

    // Open the dedicated waiting-list offer row.
    await openUserDashboardPath("/dashboard/user?tab=invitations", member1Page);
    const offerRow = member1Page.locator("#dashboard-content tr", {
      hasText: event.name,
    });
    await expect(offerRow).toContainText("Waiting list offer");
    await openEventOfferActions(offerRow);
    await offerRow.getByRole("menuitem", { name: "Decline offer", exact: true }).click();
    await expect(member1Page.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to decline this offer?",
    );

    // Confirming the decline removes the waiting-list offer from the dashboard.
    await waitForActionResponse(member1Page, () => member1Page.getByRole("button", { name: "Yes" }).click(), {
      method: "PUT",
      urlEndsWith: "/decline",
      urlIncludes: "/dashboard/user/invitations/event-offers/",
    });
    await expect(offerRow).toHaveCount(0);
  });

  test("claiming an event invitation through checkout removes it from the user dashboard", async ({
    organizerGroupPage,
    pending1Page,
  }) => {
    // Ensure the seeded event invitation exists before accepting it.
    await ensureEventInvitation(
      organizerGroupPage,
      TEST_GROUP_IDS.community1.alpha,
      TEST_EVENT_IDS.alpha.two,
      TEST_USER_IDS.pending1,
    );

    // Open the user dashboard page.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const eventInvitationRow = dashboardContent.locator("tr", {
      hasText: "Upcoming Virtual Event",
    });
    try {
      // Verify the invitation is exposed as a checkout-owned RSVP offer.
      await expect(dashboardContent.getByText("Event Invitations", { exact: true })).toBeVisible();
      await expect(eventInvitationRow).toContainText("Platform Ops Meetup");
      await openEventOfferActions(eventInvitationRow);
      const claimEventInvitationButton = eventInvitationRow.getByRole("menuitem", {
        name: "Claim offer",
      });
      await expect(claimEventInvitationButton).toBeVisible();

      // Open the offer claim modal.
      await claimEventInvitationButton.click();
      const claimModal = pending1Page.getByRole("dialog", {
        name: "Claim offer",
      });
      await expect(claimModal).toBeVisible();

      // Complete the free offer through the unified checkout endpoint.
      await waitForActionResponse(
        pending1Page,
        () => claimModal.getByRole("button", { name: "Claim offer", exact: true }).click(),
        {
          method: "POST",
          urlIncludes: `/event/${TEST_EVENT_IDS.alpha.two}/checkout`,
        },
      );

      // Reload the invited user dashboard.
      await pending1Page.reload();

      // Assert how many matching elements are shown.
      await expect(dashboardContent.locator("tr", { hasText: "Upcoming Virtual Event" })).toHaveCount(0);
    } finally {
      // Restore the attendee state for the seeded event invitation.
      await pending1Page.request.post(
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${TEST_EVENT_IDS.alpha.two}/attend`),
        { form: {} },
      );
      await clearEventAttendeeState(organizerGroupPage, TEST_EVENT_IDS.alpha.two, TEST_USER_IDS.pending1);
    }
  });

  test("claiming a waitlist offer completes through checkout", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    const eventId = TEST_EVENT_IDS.alpha.dashboardWaitlist;

    try {
      // Free the only seat so reconciliation promotes the seeded waitlist entry.
      await clearEventAttendeeState(organizerGroupPage, eventId, TEST_USER_IDS.organizer1);

      // Open the promoted user's invitations and target the waitlist offer.
      await openUserDashboardPath("/dashboard/user?tab=invitations", member2Page);
      const dashboardContent = member2Page.locator("#dashboard-content");
      const offerRow = dashboardContent.locator("tr", {
        hasText: "Dashboard Waitlist Table Lab",
      });
      await expect(offerRow).toContainText("Waiting list offer");

      // Claim the promoted seat through the unified checkout endpoint.
      await openEventOfferActions(offerRow);
      await offerRow.getByRole("menuitem", { name: "Claim offer" }).click();
      const claimModal = member2Page.getByRole("dialog", {
        name: "Claim offer",
      });
      await expect(claimModal).toBeVisible();
      await waitForActionResponse(
        member2Page,
        () => claimModal.getByRole("button", { name: "Claim offer", exact: true }).click(),
        {
          method: "POST",
          urlIncludes: `/event/${eventId}/checkout`,
        },
      );
      await expect(offerRow).toHaveCount(0);
    } finally {
      // Restore the seeded full-event state for repeatable local runs.
      await clearEventAttendeeState(organizerGroupPage, eventId, TEST_USER_IDS.member2);
      const restoreResponse = await organizerGroupPage.request.post(
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
        { form: {} },
      );
      expect(restoreResponse.ok()).toBeTruthy();
      const restoreWaitlistResponse = await member2Page.request.post(
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
        { form: {} },
      );
      expect(restoreWaitlistResponse.ok()).toBeTruthy();
    }
  });

  test("rejecting an event invitation removes it from the user dashboard", async ({
    organizerGroupPage,
    pending1Page,
  }) => {
    // Ensure the seeded event invitation exists before rejecting it.
    await ensureEventInvitation(
      organizerGroupPage,
      TEST_GROUP_IDS.community1.alpha,
      TEST_EVENT_IDS.alpha.two,
      TEST_USER_IDS.pending1,
    );

    // Open the user dashboard page.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const eventInvitationRow = dashboardContent.locator("tr", {
      hasText: "Upcoming Virtual Event",
    });
    try {
      // Verify rejecting an event invitation removes it from the dashboard.
      await expect(dashboardContent.getByText("Event Invitations", { exact: true })).toBeVisible();
      await expect(eventInvitationRow).toContainText("Platform Ops Meetup");
      await openEventOfferActions(eventInvitationRow);
      const rejectEventInvitationButton = eventInvitationRow.getByRole("menuitem", {
        exact: true,
        name: "Decline offer",
      });
      await expect(rejectEventInvitationButton).toBeVisible();

      // Click the reject event invitation button.
      await rejectEventInvitationButton.click();
      await expect(pending1Page.locator(".swal2-popup")).toContainText(
        "Are you sure you would like to decline this offer?",
      );

      // Click Yes.
      await waitForActionResponse(
        pending1Page,
        () => pending1Page.getByRole("button", { name: "Yes" }).click(),
        {
          method: "PUT",
          urlEndsWith: "/decline",
          urlIncludes: "/dashboard/user/invitations/event-offers/",
        },
      );

      // Reload the invited user dashboard.
      await pending1Page.reload();

      // Assert how many matching elements are shown.
      await expect(dashboardContent.locator("tr", { hasText: "Upcoming Virtual Event" })).toHaveCount(0);
    } finally {
      // Restore the attendee state for the seeded event invitation.
      await pending1Page.request.post(
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${TEST_EVENT_IDS.alpha.two}/attend`),
        { form: {} },
      );
      await clearEventAttendeeState(organizerGroupPage, TEST_EVENT_IDS.alpha.two, TEST_USER_IDS.pending1);
    }
  });
});

/** Restores approval and waitlist offers after their shared ticket price ends. */
const resetEndedPriceOffers = () => {
  const eventId = TEST_REGISTRATION_WINDOW_EVENTS.priceEnded.id;

  queryE2eDatabase(`
    delete from event_purchase
    where event_id = '${eventId}'
    and user_id in ('${TEST_USER_IDS.pending1}', '${TEST_USER_IDS.pending2}');

    delete from event_attendee
    where event_id = '${eventId}'
    and user_id in ('${TEST_USER_IDS.pending1}', '${TEST_USER_IDS.pending2}');

    delete from admission_offer
    where event_id = '${eventId}'
    and user_id in ('${TEST_USER_IDS.pending1}', '${TEST_USER_IDS.pending2}');

    update event_invitation_request
    set
      status = 'accepted',
      reviewed_at = current_timestamp - interval '2 days',
      reviewed_by = '${TEST_USER_IDS.organizer1}'
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.pending1}';

    insert into admission_offer (
      admission_offer_id,
      amount_minor,
      currency_code,
      discount_amount_minor,
      event_id,
      event_ticket_type_id,
      expires_at,
      source,
      status,
      ticket_title,
      user_id
    ) values (
      '${ENDED_PRICE_APPROVAL_OFFER_ID}',
      0,
      null,
      0,
      '${eventId}',
      '56555555-5555-5555-5555-555555555923',
      current_timestamp + interval '5 days',
      'approval',
      'pending',
      'Ended sales pass',
      '${TEST_USER_IDS.pending1}'
    ), (
      '${ENDED_PRICE_WAITLIST_OFFER_ID}',
      0,
      null,
      0,
      '${eventId}',
      '56555555-5555-5555-5555-555555555923',
      current_timestamp + interval '5 days',
      'waitlist',
      'pending',
      'Ended sales pass',
      '${TEST_USER_IDS.pending2}'
    );
  `);
};
