import { expect, test } from "../../../fixtures.js";

import { TEST_USER_IDS, navigateToPath } from "../../../utils.js";

import { ensureGroupViewerRole } from "../helpers.js";

test.describe("group dashboard team view", () => {
  test("group team page shows seeded roles and last-admin protection", async ({
    organizerGroupPage,
  }) => {
    // Restore the seeded viewer role before checking team permissions.
    await ensureGroupViewerRole(organizerGroupPage, "viewer");
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify group team page shows seeded roles and last-admin protection.
    await expect(
      dashboardContent.getByText("Group Team", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add member" }),
    ).toBeEnabled();

    // Find the admin row.
    const adminRow = dashboardContent.locator("tr", {
      hasText: "E2E Organizer One",
    });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.locator("select")).toHaveAttribute(
      "title",
      "At least one accepted admin is required.",
    );

    // Find the events manager row.
    const eventsManagerRow = dashboardContent.locator("tr", {
      hasText: "E2E Events Manager One",
    });
    await expect(eventsManagerRow.locator('select[name="role"]')).toHaveValue(
      "events-manager",
    );

    // Find the viewer row.
    const viewerRow = dashboardContent.locator("tr", {
      hasText: "E2E Group Viewer One",
    });
    await expect(viewerRow.locator('select[name="role"]')).toHaveValue(
      "viewer",
    );
  });

  test("organizer can invite and remove a pending group team member", async ({
    organizerGroupPage,
  }) => {
    // Load the group team tab before inviting a temporary member.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can invite and remove a pending group team member.
    await expect(
      dashboardContent.getByText("Group Team", { exact: true }),
    ).toBeVisible();

    // Click Add member.
    await dashboardContent.getByRole("button", { name: "Add member" }).click();

    // Find the add member form.
    const addMemberForm = organizerGroupPage.locator("#team-add-form");
    await expect(addMemberForm).toBeVisible();

    // Find the search input.
    const searchInput = addMemberForm.locator("#search-input");
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes("/dashboard/group/users/search?q=e2e-pending-1") &&
          response.ok(),
      ),
      searchInput.fill("e2e-pending-1"),
    ]);

    // Click E2E Pending One.
    await addMemberForm.getByText("E2E Pending One", { exact: true }).click();
    await addMemberForm.locator("#team-add-role").selectOption("viewer");

    // Submit and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/team/add") &&
          response.status() === 201,
      ),
      addMemberForm.locator("#team-add-submit").click(),
    ]);

    // Find the pending row.
    const pendingRow = dashboardContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    await expect(pendingRow).toBeVisible();
    await expect(pendingRow).toContainText("Invitation sent");
    await expect(pendingRow.locator('select[name="role"]')).toHaveValue(
      "viewer",
    );

    // Find the remove button.
    const removeButton = pendingRow.locator(
      `#remove-member-${TEST_USER_IDS.pending1}`,
    );
    await removeButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this team member?",
    );

    // Click Yes.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response
            .url()
            .includes(
              `/dashboard/group/team/${TEST_USER_IDS.pending1}/delete`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert how many matching elements are shown.
    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Pending One" }),
    ).toHaveCount(0);
  });

  test("organizer can update and restore a group team member role", async ({
    organizerGroupPage,
  }) => {
    // Define the seeded team member role that must be restored.
    const seededRole = "viewer";
    const updatedRole = "events-manager";
    const teamTabPath = "/dashboard/group?tab=team";

    // Start from the seeded viewer role before changing permissions.
    await ensureGroupViewerRole(organizerGroupPage, seededRole);

    // Restore the changed permissions after this check.
    try {
      await navigateToPath(organizerGroupPage, teamTabPath);

      // Find the dashboard content.
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      const currentRoleSelect = dashboardContent
        .locator("tr", { hasText: "E2E Group Viewer One" })
        .locator('select[name="role"]');

      // Verify organizer can update and restore a group team member role.
      await expect(
        dashboardContent.getByText("Group Team", { exact: true }),
      ).toBeVisible();
      await expect(currentRoleSelect).toHaveValue(seededRole);

      // Submit and wait for the server response.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/group/team/") &&
            response.url().endsWith("/role") &&
            response.ok(),
        ),
        currentRoleSelect.selectOption(updatedRole),
      ]);

      // Assert the field value was updated.
      await expect(currentRoleSelect).toHaveValue(updatedRole);
    } finally {
      await ensureGroupViewerRole(organizerGroupPage, seededRole);
    }
  });
});
