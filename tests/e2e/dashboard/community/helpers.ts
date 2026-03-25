import { expect } from "../../fixtures";
import { navigateToPath } from "../../utils";

export const taxonomyCases = [
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

export const ensureCommunityGroupsManagerRole = async (
  role: string,
  page: Parameters<typeof navigateToPath>[0],
) => {
  const teamTabPath = "/dashboard/community?tab=team";

  await navigateToPath(page, teamTabPath);

  const dashboardContent = page.locator("#dashboard-content");
  const groupsManagerRow = dashboardContent.locator("tr", {
    hasText: "E2E Groups Manager One",
  });
  const currentRoleSelect = groupsManagerRow.locator('select[name="role"]');

  await expect(groupsManagerRow).toBeVisible();

  if ((await currentRoleSelect.inputValue()) === role) {
    return;
  }

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "PUT" &&
        response.url().includes("/dashboard/community/team/") &&
        response.url().endsWith("/role") &&
        response.ok(),
    ),
    currentRoleSelect.selectOption(role),
  ]);

  await expect(currentRoleSelect).toHaveValue(role);
};
