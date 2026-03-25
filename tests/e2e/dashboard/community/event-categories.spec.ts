import { expect, test } from "../../fixtures";

import { navigateToPath } from "../../utils";

import { taxonomyCases } from "./helpers";

test.describe("community dashboard event categories view", () => {
  test("admin can add and delete an event category", async ({ adminCommunityPage }) => {
    const categoryName = `E2E Event Category ${Date.now()}`;

    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=event-categories");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Event Categories", { exact: true }),
    ).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Event Category" }).click();
    await expect(
      dashboardContent.getByText("Event Category Details", { exact: true }),
    ).toBeVisible();

    await adminCommunityPage.getByLabel("Name").fill(categoryName);

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/community/event-categories/add") &&
          response.status() === 201,
      ),
      adminCommunityPage.getByRole("button", { name: "Add Event Category" }).click(),
    ]);

    const categoryRow = dashboardContent.locator("tr", { hasText: categoryName });
    await expect(categoryRow).toBeVisible();

    await categoryRow
      .getByRole("button", { name: `Delete event category: ${categoryName}` })
      .click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this event category?",
    );

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/community/event-categories/") &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: categoryName })).toHaveCount(0);
  });

  test("admin can distinguish used and unused entries on Event Categories", async ({
    adminCommunityPage,
  }) => {
    const taxonomyCase = taxonomyCases[2];
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

  test("viewer sees read-only controls on Event Categories", async ({
    communityViewerPage,
  }) => {
    const taxonomyCase = taxonomyCases[2];
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
