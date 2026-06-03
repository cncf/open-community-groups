import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

import { taxonomyCases } from "../helpers.js";

test.describe("community dashboard group categories view", () => {
  test("admin can add and delete a group category", async ({
    adminCommunityPage,
  }) => {
    // Create a unique category name for the temporary category flow.
    const categoryName = `E2E Group Category ${Date.now()}`;

    // Load the group categories dashboard.
    await navigateToPath(
      adminCommunityPage,
      "/dashboard/community?tab=group-categories",
    );

    // Open the add form and submit the temporary category.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Group Categories", { exact: true }),
    ).toBeVisible();

    // Click Add Group Category.
    await dashboardContent
      .getByRole("button", { name: "Add Group Category" })
      .click();
    await expect(
      dashboardContent.getByText("Group Category Details", { exact: true }),
    ).toBeVisible();

    // Fill Name.
    await adminCommunityPage.getByLabel("Name").fill(categoryName);

    // Click Add Group Category.
    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes("/dashboard/community/group-categories/add") &&
          response.status() === 201,
      ),
      adminCommunityPage
        .getByRole("button", { name: "Add Group Category" })
        .click(),
    ]);

    // Verify the temporary category appears before deleting it.
    const categoryRow = dashboardContent.locator("tr", {
      hasText: categoryName,
    });
    await expect(categoryRow).toBeVisible();

    // Delete the group category from its row action.
    await categoryRow
      .getByRole("button", { name: `Delete group category: ${categoryName}` })
      .click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this group category?",
    );

    // Confirm deletion and verify the category is removed.
    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/community/group-categories/") &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert how many matching elements are shown.
    await expect(
      dashboardContent.locator("tr", { hasText: categoryName }),
    ).toHaveCount(0);
  });

  test("admin can distinguish used and unused entries on Group Categories", async ({
    adminCommunityPage,
  }) => {
    // Load the group category taxonomy case with seeded used entries.
    const taxonomyCase = taxonomyCases[1];
    await navigateToPath(adminCommunityPage, taxonomyCase.path);

    // Verify used entries cannot be deleted while unused entries can.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText(taxonomyCase.heading, { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: taxonomyCase.addButton }),
    ).toBeEnabled();
    await expect(
      dashboardContent.locator(`#${taxonomyCase.usedDeleteId}`),
    ).toBeDisabled();
    await expect(
      dashboardContent.locator(`#${taxonomyCase.unusedDeleteId}`),
    ).toBeEnabled();
  });

  test("viewer sees read-only controls on Group Categories", async ({
    communityViewerPage,
  }) => {
    // Load the group category taxonomy case as a read-only viewer.
    const taxonomyCase = taxonomyCases[1];
    await navigateToPath(communityViewerPage, taxonomyCase.path);

    // Verify all mutation controls are disabled for the viewer.
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
});
