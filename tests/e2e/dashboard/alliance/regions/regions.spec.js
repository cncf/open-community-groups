import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

import { taxonomyCases } from "../helpers.js";

test.describe("alliance dashboard regions view", () => {
  test("admin can add and delete a region", async ({ adminAlliancePage }) => {
    // Create a unique region name for the temporary region flow.
    const regionName = `E2E Region ${Date.now()}`;

    // Load the regions dashboard.
    await navigateToPath(
      adminAlliancePage,
      "/dashboard/alliance?tab=regions",
    );

    // Open the add form and submit the temporary region.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Regions", { exact: true }),
    ).toBeVisible();

    // Click Add Region.
    await dashboardContent.getByRole("button", { name: "Add Region" }).click();
    await expect(
      dashboardContent.getByText("Region Details", { exact: true }),
    ).toBeVisible();

    // Fill Name.
    await adminAlliancePage.getByLabel("Name").fill(regionName);

    // Click Add Region.
    await Promise.all([
      adminAlliancePage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/alliance/regions/add") &&
          response.status() === 201,
      ),
      adminAlliancePage.getByRole("button", { name: "Add Region" }).click(),
    ]);

    // Verify the temporary region appears before deleting it.
    const regionRow = dashboardContent.locator("tr", { hasText: regionName });
    await expect(regionRow).toBeVisible();

    // Delete the region from its row action.
    await regionRow
      .getByRole("button", { name: `Delete region: ${regionName}` })
      .click();
    await expect(adminAlliancePage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this region?",
    );

    // Confirm deletion and verify the region is removed.
    await Promise.all([
      adminAlliancePage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/alliance/regions/") &&
          response.ok(),
      ),
      adminAlliancePage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert how many matching elements are shown.
    await expect(
      dashboardContent.locator("tr", { hasText: regionName }),
    ).toHaveCount(0);
  });

  test("admin can distinguish used and unused entries on Regions", async ({
    adminAlliancePage,
  }) => {
    // Load the region taxonomy case with seeded used entries.
    const taxonomyCase = taxonomyCases[0];
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

  test("viewer sees read-only controls on Regions", async ({
    allianceViewerPage,
  }) => {
    // Load the region taxonomy case as a read-only viewer.
    const taxonomyCase = taxonomyCases[0];
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
