import { expect, test } from "../../../fixtures.js";

import {
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";

import {
  taxonomyCases,
  waitForCommunityDashboardMutation,
} from "../helpers.js";

test.describe("community dashboard group categories view", () => {
  test("empty state guides the first group category", async ({
    adminEmptyCommunityPage,
  }) => {
    // Load group categories for the dedicated community without taxonomy records.
    await navigateToPath(
      adminEmptyCommunityPage,
      "/dashboard/community?tab=group-categories",
    );
    const dashboardContent = adminEmptyCommunityPage.locator(
      "#dashboard-content",
    );

    // Verify first-use guidance and the creation action remain available.
    await expect(dashboardContent).toContainText(
      "No group categories found for this community yet.",
    );
    await expect(
      dashboardContent.getByRole("button", { name: "Add Group Category" }),
    ).toBeVisible();
  });

  test("group categories table exposes its responsive columns", async ({ adminCommunityPage }) => {
    // Load the group categories dashboard before checking table structure.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=group-categories");

    // Find the group categories table.
    const categoriesTable = adminCommunityPage.locator("#dashboard-content").getByRole("table");

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableHeaders(categoriesTable, ["Name", "Groups", "Actions"]);
    await expectTableColumnsAtViewport(
      adminCommunityPage,
      categoriesTable,
      1024,
      ["Name", "Actions"],
      ["Groups"],
    );
    await expectTableColumnsAtViewport(
      adminCommunityPage,
      categoriesTable,
      1280,
      ["Name", "Groups", "Actions"],
      [],
    );
  });

  test("admin can add, update, and delete a group category", async ({ adminCommunityPage }) => {
    // Create a unique category name for the temporary category flow.
    const categoryName = `E2E Group Category ${Date.now()}`;
    const updatedCategoryName = `${categoryName} Updated`;

    // Load the group categories dashboard.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=group-categories");

    // Open the add form and submit the temporary category.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Group Categories", { exact: true })).toBeVisible();

    // Click Add Group Category.
    await dashboardContent.getByRole("button", { name: "Add Group Category" }).click();
    await expect(dashboardContent.getByText("Group Category Details", { exact: true })).toBeVisible();

    // Fill Name.
    await adminCommunityPage.getByLabel("Name").fill(categoryName);

    // Click Add Group Category.
    await waitForCommunityDashboardMutation(
      adminCommunityPage,
      "/dashboard/community/group-categories",
      () => adminCommunityPage.getByRole("button", { name: "Add Group Category" }).click(),
      { method: "POST", urlIncludes: "/dashboard/community/group-categories/add", status: 201 },
    );

    // Verify the temporary category appears before deleting it.
    let categoryRow = dashboardContent.locator("tr", {
      hasText: categoryName,
    });
    await expect(categoryRow).toBeVisible();

    // Edit the temporary category and wait for the update form to load.
    await waitForActionResponse(
      adminCommunityPage,
      () => categoryRow.getByRole("button", { name: `Edit group category: ${categoryName}` }).click(),
      { method: "GET", urlIncludes: "/dashboard/community/group-categories/", urlEndsWith: "/update" },
    );
    await adminCommunityPage.getByLabel("Name").fill(updatedCategoryName);
    await waitForCommunityDashboardMutation(
      adminCommunityPage,
      "/dashboard/community/group-categories",
      () => adminCommunityPage.getByRole("button", { name: "Update Group Category" }).click(),
      { method: "PUT", urlIncludes: "/dashboard/community/group-categories/", urlEndsWith: "/update" },
    );
    // Find the renamed category and verify it is rendered.
    categoryRow = dashboardContent.locator("tr", {
      hasText: updatedCategoryName,
    });
    await expect(categoryRow).toBeVisible();

    // Delete the group category from its row action.
    await categoryRow
      .getByRole("button", {
        name: `Delete group category: ${updatedCategoryName}`,
      })
      .click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this group category?",
    );

    // Confirm deletion and verify the category is removed.
    await waitForCommunityDashboardMutation(
      adminCommunityPage,
      "/dashboard/community/group-categories",
      () => adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
      { method: "DELETE", urlIncludes: "/dashboard/community/group-categories/" },
    );

    // Assert how many matching elements are shown.
    await expect(dashboardContent.locator("tr", { hasText: categoryName })).toHaveCount(0);
  });

  test("admin can distinguish used and unused entries on Group Categories", async ({
    adminCommunityPage,
  }) => {
    // Load the group category taxonomy case with seeded used entries.
    const taxonomyCase = taxonomyCases[1];
    await navigateToPath(adminCommunityPage, taxonomyCase.path);

    // Verify used entries cannot be deleted while unused entries can.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText(taxonomyCase.heading, { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: taxonomyCase.addButton })).toBeEnabled();
    await expect(dashboardContent.locator(`#${taxonomyCase.usedDeleteId}`)).toBeDisabled();
    await expect(dashboardContent.locator(`#${taxonomyCase.unusedDeleteId}`)).toBeEnabled();
  });

  test("viewer sees read-only controls on Group Categories", async ({ communityViewerPage }) => {
    // Load the group category taxonomy case as a read-only viewer.
    const taxonomyCase = taxonomyCases[1];
    await navigateToPath(communityViewerPage, taxonomyCase.path);

    // Verify all mutation controls are disabled for the viewer.
    const dashboardContent = communityViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText(taxonomyCase.heading, { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: taxonomyCase.addButton })).toBeDisabled();
    await expect(dashboardContent.locator(`#${taxonomyCase.unusedDeleteId}`)).toBeDisabled();
  });
});
