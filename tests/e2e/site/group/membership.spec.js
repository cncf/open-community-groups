import { expect, test } from "../../fixtures.js";

import {
  TEST_ALLIANCE_NAME,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  navigateToGroup,
} from "../../utils.js";

const groupId = TEST_GROUP_IDS.alliance1.alpha;

// Return the public membership container for the current group page.
const getMembershipContainer = (page) => page.locator("#membership-container");

// Return the join button inside the membership container.
const getJoinButton = (page) =>
  getMembershipContainer(page).locator("#join-btn");

// Return the leave button inside the membership container.
const getLeaveButton = (page) =>
  getMembershipContainer(page).locator("#leave-btn");

// Wait until the membership widget resolves to a join or leave state.
const waitForMembershipState = async (page) => {
  await Promise.race([
    getJoinButton(page).waitFor({ state: "visible" }),
    getLeaveButton(page).waitFor({ state: "visible" }),
  ]);
};

// Leave the group when the current user is already a member.
const leaveGroup = async (page) => {
  const leaveButton = getLeaveButton(page);
  await expect(leaveButton).toBeVisible();

  // Request membership removal before confirming the dialog.
  await leaveButton.click();
  const confirmButton = page.getByRole("button", { name: "Yes" });
  await expect(confirmButton).toBeVisible();

  // Confirm the leave action and wait for membership to be removed.
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "DELETE" &&
        response.url().includes(`/group/${groupId}/leave`) &&
        response.ok(),
    ),
    confirmButton.click(),
  ]);

  // Verify the join action returns after leaving.
  await expect(getJoinButton(page)).toBeVisible();
};

test.describe("group membership", () => {
  test("member can join and leave a group from the public page", async ({
    member2Page,
  }) => {
    // Load the group page and resolve the current membership state.
    await navigateToGroup(
      member2Page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
    );

    // Verify the group page is ready before joining.
    await expect(
      member2Page.getByRole("heading", {
        level: 1,
        name: TEST_GROUP_NAMES.alpha,
      }),
    ).toBeVisible();

    // Resolve existing membership before starting the join flow.
    await waitForMembershipState(member2Page);

    // Leave any existing attendance before continuing.
    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveGroup(member2Page);
    }

    // Target the public join action.
    const joinButton = getJoinButton(member2Page);
    await expect(joinButton).toBeVisible();

    // Join the group and wait for the membership record to be created.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/group/${groupId}/join`) &&
          response.ok(),
      ),
      joinButton.click(),
    ]);

    // Verify the member can now leave the group.
    await expect(getLeaveButton(member2Page)).toBeVisible();

    // Restore the reusable membership state.
    await leaveGroup(member2Page);
  });
});
