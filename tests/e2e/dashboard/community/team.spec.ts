import { expect, test } from "../../fixtures";

import { TEST_USER_IDS, navigateToPath } from "../../utils";

import { ensureCommunityGroupsManagerRole } from "./helpers";

test.describe("community dashboard team tab", () => {
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

    const removeButton = pendingRow.locator(`#remove-member-${TEST_USER_IDS.pending2}`);
    await removeButton.click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this team member?",
    );

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/dashboard/community/team/${TEST_USER_IDS.pending2}/delete`) &&
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
    const seededRole = "groups-manager";
    const teamTabPath = "/dashboard/community?tab=team";

    await ensureCommunityGroupsManagerRole(seededRole, adminCommunityPage);

    try {
      await navigateToPath(adminCommunityPage, teamTabPath);

      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
      const groupsManagerRow = dashboardContent.locator("tr", {
        hasText: "E2E Groups Manager One",
      });
      const currentRoleSelect = groupsManagerRow.locator('select[name="role"]');

      await expect(
        dashboardContent.getByText("Community Team", { exact: true }),
      ).toBeVisible();
      await expect(currentRoleSelect).toHaveValue(seededRole);

      await Promise.all([
        adminCommunityPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/community/team/") &&
            response.url().endsWith("/role") &&
            response.ok(),
        ),
        currentRoleSelect.selectOption("viewer"),
      ]);

      await expect(currentRoleSelect).toHaveValue("viewer");
    } finally {
      await ensureCommunityGroupsManagerRole(seededRole, adminCommunityPage);
    }
  });
});
