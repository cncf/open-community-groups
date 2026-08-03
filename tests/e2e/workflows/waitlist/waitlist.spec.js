import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_SLUGS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  navigateToPath,
  restoreSeededWaitlistEvent,
  waitForActionResponse,
  waitForAttendanceState,
} from "../../utils.js";

const WAITLIST_EVENT_NAME = "Full Event With Waitlist";
const WAITLIST_EVENT_SLUG = "alpha-waitlist-lab";

test.describe("event waitlist promotion workflow", () => {
  test.beforeEach(async ({ member2Page, organizerGroupPage }) => {
    await restoreSeededWaitlistEvent(member2Page, organizerGroupPage);
  });

  test.afterEach(async ({ member2Page, organizerGroupPage }) => {
    await restoreSeededWaitlistEvent(member2Page, organizerGroupPage);
  });

  test("a waitlisted user is promoted when the attendee leaves", async ({
    member2Page,
    organizerGroupPage,
    page,
  }) => {
    // The public page starts sold out while the only seeded seat is occupied.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, WAITLIST_EVENT_SLUG);
    const soldOutRibbon = page.locator("[data-availability-sold-out-ribbon]");
    await expect(soldOutRibbon).toBeVisible();

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
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
      {
        method: "DELETE",
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`,
      },
    );

    // Promotion reserves the released seat, so capacity remains sold out.
    await page.reload();
    await expect(soldOutRibbon).toBeVisible();

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
    await page.reload();
    await expect(soldOutRibbon).toBeVisible();

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
    await waitForActionResponse(member2Page, () => member2Page.getByRole("button", { name: "Yes" }).click(), {
      method: "DELETE",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`,
    });
    await page.reload();
    await expect(soldOutRibbon).toBeHidden();
  });
});
