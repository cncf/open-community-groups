import { expect, test } from "../../fixtures.js";
import { cleanupGroupMember } from "../../data-graphs/groups.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
} from "../../seed.js";
import { confirmAlert, navigateToGroup, waitForActionResponse } from "../../utils.js";

const groupId = TEST_GROUP_IDS.community1.alpha;

test.describe("group membership", () => {
  test("guest join action preserves the group return URL", async ({ page }) => {
    // Load the public group and wait for the guest membership state.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const signInButton = getSignInButton(page);
    await expect(signInButton).toBeVisible();

    // Open the sign-in prompt from the public join action.
    await signInButton.click();
    const signInPrompt = page.locator(".swal2-popup");
    const loginLink = signInPrompt.getByRole("link", { name: "logged in" });

    // Verify authentication returns the guest to the same group page.
    await expect(signInPrompt).toBeVisible();
    await expect(loginLink).toHaveAttribute(
      "href",
      `/log-in?next_url=%2F${TEST_COMMUNITY_NAME}%2Fgroup%2F${TEST_GROUP_SLUGS.community1.alpha}`,
    );
  });

  test("member can join and leave a group from the public page @smoke", async ({
    member2Page,
    notifications,
    owned,
  }) => {
    // Remove the membership even if the flow fails before leaving.
    owned.defer(() => cleanupGroupMember({ groupId, userId: TEST_USER_IDS.member2 }));

    // Load the group page and resolve the current membership state.
    await navigateToGroup(member2Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    // Verify the group page is ready before joining.
    await expect(
      member2Page.getByRole("heading", {
        level: 1,
        name: TEST_GROUP_NAMES.alpha,
      }),
    ).toBeVisible();

    // Target the public join action.
    const joinButton = getJoinButton(member2Page);
    await expect(joinButton).toBeVisible();

    // Join the group and verify its welcome notification.
    await waitForActionResponse(member2Page, () => joinButton.click(), {
      method: "POST",
      urlIncludes: `/group/${groupId}/join`,
    });
    notifications.expectNew([{ kind: "group-welcome", userIds: [TEST_USER_IDS.member2] }]);

    // Verify the member can now leave the group.
    await expect(getLeaveButton(member2Page)).toBeVisible();

    // Leave the group through the public action.
    await leaveGroup(member2Page);
  });

  test("failed group join restores the action for retry", async ({ member2Page }) => {
    // Load the group as a non-member before intercepting join.
    await navigateToGroup(member2Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    await expect(getJoinButton(member2Page)).toBeVisible();

    // Return a local server failure for the join request only.
    await member2Page.route(`**/${TEST_COMMUNITY_NAME}/group/${groupId}/join`, (route) =>
      route.fulfill({
        body: "Temporary membership failure",
        contentType: "text/plain",
        status: 500,
      }),
    );

    // Attempt to join and wait for the simulated failure response.
    const joinButton = getJoinButton(member2Page);
    await waitForActionResponse(member2Page, () => joinButton.click(), {
      method: "POST",
      status: 500,
      urlIncludes: `/group/${groupId}/join`,
    });

    // Verify the error is explicit and the join action recovers.
    await expect(
      member2Page.getByText("Something went wrong joining this group. Please try again later.", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(joinButton).toBeVisible();
    await expect(getMembershipContainer(member2Page).locator("#loading-btn")).toBeHidden();
    await expect(getLeaveButton(member2Page)).toBeHidden();
  });

  test("failed group leave preserves membership and restores the action", async ({ member2Page, owned }) => {
    // Remove the membership the test creates.
    owned.defer(() => cleanupGroupMember({ groupId, userId: TEST_USER_IDS.member2 }));

    // Load the group and join it so the leave action is available.
    await navigateToGroup(member2Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    await waitForActionResponse(member2Page, () => getJoinButton(member2Page).click(), {
      method: "POST",
      urlIncludes: `/group/${groupId}/join`,
    });

    // Prepare the failed leave route.
    const leavePath = `**/${TEST_COMMUNITY_NAME}/group/${groupId}/leave`;
    try {
      // Return a local server failure for the confirmed leave request.
      await member2Page.route(leavePath, (route) =>
        route.fulfill({
          body: "Temporary membership failure",
          contentType: "text/plain",
          status: 500,
        }),
      );
      await getLeaveButton(member2Page).click();
      await waitForActionResponse(
        member2Page,
        () => confirmAlert(member2Page, { message: "Are you sure you want to leave this group?" }),
        {
          method: "DELETE",
          status: 500,
          urlIncludes: `/group/${groupId}/leave`,
        },
      );

      // Verify membership remains durable and the leave action can be retried.
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "Something went wrong leaving this group. Please try again later.",
      );
      await expect(getLeaveButton(member2Page)).toBeVisible();
      await expect(getLeaveButton(member2Page)).toBeEnabled();
      await expect(getMembershipContainer(member2Page).locator("#loading-btn")).toBeHidden();
      await expect(getJoinButton(member2Page)).toBeHidden();
    } finally {
      // Restore the real leave endpoint.
      await member2Page.unroute(leavePath);
    }
  });
});

/** Returns the join button inside the membership container. */
const getJoinButton = (page) => getMembershipContainer(page).locator("#join-btn");

/** Returns the leave button inside the membership container. */
const getLeaveButton = (page) => getMembershipContainer(page).locator("#leave-btn");

/** Returns the public membership container for the current group page. */
const getMembershipContainer = (page) => page.locator("#membership-container");

/** Returns the sign-in button shown to guests. */
const getSignInButton = (page) => getMembershipContainer(page).locator("#signin-btn");

/** Leaves the group when the current user is already a member. */
const leaveGroup = async (page) => {
  const leaveButton = getLeaveButton(page);
  await expect(leaveButton).toBeVisible();

  // Request membership removal, confirm it and wait for membership to be removed.
  await leaveButton.click();
  await waitForActionResponse(
    page,
    () => confirmAlert(page, { message: "Are you sure you want to leave this group?" }),
    {
      method: "DELETE",
      urlIncludes: `/group/${groupId}/leave`,
    },
  );

  // Verify the join action returns after leaving.
  await expect(getJoinButton(page)).toBeVisible();
};
