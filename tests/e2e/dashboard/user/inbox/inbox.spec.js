import { expect, test } from "../../../fixtures.js";
import { cleanupInboxConversations, setupInboxConversation } from "../../../data-graphs/inbox.js";
import {
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_IDS,
  TEST_EVENT_NAME,
  TEST_GROUP_IDS,
  TEST_GROUP_NAME,
  TEST_INBOX_CONVERSATION,
  TEST_USER_IDS,
} from "../../../seed.js";
import { navigateToPath, uniqueName, waitForActionResponse } from "../../../utils.js";
import { expectInboxStatusFilter } from "../../inbox-helpers.js";

const INBOX_PATH = "/dashboard/user?tab=inbox";
const LIST_PATH = "/dashboard/user/inbox";
const MOBILE_NOTICE = "This dashboard is not optimized yet for mobile devices";

test.describe("user dashboard inbox view", () => {
  test("member reads a conversation with names and the group context", async ({ member2Page }) => {
    // Load the seeded conversation from the user dashboard
    await navigateToPath(member2Page, `${INBOX_PATH}&conversation_id=${TEST_INBOX_CONVERSATION.id}`);
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

  test("member filters conversations by status without a spam option", async ({ member1Page, owned }) => {
    // Prepare an open and a spam conversation of the member
    const openQuestion = uniqueName("open inbox question");
    const spamQuestion = uniqueName("spam inbox question");
    trackMemberConversation(owned, { body: openQuestion, status: "open" });
    trackMemberConversation(owned, { body: spamQuestion, status: "spam" });

    // Verify the status filter offers no spam option and filters by open status
    await navigateToPath(member1Page, INBOX_PATH);
    await expectInboxStatusFilter(member1Page, {
      listPath: LIST_PATH,
      matchingRowText: openQuestion,
      options: ["All", "Open", "Answered", "Closed"],
      otherRowText: spamQuestion,
      status: { label: "Open", value: "open" },
    });

    // Filter by answered status, which the member has no conversations with
    const list = member1Page.locator("[data-inbox-list]");
    await list.getByLabel("Status filters").click();
    await waitForActionResponse(
      member1Page,
      () =>
        list
          .locator("#inbox-status-filter-options")
          .getByRole("button", { name: "Answered", exact: true })
          .click(),
      { method: "GET", params: { status: "answered" }, pathname: LIST_PATH, status: 200 },
    );

    // Verify the filtered empty state replaces the conversation rows
    await expect(list.getByText("No conversations with this status").filter({ visible: true })).toBeVisible();
    await expect(
      list.getByText("Choose another status to see more conversations.").filter({ visible: true }),
    ).toBeVisible();
    await expect(list.locator("[data-inbox-conversation-row]")).toHaveCount(0);
  });

  test("user without conversations sees the empty inbox", async ({ emptyUserPage }) => {
    // Load the inbox of a user who never contacted a group
    await navigateToPath(emptyUserPage, INBOX_PATH);
    const list = emptyUserPage.locator("[data-inbox-list]");

    // Verify the unfiltered empty state explains how to start a conversation
    await expect(list.getByText("No conversations yet").filter({ visible: true })).toBeVisible();
    await expect(
      list
        .getByText("Use Contact in the Organizers section of an event page to ask a question.")
        .filter({ visible: true }),
    ).toBeVisible();
    await expect(list.getByText("Active filters", { exact: true })).toHaveCount(0);
  });

  test("member opens a conversation and returns to the inbox", async ({ member1Page, owned }) => {
    // Prepare an open conversation of the member
    const question = uniqueName("inbox question");
    const { id } = trackMemberConversation(owned, { body: question, status: "open" });

    // Open the conversation from its inbox row
    await navigateToPath(member1Page, INBOX_PATH);
    const conversationRow = member1Page.locator("[data-inbox-conversation-row]", { hasText: question });
    await expect(conversationRow).toHaveAttribute("title", `View conversation with ${TEST_GROUP_NAME}`);
    await waitForActionResponse(member1Page, () => conversationRow.click(), {
      method: "GET",
      pathname: `${LIST_PATH}/${id}`,
      status: 200,
    });

    // Verify the thread and its dashboard URL
    const userThread = member1Page.locator("#inbox-conversation");
    await expect(userThread.getByRole("heading", { name: TEST_EVENT_NAME })).toBeVisible();
    await expect(userThread.getByRole("list", { name: "Messages" })).toContainText(question);
    await expect(member1Page).toHaveURL(
      (url) => url.searchParams.get("tab") === "inbox" && url.searchParams.get("conversation_id") === id,
    );

    // Return to the inbox and verify the list replaces the thread
    await waitForActionResponse(
      member1Page,
      () => userThread.getByRole("link", { name: "Back to inbox" }).click(),
      {
        method: "GET",
        pathname: "/dashboard/user",
        params: { tab: "inbox" },
        status: 200,
      },
    );
    await expect(member1Page.locator("#inbox-conversation")).toHaveCount(0);
    await expect(member1Page.locator("[data-inbox-conversation-row]", { hasText: question })).toBeVisible();
    await expect(member1Page).toHaveURL(
      (url) => url.searchParams.get("tab") === "inbox" && !url.searchParams.has("conversation_id"),
    );
  });

  test("member sees the spam notice without a message form", async ({ member1Page, owned }) => {
    // Prepare a conversation the group marked as spam
    const question = uniqueName("spam inbox question");
    const { id } = trackMemberConversation(owned, { body: question, status: "spam" });

    // Load the conversation from the user dashboard
    await navigateToPath(member1Page, `${INBOX_PATH}&conversation_id=${id}`);
    const userThread = member1Page.locator("#inbox-conversation");
    await expect(userThread.getByRole("list", { name: "Messages" })).toContainText(question);

    // Verify the spam notice replaces the message form
    await expect(userThread.locator("[data-inbox-spam-notice]")).toContainText(
      "The organizers marked this conversation as spam",
    );
    await expect(userThread.locator("#inbox-message-form")).toHaveCount(0);
    await expect(userThread.getByLabel("New message")).toHaveCount(0);
  });

  test("user inbox stays desktop only on mobile @mobile", async ({ member2Page }) => {
    // Load the user inbox on a mobile viewport
    await navigateToPath(member2Page, INBOX_PATH);

    // Verify the mobile notice replaces the conversation list
    await expect(member2Page.getByText(MOBILE_NOTICE)).toBeVisible();
    await expect(member2Page.locator("[data-inbox-list]")).toBeHidden();
  });
});

// Helpers.

/**
 * Inserts an owned conversation the first member started about the primary event, deleted at
 * teardown.
 * @param {{ track: Function }} owned - Owned data registry of the test.
 * @param {{ body: string, status: "answered"|"closed"|"open"|"spam" }} options - Initial message
 *   body and conversation status.
 * @returns {{ id: string, messageIds: string[] }} Conversation and message identifiers.
 */
const trackMemberConversation = (owned, { body, status }) =>
  owned.track(
    setupInboxConversation({
      eventId: TEST_EVENT_IDS.alpha.one,
      groupId: TEST_GROUP_IDS.community1.alpha,
      messages: [{ body }],
      status,
      userId: TEST_USER_IDS.member1,
    }),
    ({ id }) => cleanupInboxConversations([id]),
  );
