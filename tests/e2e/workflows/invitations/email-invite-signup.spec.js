import { expect, test } from "../../fixtures.js";
import { cleanupEventsByIds, insertOwnedEvent } from "../../data-graphs/events.js";
import { cleanupTemporaryUser } from "../../data-graphs/users.js";
import { queryScalar, sqlString, sqlUuid } from "../../database.js";
import { openAttendeesTab } from "../../dashboard/group/events/attendees-helpers.js";
import { openEventOfferActions } from "../../dashboard/user/invitations/helpers.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../seed.js";
import {
  buildAuthUser,
  dismissAlert,
  navigateToPath,
  uniqueName,
  waitForActionResponse,
} from "../../utils.js";
import { logInWithEmail, signUpWithEmail, waitForEmailVerificationCode } from "../auth/helpers.js";

/** Reads the account behind an email as parsed JSON, or null when none exists. */
const readUserByEmail = (email) => {
  const row = queryScalar(`
    select json_build_object(
      'email_verified', email_verified,
      'registration_status', registration_status,
      'user_id', user_id,
      'username', username
    )
    from "user"
    where email = ${sqlString(email)}
  `);

  return row === "" ? null : JSON.parse(row);
};

/** Reads the admission offers and attendee status of one user for an event as parsed JSON. */
const readEnrollment = (eventId, userId) =>
  JSON.parse(
    queryScalar(`
      select json_build_object(
        'attendee_status', (
          select ea.status
          from event_attendee ea
          where ea.event_id = ${sqlUuid(eventId)}
          and ea.user_id = ${sqlUuid(userId)}
        ),
        'offers', coalesce((
          select json_agg(json_build_object(
            'organizer_user_id', ao.organizer_user_id,
            'source', ao.source,
            'status', ao.status
          ))
          from admission_offer ao
          where ao.event_id = ${sqlUuid(eventId)}
          and ao.user_id = ${sqlUuid(userId)}
        ), '[]'::json)
      )
    `),
  );

test.describe("email invitation sign-up workflow", () => {
  test("an email invitee signs up, verifies, logs in and claims the offer", async ({
    browser,
    browserHealth,
    notifications,
    organizerGroupPage,
  }) => {
    // Create a free published event in the organizer's group and a fresh invitee identity.
    const event = insertOwnedEvent({
      groupId: TEST_GROUP_IDS.community1.alpha,
      name: uniqueName("email invite"),
    });
    const invitee = buildAuthUser();
    const context = await browser.newContext();
    browserHealth.track(context);
    const guestPage = await context.newPage();

    try {
      // Open the invitation modal from the event attendees tab.
      const attendeesContent = await openAttendeesTab(organizerGroupPage, event.name, event.eventId);
      await attendeesContent.getByRole("button", { name: "Open attendee actions menu" }).click();
      await attendeesContent.getByRole("menuitem", { name: "Invite attendee" }).click();
      const modal = organizerGroupPage.locator("#attendee-invitation-modal");
      await expect(modal).toBeVisible();

      // Choose the "Invite by email" option for an address without an account.
      await modal.locator("#attendee-invitation-search-input").fill(invitee.email);
      await modal.getByRole("button", { name: `Invite by email ${invitee.email}` }).click();
      await expect(modal.locator("#attendee-invitation-selected-user")).toContainText(invitee.email);

      // Send the invitation and verify the form submits the email target only.
      const inviteRequest = organizerGroupPage.waitForRequest(
        (request) =>
          request.method() === "POST" && request.url().includes(`/events/${event.eventId}/attendees/invite`),
      );
      await waitForActionResponse(
        organizerGroupPage,
        () => modal.locator("#submit-attendee-invitation").click(),
        {
          method: "POST",
          status: 201,
          urlIncludes: `/dashboard/group/events/${event.eventId}/attendees/invite`,
        },
      );
      const inviteData = new URLSearchParams((await inviteRequest).postData() ?? "");
      expect(inviteData.get("email")).toBe(invitee.email);
      expect(inviteData.has("user_id")).toBe(false);
      await dismissAlert(organizerGroupPage, { message: "Invitation sent." });

      // Verify the invitation pre-registered the email with a pending organizer offer.
      const preRegistered = readUserByEmail(invitee.email);
      expect(preRegistered).toMatchObject({
        email_verified: false,
        registration_status: "pre-registered",
        username: expect.stringMatching(/^invited-/u),
      });
      const userId = preRegistered.user_id;
      expect(readEnrollment(event.eventId, userId)).toEqual({
        attendee_status: null,
        offers: [
          {
            organizer_user_id: TEST_USER_IDS.organizer1,
            source: "organizer_invitation",
            status: "pending",
          },
        ],
      });
      notifications.expectNew([
        {
          kind: "event-admission-offer-created",
          templateDataContains: { event_id: event.eventId, user_id: userId },
          userIds: [userId],
        },
      ]);

      // Sign up with the invited email and verify the placeholder account is activated.
      const signUpCheckpoint = notifications.checkpoint();
      await signUpWithEmail(guestPage, invitee);
      expect(readUserByEmail(invitee.email)).toEqual({
        email_verified: false,
        registration_status: "registered",
        user_id: userId,
        username: invitee.username,
      });
      notifications.expectNew([{ kind: "email-verification", userIds: [userId] }], {
        since: signUpCheckpoint,
      });

      // Verify the email through the issued code.
      const verificationCode = await waitForEmailVerificationCode(invitee.email);
      await navigateToPath(guestPage, `/verify-email/${verificationCode}`);
      await expect(
        guestPage.getByText("Email verified successfully. You can now log in using your credentials."),
      ).toBeVisible();

      // Log in through the invitations tab and dismiss the profile prompt.
      await navigateToPath(guestPage, "/dashboard/user?tab=invitations");
      await expect(guestPage).toHaveURL(/\/log-in\?next_url=/u);
      await Promise.all([
        guestPage.waitForURL((url) => url.pathname === "/dashboard/user"),
        logInWithEmail(guestPage, invitee),
      ]);
      const profilePrompt = guestPage.locator(".swal2-popup", { hasText: "Complete your profile" });
      await expect(profilePrompt).toBeVisible();
      await guestPage.keyboard.press("Escape");
      await expect(profilePrompt).toBeHidden();

      // Claim the organizer invitation from the invitations tab.
      const offerRow = guestPage.locator("#dashboard-content tr", { hasText: event.name });
      await expect(offerRow).toContainText("Organizer invitation");
      await openEventOfferActions(offerRow);
      await offerRow.getByRole("menuitem", { name: "Claim offer" }).click();
      const claimModal = guestPage.getByRole("dialog", { name: "Claim offer" });
      await expect(claimModal).toBeVisible();
      await waitForActionResponse(
        guestPage,
        () => claimModal.getByRole("button", { name: "Claim offer", exact: true }).click(),
        {
          method: "POST",
          urlIncludes: `/event/${event.eventId}/checkout`,
        },
      );
      await dismissAlert(guestPage, { message: "Your RSVP has been confirmed." });
      await expect(offerRow).toHaveCount(0);

      // Verify the invitee is a confirmed attendee and the offer is completed.
      expect(readEnrollment(event.eventId, userId)).toEqual({
        attendee_status: "confirmed",
        offers: [
          {
            organizer_user_id: TEST_USER_IDS.organizer1,
            source: "organizer_invitation",
            status: "completed",
          },
        ],
      });
    } finally {
      // Remove the event graph, then the invitee's notifications and account.
      cleanupEventsByIds([event.eventId]);
      const inviteeUserId = queryScalar(
        `select user_id from "user" where email = ${sqlString(invitee.email)}`,
      );
      if (inviteeUserId !== "") {
        cleanupTemporaryUser(inviteeUserId);
      }
      await context.close();
    }
  });
});
