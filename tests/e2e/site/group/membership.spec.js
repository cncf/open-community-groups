import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  navigateToGroup,
  waitForActionResponse,
} from "../../utils.js";

const groupId = TEST_GROUP_IDS.community1.alpha;

// Return the public membership container for the current group page.
const getMembershipContainer = (page) => page.locator("#membership-container");

// Return the join button inside the membership container.
const getJoinButton = (page) =>
  getMembershipContainer(page).locator("#join-btn");

// Return the sign-in button shown to guests.
const getSignInButton = (page) =>
  getMembershipContainer(page).locator("#signin-btn");

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
  await waitForActionResponse(page, () => confirmButton.click(), {
    method: "DELETE",
    urlIncludes: `/group/${groupId}/leave`,
  });

  // Verify the join action returns after leaving.
  await expect(getJoinButton(page)).toBeVisible();
};

test.describe("group membership", () => {
  test("guest join action preserves the group return URL", async ({ page }) => {
    // Load the public group and wait for the guest membership state.
    await navigateToGroup(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
    );
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

  test("member can join and leave a group from the public page", async ({
    member2Page,
  }) => {
    // Load the group page and resolve the current membership state.
    await navigateToGroup(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
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
    await waitForActionResponse(member2Page, () => joinButton.click(), {
      method: "POST",
      urlIncludes: `/group/${groupId}/join`,
    });

    // Verify the member can now leave the group.
    await expect(getLeaveButton(member2Page)).toBeVisible();

    // Restore the reusable membership state.
    await leaveGroup(member2Page);
  });

  test("failed group join restores the action for retry", async ({
    member2Page,
  }) => {
    // Load the group and restore a non-member state before intercepting join.
    await navigateToGroup(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
    );
    await waitForMembershipState(member2Page);
    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveGroup(member2Page);
    }

    // Return a local server failure for the join request only.
    await member2Page.route(
      `**/${TEST_COMMUNITY_NAME}/group/${groupId}/join`,
      (route) =>
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
      member2Page.getByText(
        "Something went wrong joining this group. Please try again later.",
        {
          exact: true,
        },
      ),
    ).toBeVisible();
    await expect(joinButton).toBeVisible();
    await expect(
      getMembershipContainer(member2Page).locator("#loading-btn"),
    ).toBeHidden();
    await expect(getLeaveButton(member2Page)).toBeHidden();
  });

  test("failed group leave preserves membership and restores the action", async ({
    member2Page,
  }) => {
    // Load the group and ensure the reusable user starts as a member.
    await navigateToGroup(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
    );
    await waitForMembershipState(member2Page);
    if (await getJoinButton(member2Page).isVisible()) {
      await waitForActionResponse(member2Page, () => getJoinButton(member2Page).click(), {
        method: "POST",
        urlIncludes: `/group/${groupId}/join`,
      });
    }

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
      const confirmButton = member2Page.getByRole("button", { name: "Yes" });
      await expect(confirmButton).toBeVisible();
      await waitForActionResponse(member2Page, () => confirmButton.click(), {
        method: "DELETE",
        status: 500,
        urlIncludes: `/group/${groupId}/leave`,
      });

      // Verify membership remains durable and the leave action can be retried.
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "Something went wrong leaving this group. Please try again later.",
      );
      await expect(getLeaveButton(member2Page)).toBeVisible();
      await expect(getLeaveButton(member2Page)).toBeEnabled();
      await expect(
        getMembershipContainer(member2Page).locator("#loading-btn"),
      ).toBeHidden();
      await expect(getJoinButton(member2Page)).toBeHidden();
    } finally {
      await member2Page.unroute(leavePath);
      if (!member2Page.isClosed()) {
        const errorConfirmation = member2Page.getByRole("button", {
          name: "OK",
        });
        if (await errorConfirmation.isVisible()) {
          await errorConfirmation.click();
        }
        if (await getLeaveButton(member2Page).isVisible()) {
          await leaveGroup(member2Page);
        }
      }
    }
  });
});
