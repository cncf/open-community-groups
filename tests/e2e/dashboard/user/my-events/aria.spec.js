import { expect, test } from "../../../fixtures.js";

import { setupOwnedTicketedAttendee } from "../../../data-graphs/attendance.js";
import { TEST_GROUP_IDS, TEST_REGISTRATION_QUESTIONS_EVENT, TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// Owned event the user without data attends; its date is matched with a regex.
const ATTENDED_EVENT = { name: "E2E ARIA attended event", slug: "e2e-aria-attended-event" };

// The seeded rows of the first member are left out, since attendance tests add and remove them.
// Its registration answers are seeded and only read: answer tests use other users.
test.describe("user dashboard my events ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member1Page, owned }) => {
    await expectMyEventsViews({ emptyUserPage, member1Page, owned });
  });

  test("matches the views in the mobile desktop version @mobile", async ({
    emptyUserPage,
    member1Page,
    owned,
  }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member1Page);
    await expectMyEventsViews({ emptyUserPage, member1Page, owned });
  });
});

/** Checks the layout of the my events tab views and captures them. */
const expectMyEventsViews = async ({ emptyUserPage, member1Page, owned }) => {
  await test.step("empty state", async () => {
    // Load the events of a user without events and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=events");

    // Capture the title, the column headers and the empty state.
    await expectAriaSnapshot(emptyUserPage, content, "my-events-empty");
  });

  // Register the user for an owned event; the event cleanup removes the ticket.
  const { eventId, ticketTypeIds } = owned.event({
    groupId: TEST_GROUP_IDS.community1.alpha,
    startsIn: "10 days",
    ...ATTENDED_EVENT,
  });
  setupOwnedTicketedAttendee({ eventId, ticketTypeId: ticketTypeIds.general, userId: TEST_USER_IDS.empty });

  await test.step("event row actions", async () => {
    // Load the attended event and open its actions menu.
    const content = await openUserDashboardView(emptyUserPage, "tab=events");
    const row = content.getByRole("row").filter({ hasText: ATTENDED_EVENT.name });
    await row.getByLabel("Open event actions").click();
    await expect(row.getByRole("menu")).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [row.getByRole("menu")] });

    // Capture the row with its role, status and the open actions menu; the date follows the seed day.
    await expectAriaSnapshot(emptyUserPage, row, "my-events-row");
  });

  await test.step("registration questions dialog", async () => {
    // Load the events of the user with seeded registration answers and check the layout.
    const content = await openUserDashboardView(member1Page, "tab=events");
    const dialog = member1Page.getByRole("dialog", { name: "Registration questions" });

    // Open the answers of the registration questions event from its actions menu.
    const row = content.getByRole("row").filter({ hasText: TEST_REGISTRATION_QUESTIONS_EVENT.name });
    await row.getByLabel("Open event actions").click();
    await row.getByRole("menuitem", { name: "Update answers" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(member1Page, { regions: [dialog] });

    // Capture the questions, the seeded answers and the actions.
    await expectAriaSnapshot(member1Page, dialog, "my-events-registration-dialog");
  });
};
