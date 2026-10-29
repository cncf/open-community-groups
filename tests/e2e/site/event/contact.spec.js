import { expect, test } from "../../fixtures.js";
import { cleanupInboxConversations, insertClosedUserConversations } from "../../data-graphs/inbox.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_IDS,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_USER_IDS,
} from "../../seed.js";
import { navigateToEvent } from "../../utils.js";

test.describe("event page contact organizers modal", () => {
  test("organizer contact modal links to the group inbox", async ({ organizerGroupPage }) => {
    // Open the contact modal of an event of the organized group
    const modal = await openContactModal(organizerGroupPage);

    // Verify the organizer note links to the group inbox instead of the form
    await expect(modal.locator("[data-contact-organizer-note]")).toContainText(
      `You're an organizer of the ${TEST_GROUP_NAME} group.`,
    );
    await expect(modal.getByRole("link", { name: "Open group Inbox" })).toHaveAttribute(
      "href",
      "/dashboard/group?tab=inbox",
    );
    await expect(modal.locator("#contact-form")).toHaveCount(0);
  });

  test("group viewer contact modal has no inbox link", async ({ groupViewerPage }) => {
    // Open the contact modal of an event of the viewed group
    const modal = await openContactModal(groupViewerPage);

    // Verify the team note replaces the form without linking to the inbox
    await expect(modal.locator("[data-contact-organizer-note]")).toContainText(
      `You're a team member of the ${TEST_GROUP_NAME} group.`,
    );
    await expect(modal.getByRole("link", { name: "Open group Inbox" })).toHaveCount(0);
    await expect(modal.locator("#contact-form")).toHaveCount(0);
  });

  test("logged-out visitor gets a sign-in prompt", async ({ page }) => {
    // Open the contact modal without a session
    const modal = await openContactModal(page);

    // Verify the modal asks the visitor to sign in and returns to the event page
    await expect(modal.locator("[data-contact-sign-in]")).toBeVisible();
    await expect(modal.getByRole("link", { name: "Sign in" })).toHaveAttribute(
      "href",
      `/log-in?next_url=/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`,
    );

    // Verify Escape closes the modal and focus returns to the opener
    await page.keyboard.press("Escape");
    await expect(modal).toBeHidden();
    await expect(page.getByRole("button", { name: "Contact organizers" })).toBeFocused();
  });

  test("user over the daily conversation limit gets the limit notice", async ({ member1Page }) => {
    let conversationIds = [];

    try {
      // Start today's maximum number of conversations for the first member
      conversationIds = insertClosedUserConversations({
        count: 3,
        groupId: TEST_GROUP_IDS.community1.alpha,
        userId: TEST_USER_IDS.member1,
      });

      // Open the contact modal from the public event page
      const modal = await openContactModal(member1Page);

      // Verify the modal shows the limit notice instead of the contact form
      await expect(modal.locator("[data-contact-limit-reached]")).toBeVisible();
      await expect(modal.getByLabel("Message")).toHaveCount(0);
    } finally {
      // Remove the owned conversations
      cleanupInboxConversations(conversationIds);
    }
  });
});

// Helpers.

/**
 * Opens the contact organizers modal of the primary seeded event.
 * @param {import("@playwright/test").Page} page - Page to open the modal on
 * @returns {Promise<import("@playwright/test").Locator>} Visible contact modal
 */
const openContactModal = async (page) => {
  await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
  await page.getByRole("button", { name: "Contact organizers" }).click();
  const modal = page.getByRole("dialog", { name: "Contact organizers" });
  await expect(modal).toBeVisible();

  return modal;
};
