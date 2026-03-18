import { expect, test } from "../fixtures";

import {
  navigateToPath,
} from "../utils";

const BETA_GROUP_ID = "44444444-4444-4444-4444-444444444442";

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
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=team");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
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

  test("admin can deactivate and reactivate a group from the list", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    let betaGroupRow = dashboardContent.locator("tr", {
      hasText: "E2E Test Group Beta",
    });
    await expect(betaGroupRow).toBeVisible();
    await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);

    const openActionsMenu = async () => {
      await dashboardContent
        .locator(`.btn-group-actions[data-group-id="${BETA_GROUP_ID}"]`)
        .click();
    };

    await openActionsMenu();

    const deactivateButton = dashboardContent.locator(`#deactivate-group-${BETA_GROUP_ID}`);
    await expect(deactivateButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/community/groups/${BETA_GROUP_ID}/deactivate`) &&
          response.ok(),
      ),
      deactivateButton.click(),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    betaGroupRow = dashboardContent.locator("tr", {
      hasText: "E2E Test Group Beta",
    });
    await expect(betaGroupRow).toContainText("Inactive");
    await expect(
      betaGroupRow.getByRole("button", { name: "View group page: E2E Test Group Beta" }),
    ).toBeDisabled();

    await openActionsMenu();

    const activateButton = dashboardContent.locator(`#activate-group-${BETA_GROUP_ID}`);
    await expect(activateButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/community/groups/${BETA_GROUP_ID}/activate`) &&
          response.ok(),
      ),
      activateButton.click(),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    betaGroupRow = dashboardContent.locator("tr", {
      hasText: "E2E Test Group Beta",
    });
    await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);
    await expect(
      betaGroupRow.getByRole("link", { name: "View group page: E2E Test Group Beta" }),
    ).toBeVisible();
  });

  for (const taxonomyCase of taxonomyCases) {
    test(`admin can distinguish used and unused entries on ${taxonomyCase.heading}`, async ({
      adminCommunityPage,
    }) => {
      await navigateToPath(adminCommunityPage, taxonomyCase.path);

      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
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

    test(`viewer sees read-only controls on ${taxonomyCase.heading}`, async ({
      communityViewerPage,
    }) => {
      await navigateToPath(communityViewerPage, taxonomyCase.path);

      const dashboardContent = communityViewerPage.locator("#dashboard-content");
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
