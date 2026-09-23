import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUG,
  TEST_SITE_TITLE,
} from "../../seed.js";
import { navigateToCommunityHome, navigateToPath, navigateToSiteHome } from "../../utils.js";

const GROUP_PATH = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`;
const EVENT_PATH = `${GROUP_PATH}/event/${TEST_EVENT_SLUG}`;

test.describe("navigation", () => {
  test("guest reaches the explore and stats pages from the site home", async ({ page }) => {
    // Load the public home page and verify it renders its site title.
    await navigateToSiteHome(page);
    await expect(page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE })).toBeVisible();

    // Follow the main navigation to the explore page.
    const navigation = page.getByRole("navigation", { name: "Main navigation" });
    await navigation.getByRole("link", { name: "Explore" }).click();
    await expect(page).toHaveURL(/\/explore/);
    await expect(page.locator("main#main-content")).toBeVisible();

    // Follow the main navigation to the stats page.
    await navigation.getByRole("link", { name: "Stats" }).click();
    await expect(page).toHaveURL(/\/stats$/);
    await expect(page.locator("main#main-content")).toBeVisible();
  });

  test("guest walks from a community page to an event and back to its group", async ({ page }) => {
    // Load the seeded community and verify its title.
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    await expect(page.getByRole("heading", { level: 1, name: TEST_COMMUNITY_TITLE })).toBeVisible();

    // Open the seeded event through its card and verify the event page.
    await page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.alpha[0] }).first().click();
    await expect(page).toHaveURL(new RegExp(`${EVENT_PATH}$`));
    await expect(page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] })).toBeVisible();

    // Follow the breadcrumb back to the group page.
    const breadcrumb = page.getByRole("navigation", { name: "Breadcrumb" });
    await breadcrumb.getByRole("link", { name: TEST_GROUP_NAMES.alpha }).click();
    await expect(page).toHaveURL(new RegExp(`${GROUP_PATH}$`));
    await expect(page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha })).toBeVisible();
  });

  test("guest is sent to log in when opening a dashboard", async ({ page }) => {
    // Request a protected dashboard page as a guest.
    await navigateToPath(page, "/dashboard/user");

    // Verify the login page is shown with the return destination preserved.
    await expect(page).toHaveURL(/\/log-in\?next_url=/);
    await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  });

  test("member opens the user dashboard from the header menu", async ({ member1Page }) => {
    // Load a public page with an authenticated session.
    await navigateToSiteHome(member1Page);

    // Open the user menu and follow the dashboard destination.
    const userMenuButton = member1Page.locator('#user-dropdown-button[data-logged-in="true"]');
    await expect(userMenuButton).toBeVisible();
    await userMenuButton.click();
    await member1Page.locator("#user-dropdown").getByRole("menuitem", { name: "User dashboard" }).click();

    // Verify the user dashboard renders its default Profile tab.
    await expect(member1Page).toHaveURL(/\/dashboard\/user/);
    const dashboardContent = member1Page.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Personal Details", { exact: true })).toBeVisible();
    await expect(dashboardContent.locator("#user-details-form")).toBeVisible();
  });
});
