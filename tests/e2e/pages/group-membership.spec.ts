import type { Page } from "@playwright/test";

import { expect, test } from "../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  navigateToGroup,
} from "../utils";

const groupId = TEST_GROUP_IDS.community1.alpha;

/**
 * Returns the public membership container for the current group page.
 */
const getMembershipContainer = (page: Page) => page.locator("#membership-container");

/**
 * Returns the join button inside the membership container.
 */
const getJoinButton = (page: Page) => getMembershipContainer(page).locator("#join-btn");

/**
 * Returns the leave button inside the membership container.
 */
const getLeaveButton = (page: Page) => getMembershipContainer(page).locator("#leave-btn");

/**
 * Waits until the membership widget resolves to a join or leave state.
 */
const waitForMembershipState = async (page: Page) => {
  await Promise.race([
    getJoinButton(page).waitFor({ state: "visible" }),
    getLeaveButton(page).waitFor({ state: "visible" }),
  ]);
};

/**
 * Leaves the group when the current user is already a member.
 */
const leaveGroup = async (page: Page) => {
  const leaveButton = getLeaveButton(page);
  await expect(leaveButton).toBeVisible();

  await leaveButton.click();
  const confirmButton = page.getByRole("button", { name: "Yes" });
  await expect(confirmButton).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "DELETE" &&
        response.url().includes(`/group/${groupId}/leave`) &&
        response.ok(),
    ),
    confirmButton.click(),
  ]);

  await expect(getJoinButton(page)).toBeVisible();
};

test.describe("group membership", () => {
  test("member can join and leave a group from the public page", async ({
    member2Page,
  }) => {
    await navigateToGroup(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
    );

    await expect(
      member2Page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha }),
    ).toBeVisible();

    await waitForMembershipState(member2Page);

    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveGroup(member2Page);
    }

    const joinButton = getJoinButton(member2Page);
    await expect(joinButton).toBeVisible();

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/group/${groupId}/join`) &&
          response.ok(),
      ),
      joinButton.click(),
    ]);

    await expect(getLeaveButton(member2Page)).toBeVisible();

    await leaveGroup(member2Page);
  });
});
