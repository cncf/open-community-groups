import { expect, test } from "../../fixtures.js";
import { cleanupUserInboxConversations, findUserConversationId } from "../../data-graphs/inbox.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_IDS,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_USER_IDS,
} from "../../seed.js";
import { navigateToEvent, navigateToPath, uniqueName, waitForActionResponse } from "../../utils.js";

test.describe("group inbox workflow", () => {
  test("user contact is answered, closed, reopened and marked as spam", async ({
    member1Page,
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    // Prepare unique messages and the recipients of user messages
    const question = uniqueName("inbox question");
    const reply = uniqueName("inbox reply");
    const followUp = uniqueName("inbox follow-up");
    const organizerIds = [TEST_USER_IDS.eventsManager1, TEST_USER_IDS.organizer1];
    owned.defer(() => cleanupUserInboxConversations(TEST_USER_IDS.member1));

    // Open the contact modal from the public event page
    await navigateToEvent(member1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const modal = await openContactModal(member1Page);
    await expect(modal.getByLabel("Message")).toBeFocused();
    await expect(modal.getByLabel("Group", { exact: true })).toBeDisabled();
    await expect(modal.getByLabel("Group", { exact: true })).toHaveValue(TEST_GROUP_NAME);

    // Send the first message and check the organizer emails
    let checkpoint = notifications.checkpoint();
    await modal.getByLabel("Message").fill(question);
    await waitForActionResponse(member1Page, () => modal.getByRole("button", { name: "Send" }).click(), {
      method: "POST",
      urlEndsWith: `/event/${TEST_EVENT_IDS.alpha.one}/contact`,
    });
    await expect(modal.locator("[data-contact-sent-notice]")).toBeVisible();
    await expect(modal.locator("[data-contact-sent-notice]")).toBeFocused();
    notifications.expectNew(
      [
        {
          kind: "inbox-message-received",
          templateDataContains: { body: question, group_name: TEST_GROUP_NAME },
          userIds: organizerIds,
        },
      ],
      { since: checkpoint },
    );
    const inboxConversationId = findUserConversationId({
      groupId: TEST_GROUP_IDS.community1.alpha,
      userId: TEST_USER_IDS.member1,
    });

    // Reopen the contact modal and check it links to the open conversation
    await member1Page.keyboard.press("Escape");
    await expect(modal).toBeHidden();
    await openContactModal(member1Page);
    await expect(modal.locator("[data-contact-open-conversation]")).toBeVisible();
    await expect(modal.getByRole("link", { name: "Open conversation" })).toHaveAttribute(
      "href",
      `/dashboard/user?tab=inbox&conversation_id=${inboxConversationId}`,
    );
    await expect(modal.locator("#contact-form")).toHaveCount(0);

    // Open the conversation from the organizer inbox and check the open-count badge
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=inbox");
    const inboxMenuItem = organizerGroupPage.locator("#dashboard-menu").getByRole("link", { name: /Inbox/ });
    await expect(inboxMenuItem).toContainText("1");
    const conversationRow = organizerGroupPage.locator("[data-inbox-conversation-row]", {
      hasText: question,
    });
    await expect(conversationRow).toHaveAttribute("title", "View conversation with E2E Member One");
    await conversationRow.click();
    const organizerThread = organizerGroupPage.locator("#inbox-conversation");
    await expect(organizerThread.getByRole("heading", { name: TEST_EVENT_NAME })).toBeVisible();
    await expect(organizerThread).toContainText(`${TEST_GROUP_NAME} · `);
    await expect(organizerThread).toContainText("E2E Member One");
    await expect(organizerThread).toContainText(question);

    // Reply to the user and check the reply email
    checkpoint = notifications.checkpoint();
    await organizerThread.getByLabel("Reply").fill(reply);
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerThread.getByRole("button", { name: "Send" }).click(),
      { method: "POST", urlEndsWith: `/dashboard/group/inbox/${inboxConversationId}/replies` },
    );
    await expect(organizerGroupPage.locator("#inbox-conversation")).toContainText(reply);
    await expect(organizerGroupPage.locator("#inbox-conversation")).toContainText("Answered");
    notifications.expectNew(
      [
        {
          kind: "inbox-reply-received",
          templateDataContains: { body: reply, group_name: TEST_GROUP_NAME },
          userIds: [TEST_USER_IDS.member1],
        },
      ],
      { since: checkpoint },
    );

    // Close the conversation after confirming
    await organizerGroupPage.getByRole("button", { name: "Close conversation" }).click();
    const confirmAlert = organizerGroupPage.locator(".swal2-popup");
    await expect(confirmAlert).toContainText("Close this conversation?");
    await waitForActionResponse(
      organizerGroupPage,
      () => confirmAlert.getByRole("button", { name: "Close conversation" }).click(),
      { method: "PUT", urlEndsWith: `/dashboard/group/inbox/${inboxConversationId}/close` },
    );
    await expectActionNotice(organizerGroupPage, "Conversation closed.");
    await expect(organizerGroupPage.locator("#inbox-conversation")).toContainText("Closed");

    // Reopen the conversation with a follow-up from the user dashboard
    checkpoint = notifications.checkpoint();
    await navigateToPath(member1Page, `/dashboard/user?tab=inbox&conversation_id=${inboxConversationId}`);
    const userThread = member1Page.locator("#inbox-conversation");
    await expect(userThread.locator("[data-inbox-closed-notice]")).toBeVisible();
    await userThread.getByLabel("New message").fill(followUp);
    await waitForActionResponse(member1Page, () => userThread.getByRole("button", { name: "Send" }).click(), {
      method: "POST",
      urlEndsWith: `/dashboard/user/inbox/${inboxConversationId}/messages`,
    });
    await expect(member1Page.locator("#inbox-conversation")).toContainText(followUp);
    await expect(member1Page.locator("#inbox-conversation")).toContainText("Open");
    notifications.expectNew(
      [
        {
          kind: "inbox-message-received",
          templateDataContains: { body: followUp },
          userIds: organizerIds,
        },
      ],
      { since: checkpoint },
    );

    // Mark the conversation as spam after confirming
    await organizerGroupPage.getByRole("button", { name: "Mark as spam" }).click();
    await expect(confirmAlert).toContainText("Mark this conversation as spam?");
    await waitForActionResponse(
      organizerGroupPage,
      () => confirmAlert.getByRole("button", { name: "Mark as spam" }).click(),
      { method: "PUT", urlEndsWith: `/dashboard/group/inbox/${inboxConversationId}/mark-spam` },
    );
    await expectActionNotice(organizerGroupPage, "Conversation marked as spam.");
    await expect(organizerGroupPage.locator("[data-inbox-spam-notice]")).toBeVisible();

    // Reopen the contact modal and check the user can no longer contact the group
    await navigateToEvent(member1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    await openContactModal(member1Page);
    await expect(modal.locator("[data-contact-blocked]")).toContainText(
      `You can no longer contact ${TEST_GROUP_NAME}.`,
    );
    await expect(modal.locator("#contact-form")).toHaveCount(0);

    // Unmark the conversation as spam after confirming
    await organizerGroupPage.getByRole("button", { name: "Not spam" }).click();
    await expect(confirmAlert).toContainText("Unmark this conversation as spam?");
    await waitForActionResponse(
      organizerGroupPage,
      () => confirmAlert.getByRole("button", { name: "Not spam" }).click(),
      { method: "PUT", urlEndsWith: `/dashboard/group/inbox/${inboxConversationId}/unmark-spam` },
    );
    await expectActionNotice(organizerGroupPage, "Conversation unmarked as spam.");
    await expect(organizerGroupPage.locator("[data-inbox-spam-notice]")).toHaveCount(0);
    await expect(organizerGroupPage.locator("#inbox-conversation")).toContainText("Open");
  });
});

// Helpers.

/**
 * Verifies the focused notice reporting a conversation action.
 * @param {import("@playwright/test").Page} page - Page showing the conversation
 * @param {string} message - Expected notice message
 * @returns {Promise<void>}
 */
const expectActionNotice = async (page, message) => {
  const notice = page.locator("#inbox-conversation [data-inbox-action-notice]");
  await expect(notice).toBeVisible();
  await expect(notice).toHaveText(message);
  await expect(notice).toBeFocused();
  await expect(page.locator(".swal2-popup")).toBeHidden();
};

/**
 * Opens the contact organizers modal from the current event page and waits for its content.
 * @param {import("@playwright/test").Page} page - Page showing the event
 * @returns {Promise<import("@playwright/test").Locator>} Visible contact modal
 */
const openContactModal = async (page) => {
  await waitForActionResponse(page, () => page.getByRole("button", { name: "Contact organizers" }).click(), {
    method: "GET",
    urlEndsWith: `/event/${TEST_EVENT_IDS.alpha.one}/contact-modal`,
  });
  const modal = page.getByRole("dialog", { name: "Contact organizers" });
  await expect(modal).toBeVisible();

  return modal;
};
