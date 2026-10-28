import { expect, test } from "../../../fixtures.js";

import { navigateToPath, waitForActionResponse } from "../../../utils.js";

// Desktop user dashboard tabs (Check-In is mobile only), each with a locator
// in the tab content that proves the tab finished rendering.
const USER_TABS = [
  { ready: (content) => content.getByText("My Groups", { exact: true }), tab: "groups" },
  { ready: (content) => content.getByText("My Events", { exact: true }), tab: "events" },
  { ready: (content) => content.getByText("Surveys", { exact: true }), tab: "surveys" },
  { ready: (content) => content.getByText("Purchases & documents", { exact: true }), tab: "purchases" },
  { ready: (content) => content.locator("#user-details-form"), tab: "account" },
  { ready: (content) => content.locator("#notification-preferences-form"), tab: "notifications" },
  { ready: (content) => content.getByRole("heading", { name: "Badges", exact: true }), tab: "badges" },
  { ready: (content) => content.getByText("Event Invitations", { exact: true }), tab: "invitations" },
  { ready: (content) => content.getByText("Inbox", { exact: true }), tab: "inbox" },
  {
    ready: (content) => content.getByText("Session proposals", { exact: true }),
    tab: "session-proposals",
  },
  { ready: (content) => content.getByText("Submissions", { exact: true }), tab: "submissions" },
  { ready: (content) => content.getByText("Logs", { exact: true }), tab: "logs" },
];

test.describe("user dashboard navigation", () => {
  test("shows the dashboard shell and primary navigation", async ({ member1Page }) => {
    // Load the user events tab before checking the dashboard shell.
    await navigateToPath(member1Page, "/dashboard/user?tab=events");

    // Verify shows the dashboard shell and primary navigation.
    await expect(member1Page.getByText("User Dashboard", { exact: true }).last()).toBeVisible();
    await expect(member1Page.locator("#dashboard-content")).toBeVisible();

    // Assert the expected text is rendered.
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=events"]')).toContainText("My Events");
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=groups"]')).toContainText("My Groups");
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=account"]')).toContainText("Profile");
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=notifications"]')).toContainText(
      "Notifications",
    );
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=invitations"]')).toContainText(
      "Invitations",
    );
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=purchases"]')).toContainText("Purchases");
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=session-proposals"]')).toContainText(
      "Session proposals",
    );
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=submissions"]')).toContainText(
      "Submissions",
    );
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=badges"]')).toContainText("Badges");
    await expect(member1Page.locator('a[hx-get="/dashboard/user?tab=logs"]')).toContainText("Logs");
  });

  test("menu links open each tab and mark only it as current", async ({ member1Page }) => {
    // Load the default tab before walking the menu.
    await navigateToPath(member1Page, "/dashboard/user");
    const content = member1Page.locator("#dashboard-content");
    const menu = member1Page.locator("#dashboard-menu");

    for (const { ready, tab } of USER_TABS) {
      // Open the tab from its menu link (Purchases is matched by href, its label is compact).
      const href = `/dashboard/user?tab=${tab}`;
      const link = menu.locator(`a[href="${href}"]`);
      await waitForActionResponse(member1Page, () => link.click(), {
        method: "GET",
        params: { tab },
        pathname: "/dashboard/user",
        status: 200,
      });

      // Verify the URL, the rendered tab content and the single current menu link.
      await expect(member1Page, tab).toHaveURL(new RegExp(`\\?tab=${tab}$`));
      await expect(ready(content), tab).toBeVisible();
      await expect(link, tab).toHaveAttribute("aria-current", "page");
      await expect(menu.locator('[aria-current="page"]'), tab).toHaveCount(1);
    }
  });
});
