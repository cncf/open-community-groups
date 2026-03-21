import { expect, test } from "../fixtures";

import {
  navigateToPath,
} from "../utils";

const BETA_GROUP_ID = "44444444-4444-4444-4444-444444444442";
const GAMMA_GROUP_SLUG = "test-group-gamma";
const PENDING2_USER_ID = "77777777-7777-7777-7777-777777777708";
const COMMUNITY_GROUPS_MANAGER_USER_ID = "77777777-7777-7777-7777-777777777709";

const taxonomyCases = [
  {
    path: "/dashboard/community?tab=regions",
    heading: "Regions",
    addButton: "Add Region",
    usedDeleteId: "delete-region-22222222-2222-2222-2222-222222222301",
    unusedDeleteId: "delete-region-22222222-2222-2222-2222-222222222302",
  },
  {
    path: "/dashboard/community?tab=group-categories",
    heading: "Group Categories",
    addButton: "Add Group Category",
    usedDeleteId: "delete-group-category-22222222-2222-2222-2222-222222222221",
    unusedDeleteId: "delete-group-category-22222222-2222-2222-2222-222222222223",
  },
  {
    path: "/dashboard/community?tab=event-categories",
    heading: "Event Categories",
    addButton: "Add Event Category",
    usedDeleteId: "delete-event-category-33333333-3333-3333-3333-333333333331",
    unusedDeleteId: "delete-event-category-33333333-3333-3333-3333-333333333333",
  },
] as const;

test.describe("community dashboard", () => {
  test("community team page shows seeded roles and final-admin protection", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=team");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Community Team", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add member" }),
    ).toBeEnabled();

    const adminRow = dashboardContent.locator("tr", { hasText: "E2E Admin One" });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.locator("select")).toHaveAttribute(
      "title",
      "At least one accepted admin is required.",
    );

    const groupsManagerRow = dashboardContent.locator("tr", {
      hasText: "E2E Groups Manager One",
    });
    await expect(groupsManagerRow.locator('select[name="role"]')).toBeEnabled();

    const viewerRow = dashboardContent.locator("tr", {
      hasText: "E2E Community Viewer One",
    });
    await expect(viewerRow.locator('select[name="role"]')).toHaveValue("viewer");

    const pendingRow = dashboardContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    await expect(pendingRow).toContainText("e2e-pending-1");
    await expect(pendingRow.locator('select[name="role"]')).toHaveValue("viewer");
  });

  test("admin can invite and remove a pending community team member", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=team");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Community Team", { exact: true }),
    ).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add member" }).click();

    const addMemberForm = adminCommunityPage.locator("#team-add-form");
    await expect(addMemberForm).toBeVisible();

    const searchInput = addMemberForm.locator("#search-input");
    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/community/users/search?q=e2e-pending-2") &&
          response.ok(),
      ),
      searchInput.fill("e2e-pending-2"),
    ]);

    await addMemberForm.getByText("E2E Pending Two", { exact: true }).click();
    await addMemberForm.locator("#team-add-role").selectOption("viewer");

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/community/team/add") &&
          response.status() === 201,
      ),
      addMemberForm.locator("#team-add-submit").click(),
    ]);

    const pendingRow = dashboardContent.locator("tr", {
      hasText: "E2E Pending Two",
    });
    await expect(pendingRow).toBeVisible();
    await expect(pendingRow).toContainText("Invitation sent");
    await expect(pendingRow.locator('select[name="role"]')).toHaveValue("viewer");

    const removeButton = pendingRow.locator(`#remove-member-${PENDING2_USER_ID}`);
    await removeButton.click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this team member?",
    );

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/dashboard/community/team/${PENDING2_USER_ID}/delete`) &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Pending Two" }),
    ).toHaveCount(0);
  });

  test("admin can update and restore a community team member role", async ({
    adminCommunityPage,
  }) => {
    const SEEDED_ROLE = "groups-manager";
    const teamTabPath = "/dashboard/community?tab=team";

    await navigateToPath(adminCommunityPage, teamTabPath);

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    const roleFormSelector =
      `form[hx-put="/dashboard/community/team/${COMMUNITY_GROUPS_MANAGER_USER_ID}/role"]`;
    const updateRole = async (role: string) => {
      const response = await adminCommunityPage.request.put(
        `/dashboard/community/team/${COMMUNITY_GROUPS_MANAGER_USER_ID}/role`,
        {
          form: { role },
        },
      );
      expect(response.ok()).toBeTruthy();
      await navigateToPath(adminCommunityPage, teamTabPath);
    };
    const currentRoleSelect = () =>
      dashboardContent.locator(roleFormSelector).locator('select[name="role"]');

    await expect(
      dashboardContent.getByText("Community Team", { exact: true }),
    ).toBeVisible();
    const currentRole = await currentRoleSelect().inputValue();
    if (currentRole !== SEEDED_ROLE) {
      await updateRole(SEEDED_ROLE);
    }

    await expect(currentRoleSelect()).toHaveValue(SEEDED_ROLE);

    await updateRole("viewer");
    await expect(currentRoleSelect()).toHaveValue("viewer");

    await updateRole(SEEDED_ROLE);
    await expect(currentRoleSelect()).toHaveValue(SEEDED_ROLE);
  });

  test("admin can deactivate and reactivate a group from the list", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    let betaGroupRow = dashboardContent.locator("tr", {
      hasText: "E2E Test Group Beta",
    });
    await expect(betaGroupRow).toBeVisible();
    await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);

    const openActionsMenu = async () => {
      await dashboardContent
        .locator(`.btn-group-actions[data-group-id="${BETA_GROUP_ID}"]`)
        .click();
    };

    await openActionsMenu();

    const deactivateButton = dashboardContent.locator(`#deactivate-group-${BETA_GROUP_ID}`);
    await expect(deactivateButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/community/groups/${BETA_GROUP_ID}/deactivate`) &&
          response.ok(),
      ),
      deactivateButton.click(),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    betaGroupRow = dashboardContent.locator("tr", {
      hasText: "E2E Test Group Beta",
    });
    await expect(betaGroupRow).toContainText("Inactive");
    await expect(
      betaGroupRow.getByRole("button", { name: "View group page: E2E Test Group Beta" }),
    ).toBeDisabled();

    await openActionsMenu();

    const activateButton = dashboardContent.locator(`#activate-group-${BETA_GROUP_ID}`);
    await expect(activateButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/community/groups/${BETA_GROUP_ID}/activate`) &&
          response.ok(),
      ),
      activateButton.click(),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    betaGroupRow = dashboardContent.locator("tr", {
      hasText: "E2E Test Group Beta",
    });
    await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);
    await expect(
      betaGroupRow.getByRole("link", { name: "View group page: E2E Test Group Beta" }),
    ).toBeVisible();
  });

  test("admin can add and delete a community group", async ({
    adminCommunityPage,
  }) => {
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
    await searchInput.fill("Gamma");

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/community/groups?ts_query=Gamma") &&
          response.ok(),
      ),
      searchInput.press("Enter"),
    ]);

    await expect(adminCommunityPage).toHaveURL(/tab=groups.*ts_query=Gamma/);
    await expect(dashboardContent.locator("tr", { hasText: "E2E Test Group Gamma" })).toBeVisible();
    await expect(dashboardContent.locator("tr", { hasText: "E2E Test Group Alpha" })).toHaveCount(0);

    await searchInput.fill("");
    await searchInput.fill("No matching group");

    await searchInput.press("Enter");

    await expect(
      dashboardContent
        .locator('div.text-xl.lg\\:text-2xl.mb-4:visible')
        .filter({ hasText: "No groups found matching your search." }),
    ).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/community/groups") &&
          !response.url().includes("ts_query=") &&
          response.ok(),
      ),
      dashboardContent.locator('button[hx-get="/dashboard/community/groups"]').click(),
    ]);

    await expect(adminCommunityPage).toHaveURL(/\/dashboard\/community\?tab=groups(?:&limit=50&offset=0)?$/);
    await expect(dashboardContent.locator("tr", { hasText: "E2E Test Group Alpha" })).toBeVisible();
    await expect(dashboardContent.locator("tr", { hasText: "E2E Test Group Gamma" })).toBeVisible();
  });

  test("admin can open a selected group dashboard from the groups list", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    const openGroupButton = dashboardContent.getByRole("button", {
      name: "Open group dashboard: E2E Test Group Gamma",
    });

    await expect(openGroupButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForURL(/\/dashboard\/group$/),
      openGroupButton.click(),
    ]);

    await expect(adminCommunityPage.getByText("Group Dashboard", { exact: true }).last()).toBeVisible();
    await expect(adminCommunityPage.locator("#group-selector-button")).toContainText(
      "E2E Test Group Gamma",
    );
    await expect(adminCommunityPage.locator("#dashboard-content")).toHaveAttribute(
      "data-group-slug",
      GAMMA_GROUP_SLUG,
    );
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
      hasText: "E2E Test Group Beta",
    });
    await expect(betaGroupRow).toBeVisible();

    const actionsButton = betaGroupRow.getByRole("button", {
      name: "Open actions menu for group E2E Test Group Beta",
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
          response.url().includes(`/dashboard/community/groups/${BETA_GROUP_ID}/update`) &&
          response.ok(),
      ),
      betaGroupRow.locator(`button[hx-get="/dashboard/community/groups/${BETA_GROUP_ID}/update"]`).click(),
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

  test("admin can add and delete a region", async ({
    adminCommunityPage,
  }) => {
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

  test("admin can add and delete an event category", async ({
    adminCommunityPage,
  }) => {
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

  test("admin can add and delete a group category", async ({
    adminCommunityPage,
  }) => {
    const categoryName = `E2E Group Category ${Date.now()}`;

    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=group-categories");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Group Categories", { exact: true }),
    ).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Group Category" }).click();
    await expect(
      dashboardContent.getByText("Group Category Details", { exact: true }),
    ).toBeVisible();

    await adminCommunityPage.getByLabel("Name").fill(categoryName);

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/community/group-categories/add") &&
          response.status() === 201,
      ),
      adminCommunityPage.getByRole("button", { name: "Add Group Category" }).click(),
    ]);

    const categoryRow = dashboardContent.locator("tr", { hasText: categoryName });
    await expect(categoryRow).toBeVisible();

    await categoryRow
      .getByRole("button", { name: `Delete group category: ${categoryName}` })
      .click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this group category?",
    );

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/community/group-categories/") &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: categoryName })).toHaveCount(0);
  });

  test("admin can update and restore community settings", async ({
    adminCommunityPage,
  }) => {
    const originalDisplayName = "E2E Test Community";
    const originalDescription = "E2E test community description";
    const originalLogoUrl = "https://example.com/logo.png";
    const originalBannerUrl = "https://example.com/banner.png";
    const originalBannerMobileUrl = "https://example.com/banner-mobile.png";
    const originalWebsite = "";
    const updatedDisplayName = `E2E Test Community ${Date.now()}`;
    const updatedWebsite = "https://community-e2e.example.com";
    const settingsPath = "/dashboard/community?tab=settings";

    const submitSettings = async (displayName: string, websiteUrl: string) => {
      await navigateToPath(adminCommunityPage, settingsPath);

      const displayNameInput = adminCommunityPage.getByLabel("Display Name");
      const websiteInput = adminCommunityPage.getByLabel("Website");
      const settingsForm = adminCommunityPage.locator("#settings-form");

      await expect(displayNameInput).toBeVisible();
      await displayNameInput.fill(displayName);
      await websiteInput.fill(websiteUrl);

      await expect(settingsForm).toBeVisible();

      const formData: Record<string, string> = {
        banner_mobile_url: originalBannerMobileUrl,
        banner_url: originalBannerUrl,
        description: originalDescription,
        display_name: displayName,
        logo_url: originalLogoUrl,
      };

      if (websiteUrl !== "") {
        formData.website_url = websiteUrl;
      }

      const response = await adminCommunityPage.request.put(
        "/dashboard/community/settings/update",
        {
          form: formData,
        },
      );
      expect(response.ok()).toBeTruthy();

      await navigateToPath(adminCommunityPage, settingsPath);
      await expect(adminCommunityPage.getByLabel("Display Name")).toHaveValue(displayName);
      await expect(adminCommunityPage.getByLabel("Website")).toHaveValue(websiteUrl);
    };

    await submitSettings(updatedDisplayName, updatedWebsite);
    await submitSettings(originalDisplayName, originalWebsite);
  });

  test("viewer sees read-only controls on community settings", async ({
    communityViewerPage,
  }) => {
    await navigateToPath(communityViewerPage, "/dashboard/community?tab=settings");

    const dashboardContent = communityViewerPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("General Settings", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update community settings.", { exact: true }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute("inert", "");
    await expect(
      dashboardContent.getByRole("button", { name: "Update Settings" }),
    ).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Update Settings" }),
    ).toHaveAttribute("title", "Your role cannot update community settings.");
  });

  for (const taxonomyCase of taxonomyCases) {
    test(`admin can distinguish used and unused entries on ${taxonomyCase.heading}`, async ({
      adminCommunityPage,
    }) => {
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

    test(`viewer sees read-only controls on ${taxonomyCase.heading}`, async ({
      communityViewerPage,
    }) => {
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
  }
});
