import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

import { taxonomyCases } from "../helpers.js";

test.describe("community dashboard regions view", () => {
  test("admin can add and delete a region", async ({ adminCommunityPage }) => {
    // Create a unique region name for the temporary region flow.
    const regionName = `E2E Region ${Date.now()}`;

    // Load the regions dashboard.
    await navigateToPath(
      adminCommunityPage,
      "/dashboard/community?tab=regions",
    );

    // Open the add form and submit the temporary region.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Regions", { exact: true }),
    ).toBeVisible();

    // Click Add Region.
    await dashboardContent.getByRole("button", { name: "Add Region" }).click();
    await expect(
      dashboardContent.getByText("Region Details", { exact: true }),
    ).toBeVisible();

    // Fill Name.
    await adminCommunityPage.getByLabel("Name").fill(regionName);

    // Click Add Region.
    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/community/regions/add") &&
          response.status() === 201,
      ),
      adminCommunityPage.getByRole("button", { name: "Add Region" }).click(),
    ]);

    // Verify the temporary region appears before deleting it.
    const regionRow = dashboardContent.locator("tr", { hasText: regionName });
    await expect(regionRow).toBeVisible();

    // Delete the region from its row action.
    await regionRow
      .getByRole("button", { name: `Delete region: ${regionName}` })
      .click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this region?",
    );

    // Confirm deletion and verify the region is removed.
    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/community/regions/") &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert how many matching elements are shown.
    await expect(
      dashboardContent.locator("tr", { hasText: regionName }),
    ).toHaveCount(0);
  });

  test("admin can distinguish used and unused entries on Regions", async ({
    adminCommunityPage,
  }) => {
    // Load the region taxonomy case with seeded used entries.
    const taxonomyCase = taxonomyCases[0];
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

  test("viewer sees read-only controls on Regions", async ({
    communityViewerPage,
  }) => {
    // Load the region taxonomy case as a read-only viewer.
    const taxonomyCase = taxonomyCases[0];
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
