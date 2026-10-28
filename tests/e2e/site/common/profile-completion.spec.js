import { expect, test } from "../../fixtures.js";
import { TEST_COMMUNITY_NAME, TEST_GROUP_IDS, TEST_GROUP_SLUGS, TEST_USER_CREDENTIALS } from "../../seed.js";
import { getAttendButton, getLeaveButton, waitForAttendanceState } from "../event/helpers.js";
import { logInWithSeededUser, navigateToEvent, waitForActionResponse } from "../../utils.js";

// Session storage flag the login form sets so the next signed-in page shows the prompt once.
const LOGIN_PROMPT_STORAGE_KEY = "ocg.loginProfileCompletionPrompt";

const PROFILE_COMPLETION_MESSAGE =
  "Complete your profile so organizers and community members can learn more about you.";

test.describe("profile completion prompts", () => {
  test("login with an incomplete profile prompts once and links to the account tab", async ({ page }) => {
    // Log in through the form; the prompt auto-closes after 5 s, so assert it before anything else.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.empty);
    const prompt = getProfilePrompt(page, "Complete your profile");
    await expect(prompt).toBeVisible();
    await expect(prompt).toContainText(PROFILE_COMPLETION_MESSAGE);

    // Follow the prompt to the account tab of the user dashboard.
    await Promise.all([
      page.waitForURL(
        (url) => url.pathname === "/dashboard/user" && url.searchParams.get("tab") === "account",
      ),
      prompt.getByRole("button", { name: "Complete profile", exact: true }).click(),
    ]);
    await expectNoLoginPrompt(page, "false");

    // Verify reloading the still-incomplete profile does not prompt again.
    await page.reload();
    await expectNoLoginPrompt(page, "false");
  });

  test("login with a complete profile shows no prompt", async ({ page }) => {
    // Log in through the form and verify the consumed login flag shows nothing.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.member1);
    await expectNoLoginPrompt(page, "true");
  });

  test("attending with an incomplete profile offers to complete it", async ({ emptyUserPage, owned }) => {
    // Load an owned free event as the user with an incomplete profile.
    const event = owned.event({ groupId: TEST_GROUP_IDS.community1.alpha });
    await navigateToEvent(emptyUserPage, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event.slug);
    await waitForAttendanceState(emptyUserPage);

    // Attend and verify the success feedback carries the profile-completion CTA.
    await waitForActionResponse(emptyUserPage, () => getAttendButton(emptyUserPage).click(), {
      method: "POST",
      urlIncludes: `/event/${event.eventId}/attend`,
    });
    const prompt = getProfilePrompt(emptyUserPage, "You have successfully registered for this event.");
    await expect(prompt).toBeVisible();
    await expect(prompt).toContainText(PROFILE_COMPLETION_MESSAGE);
    await expect(prompt.getByRole("button", { name: "Complete profile", exact: true })).toBeVisible();

    // Dismiss the CTA and verify the attendance is kept.
    await prompt.getByRole("button", { name: "Maybe later", exact: true }).click();
    await expect(prompt).toBeHidden();
    await expect(getLeaveButton(emptyUserPage)).toBeVisible();
  });
});

/**
 * Verifies the signed-in page consumed the login flag without showing the prompt.
 * @param {import("@playwright/test").Page} page - Signed-in page.
 * @param {"false"|"true"} profileComplete - Expected header profile-completion state.
 */
const expectNoLoginPrompt = async (page, profileComplete) => {
  await page.waitForLoadState("load");
  await expect(page.locator('#user-dropdown-button[data-logged-in="true"]')).toHaveAttribute(
    "data-profile-complete",
    profileComplete,
  );
  expect(await page.evaluate((key) => sessionStorage.getItem(key), LOGIN_PROMPT_STORAGE_KEY)).toBeNull();
  await expect(page.locator(".swal2-popup")).toHaveCount(0);
};

/** Selects the profile-completion alert by its title. */
const getProfilePrompt = (page, title) =>
  page.locator(".swal2-popup").filter({ has: page.getByRole("heading", { name: title, exact: true }) });
