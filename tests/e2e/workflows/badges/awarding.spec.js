import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase } from "../../database.js";
import {
  cleanupBadgeAwardJobs,
  cleanupCredential,
  setupBadgeDefinition,
  setupBadgeStatusList,
} from "../../data-graphs/badges.js";
import { cleanupEventsByIds, setupOrganizerEvent } from "../../data-graphs/events.js";
import {
  openEventUpdateFormByName,
  waitForEventEditorAfterSave,
} from "../../dashboard/group/events/helpers.js";
import { deleteNotificationsSince, snapshotNotifications } from "../../notifications.js";
import { TEST_EVENT_IDS, TEST_EVENT_NAMES, TEST_GROUP_IDS, TEST_USER_IDS } from "../../seed.js";
import { navigateToPath, waitForActionResponse } from "../../utils.js";
import { submitBadgeAward } from "./helpers.js";

const BADGE_AWARD_SETTLE_TIMEOUT_MS = 45_000;

const HOST_BADGE_ID = "babababa-baba-baba-baba-babababab001";

test.describe("group badge awarding", () => {
  test("awarding a badge to existing holders is idempotent", async ({ organizerGroupPage }) => {
    // Resolve all attendees and open the shared badge picker.
    const activeHostBadgesBefore = countActiveHostBadges();
    await openPrimaryEventAttendees(organizerGroupPage);
    await organizerGroupPage.getByRole("button", { name: "Award badge" }).click();

    // Award the host badge; both seeded attendees already hold it.
    await submitBadgeAward(
      organizerGroupPage,
      () =>
        waitForActionResponse(
          organizerGroupPage,
          () => organizerGroupPage.getByRole("menuitem", { name: "All attendees" }).click(),
          {
            method: "GET",
            urlIncludes: `/events/${TEST_EVENT_IDS.alpha.one}/badges/recipients?scope=all-attendees`,
          },
        ),
      HOST_BADGE_ID,
      { expectedStatus: "2 active holders were skipped." },
    );
    expect(countActiveHostBadges()).toBe(activeHostBadgesBefore);
  });

  test("organizer can award a badge to chosen attendees", async ({ organizerGroupPage }) => {
    // Enter badge selection mode from the attendee award menu.
    await openPrimaryEventAttendees(organizerGroupPage);
    await organizerGroupPage.getByRole("button", { name: "Award badge" }).click();
    await organizerGroupPage.getByRole("menuitem", { name: "Choose attendees" }).click();

    // Select one attendee and continue to the badge picker.
    const selectionBar = organizerGroupPage.locator("[data-attendee-email-selection-bar]");
    const attendeeCheckbox = organizerGroupPage.getByRole("checkbox", {
      name: "Select E2E Member One",
    });
    await expect(selectionBar).toBeVisible();
    await attendeeCheckbox.check();
    await expect(selectionBar).toContainText("1 attendee selected");

    // Award the host badge; the selected attendee already holds it.
    await submitBadgeAward(
      organizerGroupPage,
      () => selectionBar.getByRole("button", { name: "Continue" }).click(),
      HOST_BADGE_ID,
      { expectedStatus: "1 active holder was skipped." },
    );
  });

  test("host, speaker, and session-speaker actions use the shared picker", async ({ organizerGroupPage }) => {
    // Open the contributor section of the seeded event.
    await openPrimaryEvent(organizerGroupPage);
    await organizerGroupPage.locator('button[data-section="contributors"]').click();

    // Open the all-hosts picker.
    await organizerGroupPage.locator("#event-hosts-award-button").click();
    await expect(
      organizerGroupPage
        .getByRole("dialog", { name: "Award badge" })
        .getByRole("radiogroup", { name: "Badge" }),
    ).toBeVisible();
    await closeAwardDialog(organizerGroupPage);

    // Open the all-speakers picker and verify session speakers are included.
    await organizerGroupPage
      .locator("speakers-selector")
      .getByRole("button", { name: "Award badge" })
      .click();
    const speakerDialog = organizerGroupPage.getByRole("dialog", {
      name: "Award badge",
    });
    await expect(
      speakerDialog.getByText("including speakers assigned to individual sessions", { exact: false }),
    ).toBeVisible();
    await closeAwardDialog(organizerGroupPage);

    // Open one session speaker's row action.
    const sessionSpeakers = organizerGroupPage.locator("session-speakers-table");
    const sessionSpeakerRow = sessionSpeakers.locator("tr", {
      hasText: "E2E Member One",
    });
    await sessionSpeakerRow
      .locator('summary[aria-label="Open session speaker actions for E2E Member One"]')
      .click();
    const sessionSpeakerAwardButton = sessionSpeakerRow.locator("button[data-badge-award-open]");
    await expect(sessionSpeakerAwardButton).toBeEnabled();
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        sessionSpeakerAwardButton.evaluate((button) => {
          const badgeAwardModal = document.querySelector("badge-award-modal");

          if (!badgeAwardModal || typeof badgeAwardModal.open !== "function") {
            throw new Error("Badge award modal is unavailable");
          }
          badgeAwardModal.open({
            eventId: button.dataset.eventId,
            trigger: button,
            userIds: button.dataset.userIds.split(",").filter(Boolean),
          });
        }),
      {
        method: "GET",
        urlIncludes: "/dashboard/group/badges/options",
      },
    );
    await expect(
      organizerGroupPage
        .getByRole("dialog", { name: "Award badge" })
        .getByRole("radiogroup", { name: "Badge" }),
    ).toBeVisible();
    await closeAwardDialog(organizerGroupPage);
  });

  test("organizer row and bulk awards send the event organizers", async ({ organizerGroupPage }) => {
    test.setTimeout(120_000);

    // Create an isolated event whose only contributors are two organizers outside the group team,
    // which editors can keep listed after they leave it.
    const badge = setupBadgeDefinition({ groupId: TEST_GROUP_IDS.community1.alpha });
    const statusList = setupBadgeStatusList({ groupId: TEST_GROUP_IDS.community1.alpha });
    const organizerUserIds = [TEST_USER_IDS.member2, TEST_USER_IDS.member1];
    const event = setupOrganizerEvent({
      groupId: TEST_GROUP_IDS.community1.alpha,
      organizerUserIds,
    });
    const notifications = snapshotNotifications();

    try {
      // Open the Contributors tab of the isolated event.
      await openEventUpdateFormByName(organizerGroupPage, event.name, event.eventId);
      await organizerGroupPage.locator('button[data-section="contributors"]').click();
      const awardButton = organizerGroupPage.locator("#event-organizers-award-button");
      await expect(awardButton).toBeEnabled();

      // Award one organizer from the row action and verify the request recipients.
      const memberTwoRow = organizerGroupPage.locator("#event-organizers-selector tr", {
        hasText: "E2E Member Two",
      });
      await memberTwoRow.locator('summary[aria-label="Open organizer actions for E2E Member Two"]').click();
      const rowAward = await submitBadgeAward(
        organizerGroupPage,
        () => memberTwoRow.getByRole("menuitem", { name: "Award badge" }).click(),
        badge.badgeId,
      );
      expect(rowAward).toEqual({
        badge_id: badge.badgeId,
        event_id: event.eventId,
        user_ids: [TEST_USER_IDS.member2],
      });

      // Award every organizer from the bulk button and verify the request recipients.
      const bulkAward = await submitBadgeAward(organizerGroupPage, () => awardButton.click(), badge.badgeId);
      expect(bulkAward).toEqual({
        badge_id: badge.badgeId,
        event_id: event.eventId,
        user_ids: organizerUserIds,
      });

      // Remove one organizer without saving and verify awards wait for the save.
      const memberOneRow = organizerGroupPage.locator("#event-organizers-selector tr", {
        hasText: "E2E Member One",
      });
      await memberOneRow.locator('summary[aria-label="Open organizer actions for E2E Member One"]').click();
      await memberOneRow.getByRole("menuitem", { name: "Delete" }).click();
      const confirmAlert = organizerGroupPage.locator(".swal2-popup");
      await expect(confirmAlert).toContainText("E2E Member One is no longer on the group team");
      await confirmAlert.getByRole("button", { name: "Remove" }).click();
      await expect(memberOneRow).toHaveCount(0);
      await expect(awardButton).toBeDisabled();
      await expect(awardButton).toHaveAttribute("title", "Save contributor changes before awarding badges.");
      await memberTwoRow.locator('summary[aria-label="Open organizer actions for E2E Member Two"]').click();
      await expect(memberTwoRow.getByRole("menuitem", { name: "Award badge" })).toBeDisabled();

      // Save the change and verify awards are available for the saved organizers.
      const visibleSaveButton = organizerGroupPage.locator(
        "#pending-changes-alert:not(.hidden) #update-event-button",
      );
      await expect(visibleSaveButton).toBeVisible();
      await waitForEventEditorAfterSave(organizerGroupPage, () => visibleSaveButton.click(), {
        eventId: event.eventId,
        method: "PUT",
        urlIncludes: `/dashboard/group/events/${event.eventId}/update`,
      });
      await organizerGroupPage.locator('button[data-section="contributors"]').click();
      await expect(awardButton).toBeEnabled();
      await expect(awardButton).toHaveAttribute("data-user-ids", TEST_USER_IDS.member2);
      await expect(awardButton).toHaveAttribute("data-event-id", event.eventId);

      // Wait for the queued awards before removing their generated rows.
      await waitForSettledAwardJobs(badge.badgeId);
    } finally {
      // Remove generated notifications, jobs, credentials, and the isolated event.
      deleteNotificationsSince(notifications, "badge-awarded", organizerUserIds);
      cleanupBadgeAwardJobs({ badgeId: badge.badgeId });
      cleanupCredential({
        badgeCreated: badge.badgeCreated,
        badgeId: badge.badgeId,
        badgeStatusListId: statusList.badgeStatusListId,
      });
      cleanupEventsByIds([event.eventId]);
    }
  });

  test("accepted group team members can receive badges", async ({ organizerGroupPage }) => {
    // Open an accepted member's team action menu.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");
    const memberRow = organizerGroupPage.getByRole("row", {
      name: /E2E Events Manager One/u,
    });
    await memberRow
      .locator('summary[aria-label="Open team member actions for E2E Events Manager One"]')
      .click();

    // Award the host badge without an event; the team member already holds it.
    const award = await submitBadgeAward(
      organizerGroupPage,
      () => memberRow.getByRole("menuitem", { name: "Award badge" }).click(),
      HOST_BADGE_ID,
      { expectedStatus: "1 active holder was skipped." },
    );
    expect(award).not.toHaveProperty("event_id");
  });
});

/** Closes the award badge dialog without changing selections. */
const closeAwardDialog = async (page) => {
  await page.getByRole("dialog", { name: "Award badge" }).getByRole("button", { name: "Cancel" }).click();
};

/** Counts active user_badge rows for the primary event host badge. */
const countActiveHostBadges = () =>
  Number(
    queryE2eDatabase(`
      select count(*)
      from user_badge
      where badge_id = '${HOST_BADGE_ID}'
        and event_id = '${TEST_EVENT_IDS.alpha.one}'
        and revoked_at is null
    `),
  );

/** Opens the primary event editor from the group dashboard. */
const openPrimaryEvent = async (page) => {
  await navigateToPath(page, "/dashboard/group?tab=events");
  const eventRow = page.getByRole("row", {
    name: new RegExp(TEST_EVENT_NAMES.alpha[0], "u"),
  });

  await waitForActionResponse(
    page,
    () =>
      eventRow
        .getByRole("button", {
          name: `Edit event: ${TEST_EVENT_NAMES.alpha[0]}`,
        })
        .click(),
    {
      method: "GET",
      urlIncludes: `/events/${TEST_EVENT_IDS.alpha.one}/update`,
    },
  );
};

/** Opens the primary event attendees section and waits for its table. */
const openPrimaryEventAttendees = async (page) => {
  await openPrimaryEvent(page);
  await waitForActionResponse(page, () => page.locator('button[data-section="attendees"]').click(), {
    method: "GET",
    urlIncludes: `/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
  });
  await expect(page.getByRole("table", { name: "Attendees list" })).toBeVisible();
};

/** Waits until every award job queued for the badge reaches a terminal status. */
const waitForSettledAwardJobs = async (badgeId) => {
  await expect
    .poll(
      () =>
        Number(
          queryE2eDatabase(`
            select count(*)
            from badge_award_job
            where badge_id = '${badgeId}'
              and status in ('pending', 'processing')
          `),
        ),
      { timeout: BADGE_AWARD_SETTLE_TIMEOUT_MS },
    )
    .toBe(0);
};
