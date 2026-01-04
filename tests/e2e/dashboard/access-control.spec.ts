import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_HOST,
  navigateToPath,
  setHostHeader,
} from "../utils";

const dashboardRoutes = ["/dashboard/community", "/dashboard/group", "/dashboard/user"];

test.describe("dashboard access control", () => {
  test.beforeEach(async ({ page }) => {
    await setHostHeader(page, TEST_COMMUNITY_HOST);
  });

  for (const route of dashboardRoutes) {
    test(`requires login for ${route}`, async ({ page }) => {
      await navigateToPath(page, route);

      await expect(page).toHaveURL(/\/log-in/);
      await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
    });
  }
});
