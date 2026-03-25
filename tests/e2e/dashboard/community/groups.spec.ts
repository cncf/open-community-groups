import { expect, test } from "../../fixtures";

import { TEST_GROUP_IDS, navigateToPath } from "../../utils";

test.describe("community dashboard groups tab", () => {
  test("admin can deactivate and reactivate a group from the list", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    let betaGroupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(betaGroupRow).toBeVisible();
    await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);

    const openActionsMenu = async () => {
      await dashboardContent
        .locator(`.btn-group-actions[data-group-id="${TEST_GROUP_IDS.community1.beta}"]`)
        .click();
    };

    await openActionsMenu();

    const deactivateButton = dashboardContent.locator(
      `#deactivate-group-${TEST_GROUP_IDS.community1.beta}`,
    );
    await expect(deactivateButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(`/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/deactivate`) &&
          response.ok(),
      ),
      deactivateButton.click(),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    betaGroupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(betaGroupRow).toContainText("Inactive");
    await expect(
      betaGroupRow.getByRole("button", { name: "View group page: Inactive Local Chapter" }),
    ).toBeDisabled();

    await openActionsMenu();

    const activateButton = dashboardContent.locator(
      `#activate-group-${TEST_GROUP_IDS.community1.beta}`,
    );
    await expect(activateButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(`/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/activate`) &&
          response.ok(),
      ),
      activateButton.click(),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    betaGroupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);
    await expect(
      betaGroupRow.getByRole("link", { name: "View group page: Inactive Local Chapter" }),
    ).toBeVisible();
  });

  test("admin can add and delete a community group", async ({ adminCommunityPage }) => {
    const groupName = `E2E Community Group ${Date.now()}`;

    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Group" }).click();
    await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();

    await adminCommunityPage.getByLabel("Name").fill(groupName);
    await adminCommunityPage.getByLabel("Category").selectOption(
      "22222222-2222-2222-2222-222222222221",
    );
    await adminCommunityPage.getByLabel("Region").selectOption(
      "22222222-2222-2222-2222-222222222301",
    );
    await adminCommunityPage.getByLabel("Short Description").fill(
      "A short e2e-created community group.",
    );
    await adminCommunityPage
      .locator('markdown-editor#description .CodeMirror textarea')
      .fill("A community group created and removed by the e2e suite.");

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/community/groups/add") &&
          response.status() === 201,
      ),
      adminCommunityPage.getByRole("button", { name: "Create Group" }).click(),
    ]);

    const groupRow = dashboardContent.locator("tr", { hasText: groupName });
    await expect(groupRow).toBeVisible();

    await groupRow.getByRole("button", {
      name: `Open actions menu for group ${groupName}`,
    }).click();

    const deleteButton = groupRow.locator('button[id^="delete-group-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you wish to delete this group?",
    );

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/community/groups/") &&
          response.url().endsWith("/delete") &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: groupName })).toHaveCount(0);
  });

  test("admin can search community groups and clear the filter", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    const searchInput = dashboardContent.getByPlaceholder("Search groups");
    await searchInput.fill("Observability");

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/community/groups?ts_query=Observability") &&
          response.ok(),
      ),
      searchInput.press("Enter"),
    ]);

    await expect(adminCommunityPage).toHaveURL(/tab=groups.*ts_query=Observability/);
    await expect(
      dashboardContent.locator("tr", { hasText: "Observability Guild" }),
    ).toBeVisible();
    await expect(
      dashboardContent.locator("tr", { hasText: "Platform Ops Meetup" }),
    ).toHaveCount(0);

    await searchInput.fill("");
    await searchInput.fill("No matching group");
    await searchInput.press("Enter");

    await expect(
      dashboardContent
        .locator('div.text-xl.lg\\:text-2xl.mb-4:visible')
        .filter({ hasText: "No groups found matching your search." }),
    ).toBeVisible();

    const clearFilterButton = dashboardContent.locator(
      'button[hx-get="/dashboard/community/groups"]',
    );
    await expect(clearFilterButton).toBeVisible();
    await clearFilterButton.click();

    await expect(adminCommunityPage).toHaveURL(
      /\/dashboard\/community\?tab=groups(?:&limit=50&offset=0)?$/,
    );
    await expect(searchInput).toHaveValue("");
    await expect(
      dashboardContent.locator("tr", { hasText: "Platform Ops Meetup" }),
    ).toBeVisible();
    await expect(
      dashboardContent.locator("tr", { hasText: "Observability Guild" }),
    ).toBeVisible();
  });

  test("viewer sees read-only controls on community groups", async ({
    communityViewerPage,
  }) => {
    await navigateToPath(communityViewerPage, "/dashboard/community?tab=groups");

    const dashboardContent = communityViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add Group" }),
    ).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Add Group" }),
    ).toHaveAttribute("title", "Your role cannot add groups.");

    const betaGroupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(betaGroupRow).toBeVisible();

    const actionsButton = betaGroupRow.getByRole("button", {
      name: "Open actions menu for group Inactive Local Chapter",
    });
    await expect(actionsButton).toBeDisabled();
    await expect(actionsButton).toHaveAttribute(
      "title",
      "Your role cannot activate, deactivate, or delete groups.",
    );

    await Promise.all([
      communityViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/update`) &&
          response.ok(),
      ),
      betaGroupRow
        .locator(
          `button[hx-get="/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/update"]`,
        )
        .click(),
    ]);

    await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update groups.", { exact: true }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute("inert", "");
    await expect(dashboardContent.getByRole("button", { name: "Update Group" })).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Update Group" }),
    ).toHaveAttribute("title", "Your role cannot update groups.");
  });
});
