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

test.describe("community dashboard regions view", () => {
  test("empty state guides the first community region", async ({
    adminEmptyCommunityPage,
  }) => {
    // Load regions for the dedicated community without taxonomy records.
    await navigateToPath(
      adminEmptyCommunityPage,
      "/dashboard/community?tab=regions",
    );
    const dashboardContent = adminEmptyCommunityPage.locator(
      "#dashboard-content",
    );

    // Verify first-use guidance and the creation action remain available.
    await expect(dashboardContent).toContainText(
      "No regions found for this community yet.",
    );
    await expect(
      dashboardContent.getByRole("button", { name: "Add Region" }),
    ).toBeVisible();
  });

  test("regions table exposes its responsive columns", async ({ adminCommunityPage }) => {
    // Load the regions dashboard before checking table structure.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=regions");

    // Find the regions table.
    const regionsTable = adminCommunityPage.locator("#dashboard-content").getByRole("table");

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableHeaders(regionsTable, ["Name", "Groups", "Actions"]);
    await expectTableColumnsAtViewport(
      adminCommunityPage,
      regionsTable,
      1024,
      ["Name", "Actions"],
      ["Groups"],
    );
    await expectTableColumnsAtViewport(
      adminCommunityPage,
      regionsTable,
      1280,
      ["Name", "Groups", "Actions"],
      [],
    );
  });

  test("admin can add, update, and delete a region", async ({ adminCommunityPage }) => {
    test.setTimeout(60_000);

    // Create a unique region name for the temporary region flow.
    const regionName = `E2E Region ${Date.now()}`;
    const updatedRegionName = `${regionName} Updated`;

    // Load the regions dashboard.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=regions");

    // Open the add form and submit the temporary region.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Regions", { exact: true })).toBeVisible();

    // Click Add Region.
    await dashboardContent.getByRole("button", { name: "Add Region" }).click();
    await expect(dashboardContent.getByText("Region Details", { exact: true })).toBeVisible();

    // Fill Name.
    await adminCommunityPage.getByLabel("Name").fill(regionName);

    // Click Add Region.
    await waitForCommunityDashboardMutation(
      adminCommunityPage,
      "/dashboard/community/regions",
      () => adminCommunityPage.getByRole("button", { name: "Add Region" }).click(),
      { method: "POST", urlIncludes: "/dashboard/community/regions/add", status: 201 },
    );

    // Verify the temporary region appears before deleting it.
    let regionRow = dashboardContent.locator("tr", { hasText: regionName });
    await expect(regionRow).toBeVisible();

    // Edit the temporary region and wait for the update form to load.
    await waitForActionResponse(
      adminCommunityPage,
      () => regionRow.getByRole("button", { name: `Edit region: ${regionName}` }).click(),
      { method: "GET", urlIncludes: "/dashboard/community/regions/", urlEndsWith: "/update" },
    );
    await adminCommunityPage.getByLabel("Name").fill(updatedRegionName);
    await waitForCommunityDashboardMutation(
      adminCommunityPage,
      "/dashboard/community/regions",
      () => adminCommunityPage.getByRole("button", { name: "Update Region" }).click(),
      { method: "PUT", urlIncludes: "/dashboard/community/regions/", urlEndsWith: "/update" },
    );
    // Find the renamed region and verify it is rendered.
    regionRow = dashboardContent.locator("tr", {
      hasText: updatedRegionName,
    });
    await expect(regionRow).toBeVisible();

    // Delete the region from its row action.
    await regionRow.getByRole("button", { name: `Delete region: ${updatedRegionName}` }).click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this region?",
    );

    // Confirm deletion and verify the region is removed.
    await waitForCommunityDashboardMutation(
      adminCommunityPage,
      "/dashboard/community/regions",
      () => adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
      { method: "DELETE", urlIncludes: "/dashboard/community/regions/" },
    );

    // Assert how many matching elements are shown.
    await expect(dashboardContent.locator("tr", { hasText: regionName })).toHaveCount(0);
  });

  test("admin can distinguish used and unused entries on Regions", async ({ adminCommunityPage }) => {
    // Load the region taxonomy case with seeded used entries.
    const taxonomyCase = taxonomyCases[0];
    await navigateToPath(adminCommunityPage, taxonomyCase.path);

    // Verify used entries cannot be deleted while unused entries can.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText(taxonomyCase.heading, { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: taxonomyCase.addButton })).toBeEnabled();
    await expect(dashboardContent.locator(`#${taxonomyCase.usedDeleteId}`)).toBeDisabled();
    await expect(dashboardContent.locator(`#${taxonomyCase.unusedDeleteId}`)).toBeEnabled();
  });

  test("viewer sees read-only controls on Regions", async ({ communityViewerPage }) => {
    // Load the region taxonomy case as a read-only viewer.
    const taxonomyCase = taxonomyCases[0];
    await navigateToPath(communityViewerPage, taxonomyCase.path);

    // Verify all mutation controls are disabled for the viewer.
    const dashboardContent = communityViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText(taxonomyCase.heading, { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: taxonomyCase.addButton })).toBeDisabled();
    await expect(dashboardContent.locator(`#${taxonomyCase.unusedDeleteId}`)).toBeDisabled();
  });
});
