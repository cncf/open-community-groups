import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_IDS,
  TEST_GROUP_IDS,
  TEST_USER_CREDENTIALS,
  logInWithSeededUser,
  navigateToPath,
  selectGroupContext,
} from "../utils";

const CFS_EVENT_ID = "55555555-5555-5555-5555-555555555519";

test.describe("group dashboard", () => {
  test("group team page shows seeded roles and last-admin protection", async ({
    page,
  }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.organizer1);
    await selectGroupContext(
      page,
      TEST_COMMUNITY_IDS.community1,
      TEST_GROUP_IDS.community1.alpha,
    );
    await navigateToPath(page, "/dashboard/group?tab=team");

    const dashboardContent = page.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Group Team", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add member" }),
    ).toBeEnabled();

    const adminRow = dashboardContent.locator("tr", {
      hasText: "E2E Organizer One",
    });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.locator("select")).toHaveAttribute(
      "title",
      "At least one accepted admin is required.",
    );

    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Events Manager One" }),
    ).toContainText("events-manager");
    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Group Viewer One" }),
    ).toContainText("viewer");
    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Pending Two" }),
    ).toContainText("Invitation sent");
  });

  test("events manager can review CFS submissions with labels and ratings", async ({
    page,
  }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.eventsManager1);
    await selectGroupContext(
      page,
      TEST_COMMUNITY_IDS.community1,
      TEST_GROUP_IDS.community1.alpha,
    );
    await navigateToPath(page, `/dashboard/group/events/${CFS_EVENT_ID}/submissions`);

    await expect(page.getByText("Submissions", { exact: true })).toBeVisible();
    await expect(page.getByLabel("Sort by")).toBeVisible();
    await expect(page.getByRole("option", { name: "Stars (high to low)" })).toBeVisible();
    await expect(page.getByRole("option", { name: "Ratings count (high to low)" })).toBeVisible();

    await expect(page.getByText("Platform", { exact: true })).toBeVisible();
    await expect(page.getByText("Workshop", { exact: true })).toBeVisible();
    await expect(page.getByText("2 ratings", { exact: true })).toBeVisible();
    await expect(page.getByText("1 rating", { exact: true })).toBeVisible();

    const approvedRow = page.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(approvedRow).toContainText("Approved");
    await expect(approvedRow.getByTitle("Review submission")).toBeEnabled();
  });

  test("viewer sees read-only event and submission controls", async ({ page }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.groupViewer1);
    await selectGroupContext(
      page,
      TEST_COMMUNITY_IDS.community1,
      TEST_GROUP_IDS.community1.alpha,
    );
    await navigateToPath(page, "/dashboard/group?tab=events");

    const dashboardContent = page.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add Event" }),
    ).toBeDisabled();

    await navigateToPath(page, `/dashboard/group/events/${CFS_EVENT_ID}/submissions`);

    const reviewButtons = page.getByTitle("Your role cannot manage events.");
    await expect(reviewButtons.first()).toBeDisabled();
  });
});
