import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

import { taxonomyCases } from "../helpers.js";

test.describe("alliance dashboard group categories view", () => {
  test("admin can add and delete a group category", async ({
    adminAlliancePage,
  }) => {
    // Create a unique category name for the temporary category flow.
    const categoryName = `E2E Group Category ${Date.now()}`;

    // Load the group categories dashboard.
    await navigateToPath(
      adminAlliancePage,
      "/dashboard/alliance?tab=group-categories",
    );

    // Open the add form and submit the temporary category.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");
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
    await adminAlliancePage.getByLabel("Name").fill(categoryName);

    // Click Add Group Category.
    await Promise.all([
      adminAlliancePage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes("/dashboard/alliance/group-categories/add") &&
          response.status() === 201,
      ),
      adminAlliancePage
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
    await expect(adminAlliancePage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this group category?",
    );

    // Confirm deletion and verify the category is removed.
    await Promise.all([
      adminAlliancePage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/alliance/group-categories/") &&
          response.ok(),
      ),
      adminAlliancePage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert how many matching elements are shown.
    await expect(
      dashboardContent.locator("tr", { hasText: categoryName }),
    ).toHaveCount(0);
  });

  test("admin can distinguish used and unused entries on Group Categories", async ({
    adminAlliancePage,
  }) => {
    // Load the group category taxonomy case with seeded used entries.
    const taxonomyCase = taxonomyCases[1];
    await navigateToPath(adminAlliancePage, taxonomyCase.path);

    // Verify used entries cannot be deleted while unused entries can.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");
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
    allianceViewerPage,
  }) => {
    // Load the group category taxonomy case as a read-only viewer.
    const taxonomyCase = taxonomyCases[1];
    await navigateToPath(allianceViewerPage, taxonomyCase.path);

    // Verify all mutation controls are disabled for the viewer.
    const dashboardContent = allianceViewerPage.locator("#dashboard-content");
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
