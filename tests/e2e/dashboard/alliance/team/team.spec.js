import { expect, test } from "../../../fixtures.js";

import { TEST_USER_IDS, navigateToPath } from "../../../utils.js";

import { ensureAllianceGroupsManagerRole } from "../helpers.js";

test.describe("alliance dashboard team view", () => {
  test("alliance team page shows seeded roles and final-admin protection", async ({
    adminAlliancePage,
  }) => {
    // Load the alliance team tab before checking seeded roles.
    await navigateToPath(adminAlliancePage, "/dashboard/alliance?tab=team");

    // Find the dashboard content.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");

    // Verify alliance team page shows seeded roles and final-admin protection.
    await expect(
      dashboardContent.getByText("Alliance Team", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add member" }),
    ).toBeEnabled();

    // Find the admin row.
    const adminRow = dashboardContent.locator("tr", {
      hasText: "E2E Admin One",
    });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.locator("select")).toHaveAttribute(
      "title",
      "At least one accepted admin is required.",
    );

    // Find the groups manager row.
    const groupsManagerRow = dashboardContent.locator("tr", {
      hasText: "E2E Groups Manager One",
    });
    await expect(groupsManagerRow.locator('select[name="role"]')).toBeEnabled();

    // Find the viewer row.
    const viewerRow = dashboardContent.locator("tr", {
      hasText: "E2E Alliance Viewer One",
    });
    await expect(viewerRow.locator('select[name="role"]')).toHaveValue(
      "viewer",
    );

    // Find the pending row.
    const pendingRow = dashboardContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    await expect(pendingRow).toContainText("e2e-pending-1");
    await expect(pendingRow.locator('select[name="role"]')).toHaveValue(
      "viewer",
    );
  });

  test("admin can invite and remove a pending alliance team member", async ({
    adminAlliancePage,
  }) => {
    // Load the alliance team tab before inviting a temporary member.
    await navigateToPath(adminAlliancePage, "/dashboard/alliance?tab=team");

    // Find the dashboard content.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");

    // Verify admin can invite and remove a pending alliance team member.
    await expect(
      dashboardContent.getByText("Alliance Team", { exact: true }),
    ).toBeVisible();

    // Click Add member.
    await dashboardContent.getByRole("button", { name: "Add member" }).click();

    // Find the add member form.
    const addMemberForm = adminAlliancePage.locator("#team-add-form");
    await expect(addMemberForm).toBeVisible();

    // Find the search input.
    const searchInput = addMemberForm.locator("#search-input");
    await Promise.all([
      adminAlliancePage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes("/dashboard/alliance/users/search?q=e2e-pending-2") &&
          response.ok(),
      ),
      searchInput.fill("e2e-pending-2"),
    ]);

    // Click E2E Pending Two.
    await addMemberForm.getByText("E2E Pending Two", { exact: true }).click();
    await addMemberForm.locator("#team-add-role").selectOption("viewer");

    // Submit and wait for the server response.
    await Promise.all([
      adminAlliancePage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/alliance/team/add") &&
          response.status() === 201,
      ),
      addMemberForm.locator("#team-add-submit").click(),
    ]);

    // Find the pending row.
    const pendingRow = dashboardContent.locator("tr", {
      hasText: "E2E Pending Two",
    });
    await expect(pendingRow).toBeVisible();
    await expect(pendingRow).toContainText("Invitation sent");
    await expect(pendingRow.locator('select[name="role"]')).toHaveValue(
      "viewer",
    );

    // Find the remove button.
    const removeButton = pendingRow.locator(
      `#remove-member-${TEST_USER_IDS.pending2}`,
    );
    await removeButton.click();
    await expect(adminAlliancePage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this team member?",
    );

    // Click Yes.
    await Promise.all([
      adminAlliancePage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response
            .url()
            .includes(
              `/dashboard/alliance/team/${TEST_USER_IDS.pending2}/delete`,
            ) &&
          response.ok(),
      ),
      adminAlliancePage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert how many matching elements are shown.
    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Pending Two" }),
    ).toHaveCount(0);
  });

  test("admin can update and restore a alliance team member role", async ({
    adminAlliancePage,
  }) => {
    // Define the seeded team member role that must be restored.
    const seededRole = "groups-manager";
    const teamTabPath = "/dashboard/alliance?tab=team";

    // Give the member group manager permissions.
    await ensureAllianceGroupsManagerRole(seededRole, adminAlliancePage);

    // Restore the changed permissions after this check.
    try {
      await navigateToPath(adminAlliancePage, teamTabPath);

      // Find the dashboard content.
      const dashboardContent = adminAlliancePage.locator("#dashboard-content");
      const groupsManagerRow = dashboardContent.locator("tr", {
        hasText: "E2E Groups Manager One",
      });
      const currentRoleSelect = groupsManagerRow.locator('select[name="role"]');

      // Verify admin can update and restore a alliance team member role.
      await expect(
        dashboardContent.getByText("Alliance Team", { exact: true }),
      ).toBeVisible();
      await expect(currentRoleSelect).toHaveValue(seededRole);

      // Submit and wait for the server response.
      await Promise.all([
        adminAlliancePage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/alliance/team/") &&
            response.url().endsWith("/role") &&
            response.ok(),
        ),
        currentRoleSelect.selectOption("viewer"),
      ]);

      // Assert the field value was updated.
      await expect(currentRoleSelect).toHaveValue("viewer");
    } finally {
      await ensureAllianceGroupsManagerRole(seededRole, adminAlliancePage);
    }
  });
});
