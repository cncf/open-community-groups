import { randomUUID } from "node:crypto";

import { expect, test } from "../../../fixtures.js";

import { TEST_EVENT_NAME, TEST_INBOX_CONVERSATION } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// The seeded conversation of the second member is only read by other tests; its times are matched
// with regexes since they follow the seed day.
test.describe("user dashboard inbox ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member2Page }) => {
    await expectInboxViews({ emptyUserPage, member2Page });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ emptyUserPage, member2Page }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member2Page);
    await expectInboxViews({ emptyUserPage, member2Page });
  });
});

/** Checks the layout of the inbox tab views and captures them. */
const expectInboxViews = async ({ emptyUserPage, member2Page }) => {
  const inbox = emptyUserPage.getByRole("region", { name: "Inbox" });

  await test.step("empty state", async () => {
    // Load the inbox of a user without conversations and check the layout.
    await openUserDashboardView(emptyUserPage, "tab=inbox", { regions: [inbox] });

    // Capture the title, the column headers and the empty state.
    await expectAriaSnapshot(emptyUserPage, inbox, "inbox-empty");
  });

  await test.step("status filter menu", async () => {
    // Open the status filter menu and check that it stays inside the viewport.
    const filterOptions = emptyUserPage.locator("#inbox-status-filter-options");
    await inbox.getByLabel("Status filters").click();
    await expect(filterOptions).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [filterOptions] });

    // Capture the status options, with All selected.
    await expectAriaSnapshot(emptyUserPage, filterOptions, "inbox-status-filter");
  });

  await test.step("filtered empty state", async () => {
    // Load the inbox filtered by a status and check the layout.
    await openUserDashboardView(emptyUserPage, "tab=inbox&status=answered", { regions: [inbox] });

    // Capture the active filter badges and the filtered empty state.
    await expectAriaSnapshot(emptyUserPage, inbox, "inbox-filtered-empty");
  });

  await test.step("unavailable conversation", async () => {
    // Load a conversation the user does not own and check the layout.
    await openUserDashboardView(emptyUserPage, `tab=inbox&conversation_id=${randomUUID()}`, {
      regions: [inbox],
    });

    // Capture the warning above the list.
    await expectAriaSnapshot(emptyUserPage, inbox, "inbox-not-found");
  });

  await test.step("conversation", async () => {
    // Load the second member's seeded conversation and check the layout.
    const conversation = member2Page.getByRole("region", { name: TEST_EVENT_NAME });
    await openUserDashboardView(member2Page, `tab=inbox&conversation_id=${TEST_INBOX_CONVERSATION.id}`, {
      regions: [conversation],
    });

    // Capture the header, the messages and the reply form; the times are matched with regexes.
    await expectAriaSnapshot(member2Page, conversation, "inbox-conversation");
  });

  await test.step("conversation list", async () => {
    // Load the second member's conversation list and check the layout with a row.
    const list = member2Page.getByRole("table", { name: "Inbox conversations" });
    await openUserDashboardView(member2Page, "tab=inbox", { regions: [list] });
    await expect(list.getByRole("row").filter({ hasText: TEST_INBOX_CONVERSATION.reply })).toBeVisible();
  });
};
