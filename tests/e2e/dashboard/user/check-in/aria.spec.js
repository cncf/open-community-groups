import { expect, test } from "../../../fixtures.js";

import { setupOwnedTicketedAttendee } from "../../../data-graphs/attendance.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";
import { expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// Name of the owned event the user without data attends; its dates are matched with regexes.
const CHECK_IN_EVENT_NAME = "E2E ARIA check-in event";

// Check-In is the only user dashboard tab rendered on mobile, so the mobile test uses the
// responsive layout instead of the desktop version.
test.describe("user dashboard check-in ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, owned }) => {
    await expectCheckInViews({ emptyUserPage, owned }, "desktop");
  });

  test("matches the mobile views @mobile", async ({ emptyUserPage, owned }) => {
    await expectCheckInViews({ emptyUserPage, owned }, "mobile");
  });
});

/** Checks the layout of the check-in tab views and captures them. */
const expectCheckInViews = async ({ emptyUserPage, owned }, viewport) => {
  // The menu is a closed drawer in the mobile layout.
  const menu = viewport === "desktop";
  const checkIn = emptyUserPage.getByRole("region", { name: "Check-In" });

  await test.step("empty state", async () => {
    // Load the check-in tab of a user without events and check the layout.
    await openUserDashboardView(emptyUserPage, "tab=check-in", { menu, regions: [checkIn] });

    // Capture the heading and the empty state.
    await expectAriaSnapshot(emptyUserPage, checkIn, "check-in-empty");
  });

  // Register the user for an owned event awaiting check-in; the event cleanup removes the ticket.
  const { eventId, ticketTypeIds } = owned.event({
    groupId: TEST_GROUP_IDS.community1.alpha,
    name: CHECK_IN_EVENT_NAME,
    startsIn: "10 days",
  });
  setupOwnedTicketedAttendee({ eventId, ticketTypeId: ticketTypeIds.general, userId: TEST_USER_IDS.empty });

  await test.step("event list", async () => {
    // Load the event awaiting check-in and check the layout.
    await openUserDashboardView(emptyUserPage, "tab=check-in", { menu, regions: [checkIn] });

    // Capture the event card; its dates follow the seed day.
    await expectAriaSnapshot(emptyUserPage, checkIn, "check-in-list");
  });

  await test.step("check-in code dialog", async () => {
    // Open the event's check-in code and check the layout.
    const dialog = emptyUserPage.getByRole("dialog", { name: "Attendee check-in" });
    await checkIn.getByRole("button", { name: new RegExp(`^${CHECK_IN_EVENT_NAME}`) }).click();
    await expect(
      dialog.getByRole("img", { name: `${CHECK_IN_EVENT_NAME} attendee check-in QR code` }),
    ).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [dialog] });

    // Capture the event, ticket, QR code and attendee identity; the date follows the seed day.
    await expectAriaSnapshot(emptyUserPage, dialog, "check-in-dialog");
  });
};
