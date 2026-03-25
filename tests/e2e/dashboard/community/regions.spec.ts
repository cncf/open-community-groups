import { expect, test } from "../../fixtures";

import { navigateToPath } from "../../utils";

import { taxonomyCases } from "./helpers";

test.describe("community dashboard regions tab", () => {
  test("admin can add and delete a region", async ({ adminCommunityPage }) => {
    const regionName = `E2E Region ${Date.now()}`;

    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=regions");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Regions", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Region" }).click();
    await expect(dashboardContent.getByText("Region Details", { exact: true })).toBeVisible();

    await adminCommunityPage.getByLabel("Name").fill(regionName);

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/community/regions/add") &&
          response.status() === 201,
      ),
      adminCommunityPage.getByRole("button", { name: "Add Region" }).click(),
    ]);

    const regionRow = dashboardContent.locator("tr", { hasText: regionName });
    await expect(regionRow).toBeVisible();

    await regionRow.getByRole("button", { name: `Delete region: ${regionName}` }).click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this region?",
    );

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/community/regions/") &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: regionName })).toHaveCount(0);
  });

  test("admin can distinguish used and unused entries on Regions", async ({
    adminCommunityPage,
  }) => {
    const taxonomyCase = taxonomyCases[0];
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

  test("viewer sees read-only controls on Regions", async ({ communityViewerPage }) => {
    const taxonomyCase = taxonomyCases[0];
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
});
