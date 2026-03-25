import { expect, test } from "../../fixtures";

import { TEST_USER_IDS, navigateToPath } from "../../utils";

import { ensureGroupViewerRole } from "./helpers";

test.describe("group dashboard team view", () => {
  test("group team page shows seeded roles and last-admin protection", async ({
    organizerGroupPage,
  }) => {
    await ensureGroupViewerRole(organizerGroupPage, "viewer");
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Group Team", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add member" }),
    ).toBeEnabled();

    const adminRow = dashboardContent.locator("tr", {
      hasText: "E2E Organizer One",
    });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.locator("select")).toHaveAttribute(
      "title",
      "At least one accepted admin is required.",
    );

    const eventsManagerRow = dashboardContent.locator("tr", {
      hasText: "E2E Events Manager One",
    });
    await expect(eventsManagerRow.locator('select[name="role"]')).toHaveValue(
      "events-manager",
    );

    const viewerRow = dashboardContent.locator("tr", {
      hasText: "E2E Group Viewer One",
    });
    await expect(viewerRow.locator('select[name="role"]')).toHaveValue("viewer");
  });

  test("organizer can invite and remove a pending group team member", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Group Team", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add member" }).click();

    const addMemberForm = organizerGroupPage.locator("#team-add-form");
    await expect(addMemberForm).toBeVisible();

    const searchInput = addMemberForm.locator("#search-input");
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/group/users/search?q=e2e-pending-1") &&
          response.ok(),
      ),
      searchInput.fill("e2e-pending-1"),
    ]);

    await addMemberForm.getByText("E2E Pending One", { exact: true }).click();
    await addMemberForm.locator("#team-add-role").selectOption("viewer");

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/team/add") &&
          response.status() === 201,
      ),
      addMemberForm.locator("#team-add-submit").click(),
    ]);

    const pendingRow = dashboardContent.locator("tr", { hasText: "E2E Pending One" });
    await expect(pendingRow).toBeVisible();
    await expect(pendingRow).toContainText("Invitation sent");
    await expect(pendingRow.locator('select[name="role"]')).toHaveValue("viewer");

    const removeButton = pendingRow.locator(`#remove-member-${TEST_USER_IDS.pending1}`);
    await removeButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this team member?",
    );

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/dashboard/group/team/${TEST_USER_IDS.pending1}/delete`) &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Pending One" }),
    ).toHaveCount(0);
  });

  test("organizer can update and restore a group team member role", async ({
    organizerGroupPage,
  }) => {
    const seededRole = "viewer";
    const updatedRole = "events-manager";
    const teamTabPath = "/dashboard/group?tab=team";

    await ensureGroupViewerRole(organizerGroupPage, seededRole);

    try {
      await navigateToPath(organizerGroupPage, teamTabPath);

      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      const currentRoleSelect = dashboardContent
        .locator("tr", { hasText: "E2E Group Viewer One" })
        .locator('select[name="role"]');

      await expect(
        dashboardContent.getByText("Group Team", { exact: true }),
      ).toBeVisible();
      await expect(currentRoleSelect).toHaveValue(seededRole);

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

      await expect(currentRoleSelect).toHaveValue(updatedRole);
    } finally {
      await ensureGroupViewerRole(organizerGroupPage, seededRole);
    }
  });
});
