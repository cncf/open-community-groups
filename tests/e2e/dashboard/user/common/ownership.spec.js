import { expect, test } from "../../../fixtures.js";
import { cleanupCredential, setupRevocableCredential } from "../../../data-graphs/badges.js";
import { setupCfsSubmission } from "../../../data-graphs/cfs.js";
import { cleanupInboxConversations, setupInboxConversation } from "../../../data-graphs/inbox.js";
import { queryCount, queryScalar, sqlUuid } from "../../../database.js";
import { TEST_EVENT_IDS, TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";
import { buildE2eUrl, uniqueName } from "../../../utils.js";

test.describe("user dashboard ownership", () => {
  test("badge revoke rejects a credential of another user", async ({ member1Page, owned }) => {
    const credential = owned.track(
      setupRevocableCredential({
        groupId: TEST_GROUP_IDS.community1.alpha,
        userId: TEST_USER_IDS.member2,
      }),
      cleanupCredential,
    );

    // Revoke the second member's credential as the first member.
    const response = await member1Page.request.delete(
      buildE2eUrl(`/dashboard/user/badges/${credential.userBadgeId}`),
    );

    // Verify the rejection leaves the credential active.
    await expectRejection(response, "awarded badge not found");
    expect(
      queryCount(`
        select count(*)
        from user_badge
        where user_badge_id = ${sqlUuid(credential.userBadgeId)}
        and revoked_at is null
      `),
      "active credential count",
    ).toBe(1);
  });

  test("session proposal delete rejects a proposal of another user", async ({ member1Page, owned }) => {
    const { proposalId } = owned.sessionProposal({
      title: uniqueName("member2 ownership proposal"),
      userId: TEST_USER_IDS.member2,
    });

    // Delete the second member's proposal as the first member.
    const response = await member1Page.request.delete(
      buildE2eUrl(`/dashboard/user/session-proposals/${proposalId}`),
    );

    // Verify the rejection keeps the proposal with its owner.
    await expectRejection(response, "session proposal not found");
    expect(
      queryScalar(`
        select user_id
        from session_proposal
        where session_proposal_id = ${sqlUuid(proposalId)}
      `),
      "proposal owner",
    ).toBe(TEST_USER_IDS.member2);
  });

  test("submission withdraw rejects a submission of another user", async ({ member1Page, owned }) => {
    // The proposal cleanup deletes its submission first.
    const { proposalId } = owned.sessionProposal({
      title: uniqueName("member2 ownership submission"),
      userId: TEST_USER_IDS.member2,
    });
    const submissionId = setupCfsSubmission({ eventId: TEST_EVENT_IDS.alpha.cfsSummit, proposalId });

    // Withdraw the second member's submission as the first member.
    const response = await member1Page.request.put(
      buildE2eUrl(`/dashboard/user/submissions/${submissionId}/withdraw`),
    );

    // Verify the rejection keeps the submission under review.
    await expectRejection(response, "submission not found or cannot be withdrawn");
    expect(
      queryScalar(`
        select status_id
        from cfs_submission
        where cfs_submission_id = ${sqlUuid(submissionId)}
      `),
      "submission status",
    ).toBe("not-reviewed");
  });

  test("inbox message rejects a conversation of another user", async ({ member1Page, owned }) => {
    const conversation = owned.track(
      setupInboxConversation({
        groupId: TEST_GROUP_IDS.community1.alpha,
        messages: [{ body: "Second member question for the ownership check." }],
        userId: TEST_USER_IDS.member2,
      }),
      ({ id }) => cleanupInboxConversations([id]),
    );

    // Post a follow-up to the second member's conversation as the first member.
    const response = await member1Page.request.post(
      buildE2eUrl(`/dashboard/user/inbox/${conversation.id}/messages`),
      { form: { body: "First member follow-up that must not be stored." } },
    );

    // Verify the rejection leaves the conversation untouched.
    await expectRejection(response, "conversation not found");
    expect(
      queryScalar(`
        select concat_ws(':', ic.inbox_conversation_status_id, count(im.inbox_message_id))
        from inbox_conversation ic
        join inbox_message im using (inbox_conversation_id)
        where ic.inbox_conversation_id = ${sqlUuid(conversation.id)}
        group by ic.inbox_conversation_status_id
      `),
      "conversation status and message count",
    ).toBe("open:1");
  });
});

// Helpers.

/**
 * Verifies a user dashboard action was rejected as unprocessable with the given message.
 * @param {import("@playwright/test").APIResponse} response - Action response.
 * @param {string} message - Expected rejection body.
 * @returns {Promise<void>}
 */
const expectRejection = async (response, message) => {
  expect(response.status(), "rejection status").toBe(422);
  expect(await response.text(), "rejection message").toBe(message);
};
