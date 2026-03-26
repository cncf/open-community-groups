import { expect, test } from "../../fixtures";

import { navigateToPath } from "../../utils";

const DASHBOARD_ROUTES = [
  "/dashboard/community",
  "/dashboard/group",
  "/dashboard/user",
] as const;

const MOBILE_WARNING = "This dashboard is not optimized yet for mobile devices";

test.describe("dashboard home", () => {
  for (const route of DASHBOARD_ROUTES) {
    test(`requires login for ${route}`, async ({ page }) => {
      await navigateToPath(page, route);

      await expect(page).toHaveURL(/\/log-in/);
      await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
    });
  }

  test.describe("mobile experience @mobile", () => {
    test("community dashboard shows the mobile unsupported state", async ({
      adminCommunityPage,
    }) => {
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

      await expect(
        adminCommunityPage.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(adminCommunityPage.locator("#dashboard-main-content")).toBeHidden();
    });

    test("group dashboard shows the mobile unsupported state", async ({
      organizerGroupPage,
    }) => {
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      await expect(
        organizerGroupPage.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(organizerGroupPage.locator("#dashboard-main-content")).toBeHidden();
    });

    test("user dashboard shows the mobile unsupported state", async ({
      member1Page,
    }) => {
      await navigateToPath(member1Page, "/dashboard/user?tab=events");

      await expect(
        member1Page.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(member1Page.locator("#dashboard-main-content")).toBeHidden();
    });
  });
});
