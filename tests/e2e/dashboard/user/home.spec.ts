import { expect, test } from "../../fixtures";

import { navigateToPath } from "../../utils";

test.describe("user dashboard home", () => {
  test("shows the dashboard shell and primary navigation", async ({ member1Page }) => {
    await navigateToPath(member1Page, "/dashboard/user?tab=events");

    await expect(
      member1Page.getByText("User Dashboard", { exact: true }).last(),
    ).toBeVisible();
    await expect(member1Page.locator("#dashboard-content")).toBeVisible();

    await expect(
      member1Page.locator('a[hx-get="/dashboard/user?tab=events"]'),
    ).toContainText("My Events");
    await expect(
      member1Page.locator('a[hx-get="/dashboard/user?tab=account"]'),
    ).toContainText("Profile");
    await expect(
      member1Page.locator('a[hx-get="/dashboard/user?tab=invitations"]'),
    ).toContainText("Invitations");
    await expect(
      member1Page.locator('a[hx-get="/dashboard/user?tab=session-proposals"]'),
    ).toContainText("Session proposals");
    await expect(
      member1Page.locator('a[hx-get="/dashboard/user?tab=submissions"]'),
    ).toContainText("Submissions");
  });
});
