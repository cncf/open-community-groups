import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import { TEST_REGISTRATION_WINDOW_EVENTS, TEST_USER_IDS } from "../../../seed.js";
import { waitForActionResponse } from "../../../utils.js";
import { openUserDashboardPath } from "../helpers.js";
import { openEventOfferActions } from "./helpers.js";

const CLOSED_MANUAL_INVITATION_OFFER_ID = "59555555-5555-5555-5555-555555555910";

test.describe("user dashboard invitations view — answers", () => {
  test("manual invitation answers can be submitted after registration closes", async ({ member2Page }) => {
    const event = TEST_REGISTRATION_WINDOW_EVENTS.questionsManualInviteClosed;

    // Restore the closed-window organizer invitation before loading it.
    resetClosedManualInvitation();

    try {
      // Load the invitation and open its claim flow.
      await openUserDashboardPath("/dashboard/user?tab=invitations", member2Page);
      const dashboardContent = member2Page.locator("#dashboard-content");
      const offerRow = dashboardContent.locator("tr", {
        hasText: event.name,
      });
      await expect(offerRow).toContainText("Organizer invitation");
      await openEventOfferActions(offerRow);
      await offerRow.getByRole("menuitem", { name: "Claim offer" }).click();

      // Answer the required registration question in the claim modal.
      const claimModal = member2Page.getByRole("dialog", {
        name: "Claim offer",
      });
      const answer = "I need a quiet workspace after the public registration deadline.";
      await expect(claimModal).toContainText("Registration questions");
      await claimModal
        .locator("fieldset", {
          hasText: "What should the organizers know?",
        })
        .locator("textarea")
        .fill(answer);

      // Claim the offer and verify its serialized answer contract.
      const claimRequest = member2Page.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes(`/event/${event.id}/checkout`),
      );
      await waitForActionResponse(
        member2Page,
        () => claimModal.getByRole("button", { name: "Claim offer", exact: true }).click(),
        {
          method: "POST",
          urlIncludes: `/event/${event.id}/checkout`,
        },
      );
      const requestData = new URLSearchParams((await claimRequest).postData() ?? "");
      expect(requestData.get("admission_offer_id")).toBe(CLOSED_MANUAL_INVITATION_OFFER_ID);
      expect(JSON.parse(requestData.get("registration_answers"))).toEqual({
        answers: [
          {
            question_id: "57555555-5555-5555-5555-555555555910",
            value: answer,
          },
        ],
      });
      await expect(offerRow).toHaveCount(0);

      // The accepted offer becomes durable attendance despite the closed window.
      await openUserDashboardPath("/dashboard/user?tab=events", member2Page);
      const eventRow = member2Page.locator("#dashboard-content tr", {
        hasText: event.name,
      });
      await expect(eventRow).toContainText("Attendee");
    } finally {
      // Restore the seeded invitation for later tests.
      resetClosedManualInvitation();
    }
  });
});

/** Restores the manual invitation used to claim an offer after registration closes. */
const resetClosedManualInvitation = () => {
  const eventId = TEST_REGISTRATION_WINDOW_EVENTS.questionsManualInviteClosed.id;

  queryE2eDatabase(`
    delete from event_purchase
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member2}';

    delete from event_attendee
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member2}';

    delete from admission_offer
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member2}';

    insert into admission_offer (
      admission_offer_id,
      event_id,
      event_ticket_type_id,
      expires_at,
      source,
      status,
      user_id
    ) values (
      '${CLOSED_MANUAL_INVITATION_OFFER_ID}',
      '${eventId}',
      (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '${eventId}'
        order by "order"
        limit 1
      ),
      '2099-12-31 00:00:00+00',
      'organizer_invitation',
      'pending',
      '${TEST_USER_IDS.member2}'
    );
  `);
};
