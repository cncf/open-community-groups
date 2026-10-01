import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase } from "../../database.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import {
  TEST_COMMUNITY_IDS,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_IDS,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_IDS,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_INBOX_CONVERSATION,
  TEST_USER_IDS,
} from "../../seed.js";
import {
  navigateToEvent,
  navigateToPath,
  selectGroupContext,
  uniqueName,
  waitForActionResponse,
} from "../../utils.js";

const MOBILE_NOTICE = "This dashboard is not optimized yet for mobile devices";
const NO_INBOX_ACCESS_WARNING = "You don't have Inbox access for the selected group.";

test.describe("group inbox workflow", () => {
  test("user contact is answered, closed, reopened and marked as spam", async ({
    member1Page,
    organizerGroupPage,
  }) => {
    // Prepare unique messages and the recipients of user messages
    const question = uniqueName("inbox question");
    const reply = uniqueName("inbox reply");
    const followUp = uniqueName("inbox follow-up");
    const organizerIds = [TEST_USER_IDS.eventsManager1, TEST_USER_IDS.organizer1];
    const notificationIds = [];

    try {
      // Open the contact modal from the public event page
      await navigateToEvent(member1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
      await member1Page.getByRole("button", { name: "Contact organizers" }).click();
      const modal = member1Page.getByRole("dialog", { name: "Contact organizers" });
      await expect(modal).toBeVisible();
      await expect(modal.getByLabel("Message")).toBeFocused();
      await expect(modal.getByLabel("To", { exact: true })).toBeDisabled();
      await expect(modal.getByLabel("To", { exact: true })).toHaveValue(TEST_GROUP_NAME);

      // Send the first message and check the organizer emails
      let snapshot = snapshotNotifications();
      await modal.getByLabel("Message").fill(question);
      await waitForActionResponse(member1Page, () => modal.getByRole("button", { name: "Send" }).click(), {
        method: "POST",
        urlEndsWith: `/event/${TEST_EVENT_IDS.alpha.one}/contact`,
      });
      await expect(modal.locator("[data-contact-sent-notice]")).toBeVisible();
      await expect(modal.locator("[data-contact-sent-notice]")).toBeFocused();
      notificationIds.push(
        ...expectNewNotifications(snapshot, [
          {
            kind: "inbox-message-received",
            templateDataContains: { body: question, group_name: TEST_GROUP_NAME },
            userIds: organizerIds,
          },
        ]),
      );
      const inboxConversationId = findMemberConversationId();

      // Open the conversation from the organizer inbox and check the open-count badge
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=inbox");
      const inboxMenuItem = organizerGroupPage
        .locator("#dashboard-menu")
        .getByRole("link", { name: /Inbox/ });
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
      snapshot = snapshotNotifications();
      await organizerThread.getByLabel("Reply").fill(reply);
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerThread.getByRole("button", { name: "Send" }).click(),
        { method: "POST", urlEndsWith: `/dashboard/group/inbox/${inboxConversationId}/replies` },
      );
      await expect(organizerGroupPage.locator("#inbox-conversation")).toContainText(reply);
      await expect(organizerGroupPage.locator("#inbox-conversation")).toContainText("Answered");
      notificationIds.push(
        ...expectNewNotifications(snapshot, [
          {
            kind: "inbox-reply-received",
            templateDataContains: { body: reply, group_name: TEST_GROUP_NAME },
            userIds: [TEST_USER_IDS.member1],
          },
        ]),
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
      snapshot = snapshotNotifications();
      await navigateToPath(member1Page, `/dashboard/user?tab=inbox&conversation_id=${inboxConversationId}`);
      const userThread = member1Page.locator("#inbox-conversation");
      await expect(userThread.locator("[data-inbox-closed-notice]")).toBeVisible();
      await userThread.getByLabel("New message").fill(followUp);
      await waitForActionResponse(
        member1Page,
        () => userThread.getByRole("button", { name: "Send" }).click(),
        {
          method: "POST",
          urlEndsWith: `/dashboard/user/inbox/${inboxConversationId}/messages`,
        },
      );
      await expect(member1Page.locator("#inbox-conversation")).toContainText(followUp);
      await expect(member1Page.locator("#inbox-conversation")).toContainText("Open");
      notificationIds.push(
        ...expectNewNotifications(snapshot, [
          {
            kind: "inbox-message-received",
            templateDataContains: { body: followUp },
            userIds: organizerIds,
          },
        ]),
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
    } finally {
      // Remove the notifications and the member conversation
      deleteNotifications(notificationIds);
      deleteMemberConversations();
    }
  });

  test("organizer opens a conversation from the inbox with the keyboard", async ({ organizerGroupPage }) => {
    // Focus the seeded conversation row in the group inbox
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=inbox");
    const conversationRow = organizerGroupPage.locator("[data-inbox-conversation-row]", {
      hasText: TEST_INBOX_CONVERSATION.reply,
    });
    await conversationRow.focus();
    await expect(conversationRow).toBeFocused();

    // Verify Enter opens the conversation thread
    await organizerGroupPage.keyboard.press("Enter");
    const organizerThread = organizerGroupPage.locator("#inbox-conversation");
    await expect(organizerThread.getByRole("heading", { name: TEST_EVENT_NAME })).toBeVisible();
    await expect(organizerThread).toContainText("E2E Member Two");
    await expect(organizerThread).toContainText(TEST_INBOX_CONVERSATION.question);
  });

  test("member reads a conversation with names and the group context", async ({ member2Page }) => {
    // Load the seeded conversation from the user dashboard
    await navigateToPath(
      member2Page,
      `/dashboard/user?tab=inbox&conversation_id=${TEST_INBOX_CONVERSATION.id}`,
    );
    const userThread = member2Page.locator("#inbox-conversation");

    // Verify the header shows the group and community above the event name
    await expect(userThread.getByRole("heading", { name: TEST_EVENT_NAME })).toBeVisible();
    await expect(userThread.locator("header")).toContainText(`${TEST_GROUP_NAME} · ${TEST_COMMUNITY_TITLE}`);

    // Verify messages show the member name and the organizer label instead of "You"
    const messages = userThread.getByRole("list", { name: "Messages" });
    await expect(messages).toContainText("E2E Member Two");
    await expect(messages).toContainText("E2E Organizer One");
    await expect(messages.getByText("Organizer", { exact: true })).toBeVisible();
    await expect(messages.getByText("You", { exact: true })).toHaveCount(0);
  });

  test("organizer conversation header adapts actions and dates to the viewport", async ({
    organizerGroupPage,
  }) => {
    // Load the seeded conversation on a wide screen
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });
    await navigateToPath(
      organizerGroupPage,
      `/dashboard/group?tab=inbox&conversation_id=${TEST_INBOX_CONVERSATION.id}`,
    );
    const header = organizerGroupPage.locator("#inbox-conversation header");
    const closeButton = organizerGroupPage.getByRole("button", { name: "Close conversation" });
    const dates = header.locator("time");

    // Verify wide screens show the dates and keep the actions inside the header
    await expect(dates.first()).toBeVisible();
    await expect(dates.last()).toBeVisible();
    await expectActionsInsideHeader(header, closeButton, true);

    // Verify xl screens show the dates and move the actions below the header
    await organizerGroupPage.setViewportSize({ width: 1358, height: 900 });
    await expect(dates.first()).toBeVisible();
    await expect(dates.last()).toBeVisible();
    await expectActionsInsideHeader(header, closeButton, false);

    // Verify lg screens hide the dates and keep the actions inside the header
    await organizerGroupPage.setViewportSize({ width: 1100, height: 900 });
    await expect(dates.first()).toBeHidden();
    await expect(dates.last()).toBeHidden();
    await expectActionsInsideHeader(header, closeButton, true);
  });

  test("organizer contact modal links to the group inbox", async ({ organizerGroupPage }) => {
    // Open the contact modal of an event of the organized group
    await navigateToEvent(organizerGroupPage, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    await organizerGroupPage.getByRole("button", { name: "Contact organizers" }).click();
    const modal = organizerGroupPage.getByRole("dialog", { name: "Contact organizers" });

    // Verify the organizer note links to the group inbox instead of the form
    await expect(modal.locator("[data-contact-organizer-note]")).toContainText(
      `You organize ${TEST_GROUP_NAME}.`,
    );
    await expect(modal.getByRole("link", { name: "Open group Inbox" })).toHaveAttribute(
      "href",
      "/dashboard/group?tab=inbox",
    );
    await expect(modal.locator("#contact-form")).toHaveCount(0);
  });

  test("group viewer contact modal has no inbox link", async ({ groupViewerPage }) => {
    // Open the contact modal of an event of the viewed group
    await navigateToEvent(groupViewerPage, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    await groupViewerPage.getByRole("button", { name: "Contact organizers" }).click();
    const modal = groupViewerPage.getByRole("dialog", { name: "Contact organizers" });

    // Verify the team note replaces the form without linking to the inbox
    await expect(modal.locator("[data-contact-organizer-note]")).toContainText(
      `You're a team member of the ${TEST_GROUP_NAME} group.`,
    );
    await expect(modal.getByRole("link", { name: "Open group Inbox" })).toHaveCount(0);
    await expect(modal.locator("#contact-form")).toHaveCount(0);
  });

  test("group viewer has no inbox access", async ({ groupViewerPage }) => {
    // Load the inbox tab of a read-only team member
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=inbox");

    // Verify the menu hides the inbox and the tab falls back with a warning
    await expect(groupViewerPage.locator("#dashboard-menu").getByRole("link", { name: /Inbox/ })).toHaveCount(
      0,
    );
    await expect(groupViewerPage.getByText(NO_INBOX_ACCESS_WARNING)).toBeVisible();
  });

  test("organizer arriving from the email with another group selected switches group", async ({
    organizerGroupPage,
  }) => {
    try {
      // Select a group where the organizer only views the dashboard
      await selectGroupContext(
        organizerGroupPage,
        TEST_COMMUNITY_IDS.community1,
        TEST_GROUP_IDS.community1.gamma,
      );

      // Open the inbox link used by the email
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=inbox");
      await expect(organizerGroupPage.getByText(NO_INBOX_ACCESS_WARNING)).toBeVisible();
      await expect(organizerGroupPage.locator("group-selector")).toBeVisible();

      // Switch to the group named in the email and reload the inbox
      await selectGroupContext(
        organizerGroupPage,
        TEST_COMMUNITY_IDS.community1,
        TEST_GROUP_IDS.community1.alpha,
      );
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=inbox");

      // Verify the inbox of the selected group lists the seeded conversation
      await expect(organizerGroupPage.getByText(NO_INBOX_ACCESS_WARNING)).toHaveCount(0);
      await expect(organizerGroupPage.locator("[data-inbox-list]")).toContainText(
        TEST_INBOX_CONVERSATION.reply,
      );
    } finally {
      // Restore the organizer group selection
      await selectGroupContext(
        organizerGroupPage,
        TEST_COMMUNITY_IDS.community1,
        TEST_GROUP_IDS.community1.alpha,
      );
    }
  });

  test("logged-out visitor gets a sign-in prompt", async ({ page }) => {
    // Open the contact modal without a session
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const opener = page.getByRole("button", { name: "Contact organizers" });
    await opener.click();

    // Verify the modal asks the visitor to sign in and returns to the event page
    const modal = page.getByRole("dialog", { name: "Contact organizers" });
    await expect(modal.locator("[data-contact-sign-in]")).toBeVisible();
    await expect(modal.getByRole("link", { name: "Sign in" })).toHaveAttribute(
      "href",
      `/log-in?next_url=/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`,
    );

    // Verify Escape closes the modal and focus returns to the opener
    await page.keyboard.press("Escape");
    await expect(modal).toBeHidden();
    await expect(opener).toBeFocused();
  });

  test("group team member gets the organizer note", async ({ organizerGroupPage }) => {
    // Open the contact modal as an organizer of the event group
    await navigateToEvent(organizerGroupPage, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    await organizerGroupPage.getByRole("button", { name: "Contact organizers" }).click();
    const modal = organizerGroupPage.getByRole("dialog", { name: "Contact organizers" });

    // Verify the modal points to the group inbox instead of the contact form
    await expect(modal.locator("[data-contact-organizer-note]")).toBeVisible();
    await expect(modal.getByRole("link", { name: "Open group Inbox" })).toBeVisible();
    await expect(modal.getByLabel("Message")).toHaveCount(0);
  });

  test("user over the daily conversation limit gets the limit notice", async ({ member1Page }) => {
    try {
      // Start today's maximum number of conversations for the first member
      insertClosedMemberConversations(3);

      // Open the contact modal from the public event page
      await navigateToEvent(member1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
      await member1Page.getByRole("button", { name: "Contact organizers" }).click();
      const modal = member1Page.getByRole("dialog", { name: "Contact organizers" });

      // Verify the modal shows the limit notice instead of the contact form
      await expect(modal.locator("[data-contact-limit-reached]")).toBeVisible();
      await expect(modal.getByLabel("Message")).toHaveCount(0);
    } finally {
      // Remove the member conversations
      deleteMemberConversations();
    }
  });

  test("inbox stays desktop only on mobile @mobile", async ({ member2Page, organizerGroupPage }) => {
    // Verify the user inbox shows the mobile notice instead of the list
    await navigateToPath(member2Page, "/dashboard/user?tab=inbox");
    await expect(member2Page.getByText(MOBILE_NOTICE)).toBeVisible();
    await expect(member2Page.locator("[data-inbox-list]")).toBeHidden();

    // Verify the group inbox shows the mobile notice instead of the list
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=inbox");
    await expect(organizerGroupPage.getByText(MOBILE_NOTICE)).toBeVisible();
    await expect(organizerGroupPage.locator("[data-inbox-list]")).toBeHidden();
  });
});

// Helpers.

/** Deletes every inbox conversation of the first member with its messages. */
const deleteMemberConversations = () => {
  queryE2eDatabase(`
    delete from inbox_message
    where inbox_conversation_id in (
      select inbox_conversation_id from inbox_conversation where user_id = '${TEST_USER_IDS.member1}'
    );
    delete from inbox_conversation where user_id = '${TEST_USER_IDS.member1}';
  `);
};

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
 * Verifies whether a conversation action sits inside the header box.
 * @param {import("@playwright/test").Locator} header - Conversation header
 * @param {import("@playwright/test").Locator} action - Conversation action button
 * @param {boolean} inside - Whether the action is expected inside the header
 * @returns {Promise<void>}
 */
const expectActionsInsideHeader = async (header, action, inside) => {
  await expect
    .poll(async () => {
      const headerBox = await header.boundingBox();
      const actionBox = await action.boundingBox();
      return actionBox.y + actionBox.height <= headerBox.y + headerBox.height;
    })
    .toBe(inside);
};

/** Returns the conversation the first member started with the primary group. */
const findMemberConversationId = () =>
  queryE2eDatabase(`
    select inbox_conversation_id
    from inbox_conversation
    where user_id = '${TEST_USER_IDS.member1}'
    and group_id = '${TEST_GROUP_IDS.community1.alpha}'
  `);

/**
 * Inserts closed conversations started today by the first member with the
 * primary group, so they count towards the daily limit without an open thread.
 * @param {number} count Number of conversations to insert.
 */
const insertClosedMemberConversations = (count) => {
  queryE2eDatabase(`
    insert into inbox_conversation (group_id, inbox_conversation_status_id, user_id)
    select '${TEST_GROUP_IDS.community1.alpha}', 'closed', '${TEST_USER_IDS.member1}'
    from generate_series(1, ${count});
  `);
};
