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

test.describe("community dashboard event categories view", () => {
  test("empty state guides the first event category", async ({
    adminEmptyCommunityPage,
  }) => {
    // Load event categories for the dedicated community without taxonomy records.
    await navigateToPath(
      adminEmptyCommunityPage,
      "/dashboard/community?tab=event-categories",
    );
    const dashboardContent = adminEmptyCommunityPage.locator(
      "#dashboard-content",
    );

    // Verify first-use guidance and the creation action remain available.
    await expect(dashboardContent).toContainText(
      "No event categories found for this community yet.",
    );
    await expect(
      dashboardContent.getByRole("button", { name: "Add Event Category" }),
    ).toBeVisible();
  });

  test("event categories table exposes its responsive columns", async ({ adminCommunityPage }) => {
    // Load the event categories dashboard before checking table structure.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=event-categories");

    // Find the event categories table.
    const categoriesTable = adminCommunityPage.locator("#dashboard-content").getByRole("table");

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableHeaders(categoriesTable, ["Name", "Events", "Actions"]);
    await expectTableColumnsAtViewport(
      adminCommunityPage,
      categoriesTable,
      1024,
      ["Name", "Actions"],
      ["Events"],
    );
    await expectTableColumnsAtViewport(
      adminCommunityPage,
      categoriesTable,
      1280,
      ["Name", "Events", "Actions"],
      [],
    );
  });

  test("admin can add, update, and delete an event category", async ({ adminCommunityPage }) => {
    test.setTimeout(60_000);

    // Create a unique category name for the temporary category flow.
    const categoryName = `E2E Event Category ${Date.now()}`;
    const updatedCategoryName = `${categoryName} Updated`;

    // Load the event categories dashboard.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=event-categories");

    // Open the add form and submit the temporary category.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Event Categories", { exact: true })).toBeVisible();

    // Click Add Event Category.
    await dashboardContent.getByRole("button", { name: "Add Event Category" }).click();
    await expect(dashboardContent.getByText("Event Category Details", { exact: true })).toBeVisible();

    // Fill Name.
    await adminCommunityPage.getByLabel("Name").fill(categoryName);

    // Click Add Event Category.
    await waitForCommunityDashboardMutation(
      adminCommunityPage,
      "/dashboard/community/event-categories",
      () => adminCommunityPage.getByRole("button", { name: "Add Event Category" }).click(),
      { method: "POST", urlIncludes: "/dashboard/community/event-categories/add", status: 201 },
    );

    // Verify the temporary category appears before deleting it.
    let categoryRow = dashboardContent.locator("tr", {
      hasText: categoryName,
    });
    await expect(categoryRow).toBeVisible();

    // Edit the temporary category and wait for the update form to load.
    await waitForActionResponse(
      adminCommunityPage,
      () => categoryRow.getByRole("button", { name: `Edit event category: ${categoryName}` }).click(),
      { method: "GET", urlIncludes: "/dashboard/community/event-categories/", urlEndsWith: "/update" },
    );
    await adminCommunityPage.getByLabel("Name").fill(updatedCategoryName);
    await waitForCommunityDashboardMutation(
      adminCommunityPage,
      "/dashboard/community/event-categories",
      () => adminCommunityPage.getByRole("button", { name: "Update Event Category" }).click(),
      { method: "PUT", urlIncludes: "/dashboard/community/event-categories/", urlEndsWith: "/update" },
    );
    // Find the renamed category and verify it is rendered.
    categoryRow = dashboardContent.locator("tr", {
      hasText: updatedCategoryName,
    });
    await expect(categoryRow).toBeVisible();

    // Delete the event category from its row action.
    await categoryRow
      .getByRole("button", {
        name: `Delete event category: ${updatedCategoryName}`,
      })
      .click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this event category?",
    );

    // Confirm deletion and verify the category is removed.
    await waitForCommunityDashboardMutation(
      adminCommunityPage,
      "/dashboard/community/event-categories",
      () => adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
      { method: "DELETE", urlIncludes: "/dashboard/community/event-categories/" },
    );

    // Assert how many matching elements are shown.
    await expect(dashboardContent.locator("tr", { hasText: categoryName })).toHaveCount(0);
  });

  test("admin can distinguish used and unused entries on Event Categories", async ({
    adminCommunityPage,
  }) => {
    // Load the event category taxonomy case with seeded used entries.
    const taxonomyCase = taxonomyCases[2];
    await navigateToPath(adminCommunityPage, taxonomyCase.path);

    // Verify used entries cannot be deleted while unused entries can.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText(taxonomyCase.heading, { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: taxonomyCase.addButton })).toBeEnabled();
    await expect(dashboardContent.locator(`#${taxonomyCase.usedDeleteId}`)).toBeDisabled();
    await expect(dashboardContent.locator(`#${taxonomyCase.unusedDeleteId}`)).toBeEnabled();
  });

  test("viewer sees read-only controls on Event Categories", async ({ communityViewerPage }) => {
    // Load the event category taxonomy case as a read-only viewer.
    const taxonomyCase = taxonomyCases[2];
    await navigateToPath(communityViewerPage, taxonomyCase.path);

    // Verify all mutation controls are disabled for the viewer.
    const dashboardContent = communityViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText(taxonomyCase.heading, { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: taxonomyCase.addButton })).toBeDisabled();
    await expect(dashboardContent.locator(`#${taxonomyCase.unusedDeleteId}`)).toBeDisabled();
  });
});
