import { expect, test } from "@playwright/test";

import { navigateToPath } from "../utils";

const DASHBOARD_ROUTES = [
  "/dashboard/community",
  "/dashboard/group",
  "/dashboard/user",
] as const;

test.describe("dashboard access control", () => {
  for (const route of DASHBOARD_ROUTES) {
    test(`requires login for ${route}`, async ({ page }) => {
      await navigateToPath(page, route);

      await expect(page).toHaveURL(/\/log-in/);
      await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
    });
  }
});
