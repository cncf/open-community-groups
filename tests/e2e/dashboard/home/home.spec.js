import { expect, test } from "../../fixtures.js";

import { navigateToPath } from "../../utils.js";

const DASHBOARD_ROUTES = [
  "/dashboard/alliance",
  "/dashboard/group",
  "/dashboard/user",
];

const MOBILE_WARNING = "This dashboard is not optimized yet for mobile devices";

test.describe("dashboard home", () => {
  for (const route of DASHBOARD_ROUTES) {
    test(`requires login for ${route}`, async ({ page }) => {
      // Open the protected dashboard route as a guest.
      await navigateToPath(page, route);

      // Verify requires login for route.
      await expect(page).toHaveURL(/\/log-in/);
      await expect(
        page.getByRole("heading", { name: "Welcome back." }),
      ).toBeVisible();
    });
  }

  test.describe("mobile experience @mobile", () => {
    test("alliance dashboard shows the mobile unsupported state", async ({
      adminAlliancePage,
    }) => {
      // Load the alliance dashboard on a mobile viewport.
      await navigateToPath(adminAlliancePage, "/dashboard/alliance?tab=groups");

      // Verify alliance dashboard shows the mobile unsupported state.
      await expect(
        adminAlliancePage.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(
        adminAlliancePage.locator("#dashboard-main-content"),
      ).toBeHidden();
    });

    test("group dashboard shows the mobile unsupported state", async ({
      organizerGroupPage,
    }) => {
      // Load the group dashboard on a mobile viewport.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Verify group dashboard shows the mobile unsupported state.
      await expect(
        organizerGroupPage.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(
        organizerGroupPage.locator("#dashboard-main-content"),
      ).toBeHidden();
    });

    test("user dashboard shows the mobile unsupported state", async ({
      member1Page,
    }) => {
      // Load the user dashboard on a mobile viewport.
      await navigateToPath(member1Page, "/dashboard/user?tab=events");

      // Verify user dashboard shows the mobile unsupported state.
      await expect(
        member1Page.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(member1Page.locator("#dashboard-main-content")).toBeHidden();
    });
  });
});
