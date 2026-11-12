import { expect, test, testAtBothWidths } from "../../fixtures.js";
import { cleanupGroupMember } from "../../data-graphs/groups.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
} from "../../seed.js";
import {
  confirmAlert,
  dismissAlert,
  expectDarkTheme,
  expectFocusIndicator,
  navigateToGroup,
  resolveCssColor,
  useTheme,
  waitForActionResponse,
} from "../../utils.js";

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

  test("guest join prompt opens without flashing the page", async ({ page }) => {
    // Load the public group and wait for the guest membership state.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const signInButton = getSignInButton(page);
    await expect(signInButton).toBeVisible();

    // Record the background of the alert's page-sized container as soon as it is inserted.
    await page.evaluate(() => {
      new MutationObserver((_, observer) => {
        const container = document.querySelector(".swal2-container");
        if (container) {
          window.ocgAlertContainerBackground = getComputedStyle(container).backgroundColor;
          observer.disconnect();
        }
      }).observe(document.body, { childList: true });
    });
    await signInButton.click();
    await expect(page.locator(".swal2-popup")).toBeVisible();

    // Verify the container starts transparent instead of the opaque popover default.
    expect(await page.evaluate(() => window.ocgAlertContainerBackground)).toBe("rgba(0, 0, 0, 0)");
  });

  test("guests send no membership check and keep the header logo", async ({ page }) => {
    // Record membership checks before the group loads.
    const membershipChecks = [];
    page.on("request", (request) => {
      if (new URL(request.url()).pathname.endsWith("/membership")) {
        membershipChecks.push(request.url());
      }
    });
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    // Verify the guest action shows without asking the server.
    await expect(getSignInButton(page)).toBeVisible();
    expect(membershipChecks).toEqual([]);

    // Verify the header keeps its logo slot, which a log-in redirect used to take away.
    await expect(page.locator("#header #site-logo")).toBeAttached();
  });

  testAtBothWidths(
    "guest join prompt paints the raised token with dark text in dark",
    async ({ isMobile, page }) => {
      // Load the public group in the dark theme.
      await useTheme(page, { stored: "dark" });
      await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
      await expectDarkTheme(page);

      // Open the sign-in prompt from the public join action.
      await getSignInButton(page).click();
      const signInPrompt = page.locator(".swal2-popup");
      await expect(signInPrompt).toBeVisible();

      // Verify phones show the bottom prompt with a Log in button, and desktop its inline link.
      if (isMobile) {
        // swal2-bottom is SweetAlert's position API class, not a utility class.
        await expect(page.locator(".swal2-container")).toHaveClass(/swal2-bottom/);
        await expect(signInPrompt.getByRole("button", { name: "Log in", exact: true })).toBeVisible();
      } else {
        await expect(signInPrompt.getByRole("link", { name: "logged in" })).toBeVisible();
      }

      // Verify the prompt paints the dark raised token with the dark stone-700 text.
      const raised = await resolveCssColor(signInPrompt, "var(--color-raised)");
      expect(raised).not.toBe("rgb(255, 255, 255)");
      await expect(signInPrompt).toHaveCSS("background-color", raised);
      await expect(signInPrompt).toHaveCSS(
        "color",
        await resolveCssColor(signInPrompt, "var(--color-stone-700)"),
      );
    },
  );

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

  test("keyboard join and leave keep focus on the membership action @smoke", async ({
    member2Page,
    owned,
  }) => {
    // Remove the membership even if the flow fails before leaving.
    owned.defer(() => cleanupGroupMember({ groupId, userId: TEST_USER_IDS.member2 }));

    // Load the group page as a non-member.
    await navigateToGroup(member2Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const joinButton = getJoinButton(member2Page);
    const leaveButton = getLeaveButton(member2Page);
    const popup = member2Page.locator(".swal2-popup");
    await expect(joinButton).toBeVisible();

    // Join with the keyboard and wait for the re-checked leave action.
    await joinButton.focus();
    await waitForActionResponse(member2Page, () => member2Page.keyboard.press("Enter"), {
      method: "POST",
      urlIncludes: `/group/${groupId}/join`,
    });
    await expect(popup).toContainText("You have successfully joined this group.");
    await expect(leaveButton).toBeVisible();

    // Dismissing the success alert with the keyboard focuses the leave action.
    await expectFocusIndicator(leaveButton, () => member2Page.keyboard.press("Enter"));
    await expect(popup).toBeHidden();

    // Leave with the keyboard, confirming the prompt with the keyboard too.
    await member2Page.keyboard.press("Enter");
    await expect(popup).toContainText("Are you sure you want to leave this group?");
    await waitForActionResponse(member2Page, () => member2Page.keyboard.press("Enter"), {
      method: "DELETE",
      urlIncludes: `/group/${groupId}/leave`,
    });
    await expect(popup).toContainText("You have successfully left this group.");
    await expect(joinButton).toBeVisible();

    // Dismissing the success alert with the keyboard focuses the join action.
    await expectFocusIndicator(joinButton, () => member2Page.keyboard.press("Enter"));
    await expect(popup).toBeHidden();
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

    // Dismissing the error returns focus to the restored join action.
    await dismissAlert(member2Page, {
      message: "Something went wrong joining this group. Please try again later.",
    });
    await expect(joinButton).toBeFocused();
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
