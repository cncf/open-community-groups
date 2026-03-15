import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_IDS,
  TEST_USER_CREDENTIALS,
  logInWithSeededUser,
  navigateToPath,
  selectCommunityContext,
} from "../utils";

const taxonomyCases = [
  {
    path: "/dashboard/community?tab=regions",
    heading: "Regions",
    addButton: "Add Region",
    usedDeleteId: "delete-region-22222222-2222-2222-2222-222222222301",
    unusedDeleteId: "delete-region-22222222-2222-2222-2222-222222222302",
  },
  {
    path: "/dashboard/community?tab=group-categories",
    heading: "Group Categories",
    addButton: "Add Group Category",
    usedDeleteId: "delete-group-category-22222222-2222-2222-2222-222222222221",
    unusedDeleteId: "delete-group-category-22222222-2222-2222-2222-222222222223",
  },
  {
    path: "/dashboard/community?tab=event-categories",
    heading: "Event Categories",
    addButton: "Add Event Category",
    usedDeleteId: "delete-event-category-33333333-3333-3333-3333-333333333331",
    unusedDeleteId: "delete-event-category-33333333-3333-3333-3333-333333333333",
  },
] as const;

test.describe("community dashboard", () => {
  test("community team page shows seeded roles and final-admin protection", async ({
    page,
  }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin1);
    await selectCommunityContext(page, TEST_COMMUNITY_IDS.community1);
    await navigateToPath(page, "/dashboard/community?tab=team");

    const dashboardContent = page.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Community Team", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add member" }),
    ).toBeEnabled();

    const adminRow = dashboardContent.locator("tr", { hasText: "E2E Admin One" });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.locator("select")).toHaveAttribute(
      "title",
      "At least one accepted admin is required.",
    );

    const groupsManagerRow = dashboardContent.locator("tr", {
      hasText: "E2E Groups Manager One",
    });
    await expect(groupsManagerRow.locator('select[name="role"]')).toHaveValue(
      "groups-manager",
    );

    const viewerRow = dashboardContent.locator("tr", {
      hasText: "E2E Community Viewer One",
    });
    await expect(viewerRow.locator('select[name="role"]')).toHaveValue("viewer");
    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Pending One" }),
    ).toContainText("Invitation sent");
  });

  for (const taxonomyCase of taxonomyCases) {
    test(`admin can distinguish used and unused entries on ${taxonomyCase.heading}`, async ({
      page,
    }) => {
      await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin1);
      await selectCommunityContext(page, TEST_COMMUNITY_IDS.community1);
      await navigateToPath(page, taxonomyCase.path);

      const dashboardContent = page.locator("#dashboard-content");
      await expect(
        dashboardContent.getByText(taxonomyCase.heading, { exact: true }),
      ).toBeVisible();
      await expect(
        dashboardContent.getByRole("button", { name: taxonomyCase.addButton }),
      ).toBeEnabled();
      await expect(dashboardContent.locator(`#${taxonomyCase.usedDeleteId}`)).toBeDisabled();
      await expect(
        dashboardContent.locator(`#${taxonomyCase.unusedDeleteId}`),
      ).toBeEnabled();
    });

    test(`viewer sees read-only controls on ${taxonomyCase.heading}`, async ({ page }) => {
      await logInWithSeededUser(page, TEST_USER_CREDENTIALS.communityViewer1);
      await selectCommunityContext(page, TEST_COMMUNITY_IDS.community1);
      await navigateToPath(page, taxonomyCase.path);

      const dashboardContent = page.locator("#dashboard-content");
      await expect(
        dashboardContent.getByText(taxonomyCase.heading, { exact: true }),
      ).toBeVisible();
      await expect(
        dashboardContent.getByRole("button", { name: taxonomyCase.addButton }),
      ).toBeDisabled();
      await expect(
        dashboardContent.locator(`#${taxonomyCase.unusedDeleteId}`),
      ).toBeDisabled();
    });
  }
});
