import { expect, test } from "../../../fixtures.js";
import { cleanupInboxConversations, setupInboxConversation } from "../../../data-graphs/inbox.js";
import {
  TEST_COMMUNITY_IDS,
  TEST_EVENT_IDS,
  TEST_EVENT_NAME,
  TEST_GROUP_IDS,
  TEST_GROUP_NAME,
  TEST_INBOX_CONVERSATION,
  TEST_USER_IDS,
} from "../../../seed.js";
import {
  confirmAlert,
  navigateToPath,
  selectGroupContext,
  uniqueName,
  waitForActionResponse,
} from "../../../utils.js";
import { expectInboxStatusFilter } from "../../inbox-helpers.js";

const INBOX_PATH = "/dashboard/group?tab=inbox";
const LIST_PATH = "/dashboard/group/inbox";
const MOBILE_NOTICE = "This dashboard is not optimized yet for mobile devices";
const NO_INBOX_ACCESS_WARNING = "You don't have Inbox access for the selected group.";

test.describe("group dashboard inbox view", () => {
  test("organizer opens a conversation from the inbox with the keyboard", async ({ organizerGroupPage }) => {
    // Focus the seeded conversation row in the group inbox
    await navigateToPath(organizerGroupPage, INBOX_PATH);
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

  test("organizer conversation header adapts actions and dates to the viewport", async ({
    organizerGroupPage,
  }) => {
    // Load the seeded conversation on a wide screen
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });
    await navigateToPath(organizerGroupPage, `${INBOX_PATH}&conversation_id=${TEST_INBOX_CONVERSATION.id}`);
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

  test("group viewer has no inbox access", async ({ groupViewerPage }) => {
    // Load the inbox tab of a read-only team member
    await navigateToPath(groupViewerPage, INBOX_PATH);

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
      await navigateToPath(organizerGroupPage, INBOX_PATH);
      await expect(organizerGroupPage.getByText(NO_INBOX_ACCESS_WARNING)).toBeVisible();
      await expect(organizerGroupPage.locator("group-selector")).toBeVisible();

      // Switch to the group named in the email and reload the inbox
      await selectGroupContext(
        organizerGroupPage,
        TEST_COMMUNITY_IDS.community1,
        TEST_GROUP_IDS.community1.alpha,
      );
      await navigateToPath(organizerGroupPage, INBOX_PATH);

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

  test("organizer filters conversations by status including spam", async ({ organizerGroupPage, owned }) => {
    // Prepare a spam conversation next to the seeded answered one
    const spamQuestion = uniqueName("spam inbox question");
    trackConversation(owned, {
      eventId: TEST_EVENT_IDS.alpha.one,
      messages: [{ body: spamQuestion }],
      status: "spam",
      userId: TEST_USER_IDS.member1,
    });

    // Verify the unfiltered inbox leaves the spam conversation out
    await navigateToPath(organizerGroupPage, INBOX_PATH);
    const rows = organizerGroupPage.locator("[data-inbox-conversation-row]");
    await expect(rows.filter({ hasText: TEST_INBOX_CONVERSATION.reply })).toBeVisible();
    await expect(rows.filter({ hasText: spamQuestion })).toHaveCount(0);

    // Verify the status filter offers spam and lists only the spam conversation
    await expectInboxStatusFilter(organizerGroupPage, {
      listPath: LIST_PATH,
      matchingRowText: spamQuestion,
      options: ["All", "Open", "Answered", "Closed", "Spam"],
      otherRowText: TEST_INBOX_CONVERSATION.reply,
      status: { label: "Spam", value: "spam" },
    });
  });

  test("organizer sees the empty inbox of a group without conversations", async ({
    organizerEmptyGroupPage,
  }) => {
    // Load the inbox of the inactive empty group
    await navigateToPath(organizerEmptyGroupPage, INBOX_PATH);

    // Verify the menu still exposes the active inbox tab without an open-count badge
    const inboxMenuItem = organizerEmptyGroupPage
      .locator("#dashboard-menu")
      .getByRole("link", { name: "Inbox", exact: true });
    await expect(inboxMenuItem).toHaveAttribute("aria-current", "page");

    // Verify the unfiltered empty state explains where conversations come from
    const list = organizerEmptyGroupPage.locator("[data-inbox-list]");
    await expect(list.getByText("No conversations yet").filter({ visible: true })).toBeVisible();
    await expect(
      list
        .getByText("Questions users send from this group's event pages will appear here.")
        .filter({ visible: true }),
    ).toBeVisible();
    await expect(list.locator("[data-inbox-conversation-row]")).toHaveCount(0);
  });

  test("organizer closes the read-only conversation of a deleted user", async ({
    organizerGroupPage,
    owned,
  }) => {
    // Prepare an open conversation whose user deleted their account
    const question = uniqueName("deleted user inbox question");
    const { id } = trackConversation(owned, { messages: [{ body: question }], status: "open", userId: null });

    // Load the conversation from the group dashboard
    await navigateToPath(organizerGroupPage, `${INBOX_PATH}&conversation_id=${id}`);
    const organizerThread = organizerGroupPage.locator("#inbox-conversation");
    await expect(organizerThread.getByRole("heading", { name: "Deleted user" })).toBeVisible();
    await expect(organizerThread.getByRole("list", { name: "Messages" })).toContainText(question);

    // Verify the thread is read-only but can still be closed
    const readOnlyNotice = organizerThread.locator("[data-inbox-read-only-notice]");
    await expect(readOnlyNotice).toContainText(
      "The user deleted their account, so this conversation is read-only.",
    );
    await expect(readOnlyNotice).toContainText("You can still close it.");
    await expect(organizerThread.locator("#inbox-message-form")).toHaveCount(0);

    // Close the conversation after confirming
    await organizerThread.getByRole("button", { name: "Close conversation" }).click();
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        confirmAlert(organizerGroupPage, {
          button: "Close conversation",
          message: "Close this conversation?",
        }),
      { method: "PUT", pathname: `${LIST_PATH}/${id}/close`, status: 200 },
    );

    // Verify the closed thread stays read-only without the close action
    const closedThread = organizerGroupPage.locator("#inbox-conversation");
    await expect(closedThread.locator("[data-inbox-action-notice]")).toHaveText("Conversation closed.");
    await expect(closedThread.locator("header")).toContainText("Closed");
    await expect(closedThread.locator("[data-inbox-read-only-notice]")).not.toContainText(
      "You can still close it.",
    );
    await expect(closedThread.getByRole("button", { name: "Close conversation" })).toHaveCount(0);
    await expect(closedThread.locator("#inbox-message-form")).toHaveCount(0);
  });

  test("events manager replies to a conversation and the user is notified", async ({
    eventsManagerGroupPage,
    notifications,
    owned,
  }) => {
    // Prepare an open conversation of the first member
    const question = uniqueName("inbox question");
    const reply = uniqueName("inbox reply");
    const { id } = trackConversation(owned, {
      eventId: TEST_EVENT_IDS.alpha.one,
      messages: [{ body: question }],
      status: "open",
      userId: TEST_USER_IDS.member1,
    });

    // Load the conversation from the group dashboard
    await navigateToPath(eventsManagerGroupPage, `${INBOX_PATH}&conversation_id=${id}`);
    const thread = eventsManagerGroupPage.locator("#inbox-conversation");
    await expect(thread.getByRole("heading", { name: TEST_EVENT_NAME })).toBeVisible();
    await expect(thread).toContainText(question);

    // Reply to the user
    await thread.getByLabel("Reply").fill(reply);
    await waitForActionResponse(
      eventsManagerGroupPage,
      () => thread.getByRole("button", { name: "Send" }).click(),
      {
        method: "POST",
        pathname: `${LIST_PATH}/${id}/replies`,
        status: 200,
      },
    );

    // Verify the answered thread shows the reply from the events manager
    const answeredThread = eventsManagerGroupPage.locator("#inbox-conversation");
    await expect(answeredThread.getByRole("list", { name: "Messages" })).toContainText(reply);
    await expect(answeredThread.locator("header")).toContainText("Answered");

    // Verify the user is emailed the reply
    notifications.expectNew([
      {
        kind: "inbox-reply-received",
        templateDataContains: { body: reply, group_name: TEST_GROUP_NAME },
        userIds: [TEST_USER_IDS.member1],
      },
    ]);
  });

  test("group inbox stays desktop only on mobile @mobile", async ({ organizerGroupPage }) => {
    // Load the group inbox on a mobile viewport
    await navigateToPath(organizerGroupPage, INBOX_PATH);

    // Verify the mobile notice replaces the conversation list
    await expect(organizerGroupPage.getByText(MOBILE_NOTICE)).toBeVisible();
    await expect(organizerGroupPage.locator("[data-inbox-list]")).toBeHidden();
  });
});

// Helpers.

/**
 * Inserts an owned conversation with the primary group, deleted at teardown.
 * @param {{ track: Function }} owned - Owned data registry of the test.
 * @param {Omit<Parameters<typeof setupInboxConversation>[0], "groupId">} options - Conversation
 *   shape without the group.
 * @returns {{ id: string, messageIds: string[] }} Conversation and message identifiers.
 */
const trackConversation = (owned, options) =>
  owned.track(setupInboxConversation({ ...options, groupId: TEST_GROUP_IDS.community1.alpha }), ({ id }) =>
    cleanupInboxConversations([id]),
  );

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
