import { expect, test } from "../../fixtures.js";
import { resetWaitlistLab } from "../../data-graphs/waitlist.js";
import { TEST_COMMUNITY_NAME, TEST_EVENT_IDS, TEST_GROUP_SLUGS, TEST_USER_IDS } from "../../seed.js";
import { getAttendButton, getLeaveButton, waitForAttendanceState } from "../../site/event/helpers.js";
import { confirmAlert, navigateToEvent, navigateToPath, waitForActionResponse } from "../../utils.js";

const WAITLIST_EVENT_NAME = "Full Event With Waitlist";

const WAITLIST_EVENT_SLUG = "alpha-waitlist-lab";

const WAITLIST_PROMOTION_KIND = "event-ticket-waitlist-offer";

test.describe("event waitlist promotion workflow", () => {
  test.afterEach(() => {
    resetWaitlistLab();
  });

  test("a waitlisted user is promoted when the attendee leaves", async ({
    member2Page,
    notifications,
    organizerGroupPage,
    page,
  }) => {
    // The public page starts sold out while the only seeded seat is occupied.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, WAITLIST_EVENT_SLUG);
    const soldOutRibbon = page.locator("[data-availability-sold-out-ribbon]");
    const remainingCaption = page.locator('[data-availability-caption="remaining"]');
    const waitlistCaption = page.locator('[data-availability-caption="waitlist"]');
    await waitForAvailabilityHydration(page);
    await expect(soldOutRibbon).toBeVisible();
    await expect(remainingCaption).toBeHidden();
    await expect(waitlistCaption).toBeHidden();

    // Load the waitlist event before creating a waitlisted member.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    // Wait for the member attendance controls before joining the waitlist.
    await waitForAttendanceState(member2Page);

    // Join the waitlist and wait for the attendance record to be created.
    await waitForActionResponse(member2Page, () => getAttendButton(member2Page).click(), {
      method: "POST",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`,
    });

    // Verify the member is waiting before the attendee leaves.
    await expect(getLeaveButton(member2Page)).toContainText("Leave waiting list");

    // The public page shows the queue size while no seats remain.
    await reloadWithAvailability(page);
    await expect(soldOutRibbon).toBeVisible();
    await expect(remainingCaption).toBeHidden();
    await expect(waitlistCaption).toBeVisible();
    await expect(page.locator("[data-availability-waitlist]")).toHaveText("1");

    // Load the attendee account that can free the event capacity.
    await navigateToEvent(
      organizerGroupPage,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    // Verify the attendee can cancel attendance.
    await waitForAttendanceState(organizerGroupPage);
    await expect(getLeaveButton(organizerGroupPage)).toContainText("Cancel attendance");

    // Request attendee cancellation and verify the confirmation appears.
    await getLeaveButton(organizerGroupPage).click();
    await expect(organizerGroupPage.getByRole("button", { name: "Yes" })).toBeVisible();

    // Cancel the organizer attendance to promote the waitlisted member.
    const promotionCheckpoint = notifications.checkpoint();
    await waitForActionResponse(
      organizerGroupPage,
      () => confirmAlert(organizerGroupPage, { message: "Are you sure you want to cancel your attendance?" }),
      {
        method: "DELETE",
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`,
      },
    );

    // Waitlist promotion creates the ticket-offer notification kind used by the enqueue function.
    notifications.expectNew(
      [
        { kind: "event-attendance-canceled", userIds: [TEST_USER_IDS.organizer1] },
        { kind: WAITLIST_PROMOTION_KIND, userIds: [TEST_USER_IDS.member2] },
      ],
      { since: promotionCheckpoint },
    );

    // Promotion reserves the released seat and empties the queue.
    await reloadWithAvailability(page);
    await expect(soldOutRibbon).toBeVisible();
    await expect(remainingCaption).toBeHidden();
    await expect(waitlistCaption).toBeHidden();

    // Open the promoted member's invitations and verify the waitlist offer.
    await navigateToPath(member2Page, "/dashboard/user?tab=invitations");
    const dashboardContent = member2Page.locator("#dashboard-content");
    const offerRow = dashboardContent.locator("tr", {
      hasText: WAITLIST_EVENT_NAME,
    });
    await expect(offerRow).toContainText("Waiting list offer");

    // Claim the promoted seat through the unified checkout endpoint.
    await offerRow.getByLabel(/Open offer actions/).click();
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
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/checkout`,
      },
    );
    await expect(offerRow).toHaveCount(0);

    // Claiming the promoted offer keeps the single seat allocated.
    await reloadWithAvailability(page);
    await expect(soldOutRibbon).toBeVisible();
    await expect(remainingCaption).toBeHidden();

    // Verify the promoted member is now attending the event.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );
    await waitForAttendanceState(member2Page);
    await expect(getLeaveButton(member2Page)).toBeVisible();
    await expect(getLeaveButton(member2Page)).toContainText("Cancel attendance");

    // Cancel the claimed attendance and verify the public capacity reopens.
    await getLeaveButton(member2Page).click();
    await waitForActionResponse(
      member2Page,
      () => confirmAlert(member2Page, { message: "Are you sure you want to cancel your attendance?" }),
      {
        method: "DELETE",
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`,
      },
    );
    await reloadWithAvailability(page);
    await expect(soldOutRibbon).toBeHidden();

    // The reopened seat stays visible while the waiting list remains enabled.
    await expect(remainingCaption).toBeVisible();
    await expect(page.locator("[data-availability-remaining]")).toHaveText("1");
    await expect(waitlistCaption).toBeHidden();
  });
});

/** Reloads the page and waits for the refreshed public availability. */
const reloadWithAvailability = async (page) => {
  await page.reload();
  await waitForAvailabilityHydration(page);
};

/** Waits until the public availability payload has been applied to the page. */
const waitForAvailabilityHydration = async (page) => {
  await expect(
    page.locator('[data-availability-url][data-availability-hydrated="true"]').first(),
  ).toBeAttached();
};
