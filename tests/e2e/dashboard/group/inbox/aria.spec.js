import { randomUUID } from "node:crypto";

import { expect, test } from "../../../fixtures.js";

import { cleanupInboxConversations, setupInboxConversation } from "../../../data-graphs/inbox.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { ARIA_EVENT, openGroupDashboardView, setupAriaEvent, setupAriaGroup } from "../aria-helpers.js";

test.describe("group dashboard inbox ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectInboxViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectInboxViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the inbox tab views and captures them. */
const expectInboxViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });
  const inbox = page.getByRole("region", { name: "Inbox" });

  await test.step("empty state", async () => {
    // Load the inbox of a temporary group without conversations and check the layout.
    await openGroupDashboardView(page, "tab=inbox", { regions: [inbox] });

    // Capture the title, the column headers and the empty state.
    await expectAriaSnapshot(page, inbox, "inbox-empty");
  });

  await test.step("status filter menu", async () => {
    // Open the status filter options and check the layout.
    const filterOptions = page.locator("#inbox-status-filter-options");
    await inbox.getByLabel("Status filters").click();
    await expect(filterOptions).toBeVisible();
    await expectPageLayout(page, { regions: [filterOptions] });

    // Capture the status options.
    await expectAriaSnapshot(page, filterOptions, "inbox-status-filter");
  });

  await test.step("unavailable conversation", async () => {
    // Load a conversation that does not exist and check the layout.
    await openGroupDashboardView(page, `tab=inbox&conversation_id=${randomUUID()}`, { regions: [inbox] });

    // Capture the not found state with the way back to the inbox.
    await expectAriaSnapshot(page, inbox, "inbox-not-found");
  });

  // Give the group an open conversation about an owned event.
  const event = setupAriaEvent({ groupId, owned });
  const conversation = owned.track(
    setupInboxConversation({
      eventId: event.eventId,
      groupId,
      messages: [{ body: "Is the venue step-free?", kind: "initial" }],
      userId: TEST_USER_IDS.member3,
    }),
    ({ id }) => cleanupInboxConversations([id]),
  );

  await test.step("conversation list", async () => {
    // Load the inbox with the open conversation and check the layout.
    const list = page.getByRole("table", { name: "Inbox conversations" });
    await openGroupDashboardView(page, "tab=inbox", { regions: [list] });
    await expect(list.getByRole("row").filter({ hasText: ARIA_EVENT.name })).toBeVisible();

    // Capture the column headers and the conversation row; the message time is the test day.
    await expectAriaSnapshot(page, list, "inbox-conversations");
  });

  await test.step("conversation", async () => {
    // Load the conversation and check the layout.
    const thread = page.locator("#inbox-conversation");
    await openGroupDashboardView(page, `tab=inbox&conversation_id=${conversation.id}`, { regions: [thread] });

    // Capture the thread header and actions, the message and the reply form.
    await expectAriaSnapshot(page, thread, "inbox-conversation");
  });
};
