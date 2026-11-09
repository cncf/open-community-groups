import { expect, test } from "../../../fixtures.js";
import { cleanupEventsByIds, setupTicketAllocationEvent } from "../../../data-graphs/events.js";
import { cleanupEventEnrollment, setupEventInvitation } from "../../../data-graphs/invitations.js";
import { queryE2eDatabase } from "../../../database.js";
import { enableDesktopVersion } from "../../../snapshots.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_IDS,
  TEST_GROUP_SLUGS,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_TICKETING_EVENTS,
  TEST_USER_IDS,
} from "../../../seed.js";
import { buildE2eUrl, confirmAlert, waitForActionResponse } from "../../../utils.js";
import { clearEventAttendeeState, openUserDashboardPath } from "../helpers.js";
import { openEventOfferActions } from "./helpers.js";

const ENDED_PRICE_APPROVAL_OFFER_ID = "59555555-5555-5555-5555-555555555923";

const ENDED_PRICE_WAITLIST_OFFER_ID = "59555555-5555-5555-6555-555555555923";

/** Event-user pair whose organizer invitation the claim and decline tests own. */
const EVENT_INVITATION = {
  eventId: TEST_EVENT_IDS.alpha.two,
  userId: TEST_USER_IDS.pending1,
};

const PAID_OFFER_CHECKOUT_ID = "59555555-5555-5555-5555-555555555916";

const PAID_OFFER_TICKET_TYPE_ID = "56555555-5555-5555-5555-555555555916";

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

    try {
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

      // Canceling the hold keeps the underlying offer available to claim again.
      await waitForActionResponse(
        pending2Page,
        () =>
          confirmAlert(pending2Page, {
            message: "Are you sure you want to cancel this checkout? Your ticket hold will be released.",
          }),
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
    } finally {
      // Restore the seeded checkout hold for later tests.
      resetPaidOfferCheckout();
    }
  });

  test("member can decline a waiting-list ticket offer", async ({ member1Page }) => {
    const event = TEST_TICKETING_EVENTS.paidOffers;

    try {
      // Open the dedicated waiting-list offer row.
      await openUserDashboardPath("/dashboard/user?tab=invitations", member1Page);
      const offerRow = member1Page.locator("#dashboard-content tr", {
        hasText: event.name,
      });
      await expect(offerRow).toContainText("Waiting list offer");
      await openEventOfferActions(offerRow);
      await offerRow.getByRole("menuitem", { name: "Decline offer", exact: true }).click();

      // Confirming the decline removes the waiting-list offer from the dashboard.
      await waitForActionResponse(
        member1Page,
        () => confirmAlert(member1Page, { message: "Are you sure you would like to decline this offer?" }),
        {
          method: "PUT",
          urlEndsWith: "/decline",
          urlIncludes: "/dashboard/user/invitations/event-offers/",
        },
      );
      await expect(offerRow).toHaveCount(0);
    } finally {
      // Restore the seeded waiting-list offer for later tests.
      resetPaidOfferWaitlistOffer();
    }
  });

  test("claiming an event invitation through checkout removes it from the user dashboard", async ({
    owned,
    pending1Page,
  }) => {
    // Create the event invitation before accepting it; owned teardown removes it and any enrollment.
    setupEventInvitation(EVENT_INVITATION);
    owned.defer(() => cleanupEventEnrollment(EVENT_INVITATION));

    // Open the user dashboard page.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const eventInvitationRow = dashboardContent.locator("tr", {
      hasText: "Upcoming Virtual Event",
    });

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
  });

  test("claiming a waitlist offer completes through checkout", async ({
    member2Page,
    organizerGroupPage,
    owned,
  }) => {
    // Own a one-seat event so the promotion never reorders a seeded waitlist.
    const event = owned.track(
      setupTicketAllocationEvent({
        groupId: TEST_GROUP_IDS.community1.alpha,
        ticketTypes: [{ key: "general", seats: 1, title: "General admission" }],
        waitlistEnabled: true,
      }),
      ({ eventId }) => cleanupEventsByIds([eventId]),
    );
    const eventId = event.eventId;

    // Fill the only seat and queue the member behind it.
    for (const page of [organizerGroupPage, member2Page]) {
      const attendResponse = await page.request.post(
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
        { form: {} },
      );
      expect(attendResponse.ok()).toBeTruthy();
    }

    // Free the only seat so reconciliation promotes the queued member.
    await clearEventAttendeeState(organizerGroupPage, eventId, TEST_USER_IDS.organizer1);

    // Open the promoted user's invitations and target the waitlist offer.
    await openUserDashboardPath("/dashboard/user?tab=invitations", member2Page);
    const dashboardContent = member2Page.locator("#dashboard-content");
    const offerRow = dashboardContent.locator("tr", {
      hasText: event.name,
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
  });

  test("rejecting an event invitation removes it from the user dashboard", async ({
    notifications,
    owned,
    pending1Page,
  }) => {
    // Create the event invitation before rejecting it; owned teardown removes it.
    setupEventInvitation(EVENT_INVITATION);
    owned.defer(() => cleanupEventEnrollment(EVENT_INVITATION));
    const checkpoint = notifications.checkpoint();

    // Open the user dashboard page.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const eventInvitationRow = dashboardContent.locator("tr", {
      hasText: "Upcoming Virtual Event",
    });

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

    // Click Yes.
    await waitForActionResponse(
      pending1Page,
      () => confirmAlert(pending1Page, { message: "Are you sure you would like to decline this offer?" }),
      {
        method: "PUT",
        urlEndsWith: "/decline",
        urlIncludes: "/dashboard/user/invitations/event-offers/",
      },
    );

    // Verify the organizer who sent the invitation is told it was declined.
    notifications.expectNew(
      [
        {
          kind: "event-admission-offer-declined",
          templateDataContains: { event_id: EVENT_INVITATION.eventId, user_id: EVENT_INVITATION.userId },
          userIds: [TEST_USER_IDS.organizer1],
        },
      ],
      { since: checkpoint },
    );

    // Reload the invited user dashboard.
    await pending1Page.reload();

    // Assert how many matching elements are shown.
    await expect(dashboardContent.locator("tr", { hasText: "Upcoming Virtual Event" })).toHaveCount(0);
  });
});

test.describe("user dashboard invitations view on phones @mobile", () => {
  test("claims an offer from its card action and a bottom sheet", async ({ owned, pending1Page }) => {
    // Create the event invitation before claiming it; owned teardown removes it and any enrollment.
    setupEventInvitation(EVENT_INVITATION);
    owned.defer(() => cleanupEventEnrollment(EVENT_INVITATION));
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);
    const offerCard = pending1Page.locator("#dashboard-content article", {
      hasText: "Upcoming Virtual Event",
    });

    // Verify the card summarizes the offer and when it expires.
    await expect(offerCard.getByRole("heading", { name: "Upcoming Virtual Event" })).toBeVisible();
    await expect(offerCard.getByText("Free RSVP", { exact: true })).toBeVisible();
    await expect(offerCard).toContainText(/Expires [A-Z][a-z]{2} \d{1,2}, \d{4}/);

    // Verify the primary action is one tap away and 44px tall.
    const claimButton = offerCard.getByRole("button", { name: "Claim offer", exact: true });
    await expect(claimButton).toBeVisible();
    expect((await claimButton.boundingBox()).height).toBeGreaterThanOrEqual(44);

    // Verify Decline sits beside it at 44px, without an actions menu.
    const declineButton = offerCard.getByRole("button", { name: "Decline", exact: true });
    await expect(declineButton).toBeVisible();
    const claimBox = await claimButton.boundingBox();
    const declineBox = await declineButton.boundingBox();
    expect(declineBox.height).toBeGreaterThanOrEqual(44);
    expect(declineBox.y).toBe(claimBox.y);
    expect(declineBox.x).toBeGreaterThan(claimBox.x + claimBox.width);
    await expect(offerCard.getByLabel(/Open offer actions/)).toHaveCount(0);

    // Open the claim form and verify it rests on the bottom edge, full width.
    await claimButton.click();
    const dialog = pending1Page.getByRole("dialog", { name: "Claim offer" });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole("button", { name: "Close modal" })).toBeFocused();
    const sheet = dialog.locator(".sheet-panel");
    await expect(sheet).toHaveAttribute("data-sheet-drag", "");
    const viewport = pending1Page.viewportSize();
    await expect
      .poll(async () => {
        const box = await sheet.boundingBox();
        return Math.round(box.y + box.height);
      })
      .toBe(viewport.height);
    expect((await sheet.boundingBox()).width).toBe(viewport.width);

    // Close it and verify focus returns to the card action.
    await dialog.getByRole("button", { name: "Close modal" }).click();
    await expect(dialog).toBeHidden();
    await expect(claimButton).toBeFocused();

    // Complete the free offer through the unified checkout endpoint.
    await claimButton.click();
    await waitForActionResponse(
      pending1Page,
      () => dialog.getByRole("button", { name: "Claim offer", exact: true }).click(),
      {
        method: "POST",
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.two}/checkout`,
      },
    );

    // Verify the claimed offer leaves the list.
    await pending1Page.reload();
    await expect(offerCard).toHaveCount(0);
  });

  test("checkout-started offers continue from the card action", async ({ pending2Page }) => {
    // Open the offer whose provider checkout has started.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending2Page);
    const offerCard = pending2Page.locator("#dashboard-content article", {
      hasText: TEST_TICKETING_EVENTS.paidOffers.name,
    });

    // Verify the card links to checkout and the menu keeps Cancel checkout and Decline offer.
    await expect(offerCard.getByRole("link", { name: "Continue to checkout" })).toHaveAttribute(
      "href",
      "https://example.test/checkout/paid-offer",
    );
    await openEventOfferActions(offerCard);
    await expect(offerCard.getByRole("menuitem", { name: "Cancel checkout" })).toBeVisible();
    await expect(offerCard.getByRole("menuitem", { name: "Decline offer" })).toBeVisible();
    await expect(offerCard.getByRole("menuitem", { name: "Continue to checkout" })).toHaveCount(0);
  });

  test("a deep link lands below the fixed header", async ({ member1Page }) => {
    // Use a short viewport, so the card has to scroll into view.
    await member1Page.setViewportSize({ height: 400, width: 390 });

    // The seeded offers tie on created_at, so take the first card, the one with room to scroll.
    await openUserDashboardPath("/dashboard/user?tab=invitations", member1Page);
    const firstCard = member1Page.locator('#dashboard-content article[id^="event-offer-card-"]').first();
    const cardId = await firstCard.getAttribute("id");

    // Leave the page, so the hash is a real load.
    await member1Page.goto("about:blank");
    await openUserDashboardPath(`/dashboard/user?tab=invitations#${cardId}`, member1Page);

    // Verify the header does not cover the targeted card.
    const card = member1Page.locator(`[id="${cardId}"]`);
    await expect(card).toBeInViewport();
    const headerBox = await member1Page.locator("#dashboard-header").boundingBox();
    const headerBottom = headerBox.y + headerBox.height;
    const cardTop = (await card.boundingBox()).y;
    expect(cardTop).toBeGreaterThanOrEqual(headerBottom);
    expect(cardTop).toBeLessThanOrEqual(headerBottom + 24);
  });

  test("the desktop version keeps the table and the modal", async ({ owned, pending1Page }) => {
    // Create an offer and load it in the desktop version.
    setupEventInvitation(EVENT_INVITATION);
    owned.defer(() => cleanupEventEnrollment(EVENT_INVITATION));
    await enableDesktopVersion(pending1Page);
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);
    const content = pending1Page.locator("#dashboard-content");
    const offerRow = content.locator("tr", { hasText: "Upcoming Virtual Event" });

    // Verify the column headers stay and the phone action does not show.
    await expect(content.getByRole("columnheader", { name: "Expires" })).toBeVisible();
    await expect(offerRow.getByRole("button", { name: "Claim offer", exact: true })).toHaveCount(0);

    // Verify the menu item opens the centred modal, with no sheet behaviour.
    await openEventOfferActions(offerRow);
    await offerRow.getByRole("menuitem", { name: "Claim offer" }).click();
    const dialog = pending1Page.getByRole("dialog", { name: "Claim offer" });
    await expect(dialog).toBeVisible();
    const sheet = dialog.locator(".sheet-panel");
    await expect(sheet).not.toHaveAttribute("data-sheet-drag");
    await expect(sheet).not.toHaveCSS("position", "fixed");
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

const resetPaidOfferCheckout = () => {
  // The lifecycle trigger allows pending -> checkout_pending, so the canceled hold can be reopened in place.
  queryE2eDatabase(`
    update admission_offer
    set status = 'checkout_pending', updated_at = current_timestamp
    where admission_offer_id = '${PAID_OFFER_CHECKOUT_ID}'
    and status = 'pending';

    update event_purchase
    set
      hold_expires_at = current_timestamp + interval '5 days',
      status = 'pending',
      updated_at = current_timestamp
    where event_purchase_id = '${PAID_OFFER_CHECKOUT_ID}'
    and status = 'expired';
  `);
};

const resetPaidOfferWaitlistOffer = () => {
  const eventId = TEST_TICKETING_EVENTS.paidOffers.id;

  // Declined offers cannot become pending again, so replace the row with the seeded one.
  queryE2eDatabase(`
    delete from admission_offer
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member1}'
    and source = 'waitlist'
    and status = 'declined';

    insert into admission_offer (event_id, event_ticket_type_id, expires_at, source, status, user_id)
    select
      '${eventId}',
      '${PAID_OFFER_TICKET_TYPE_ID}',
      current_timestamp + interval '7 days',
      'waitlist',
      'pending',
      '${TEST_USER_IDS.member1}'
    where not exists (
      select 1
      from admission_offer
      where event_id = '${eventId}'
      and user_id = '${TEST_USER_IDS.member1}'
      and status in ('checkout_pending', 'pending')
    );
  `);
};
