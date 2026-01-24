import { expect, test } from "@playwright/test";

import { navigateToPath } from "../utils";

const dashboardRoutes = [
  "/dashboard/community",
  "/dashboard/group",
  "/dashboard/user",
];

/**
 * Dashboard access control checks for unauthenticated traffic.
 */
test.describe("dashboard access control", () => {
  for (const route of dashboardRoutes) {
    /**
     * Ensures protected dashboard routes redirect anonymous users to log in.
     */
    test(`requires login for ${route}`, async ({ page }) => {
      await navigateToPath(page, route);

      await expect(page).toHaveURL(/\/log-in/);
      await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
    });
  }
});
