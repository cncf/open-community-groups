import { expect } from "../../fixtures.js";
import { navigateToPath, waitForActionResponse } from "../../utils.js";

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
    unusedDeleteId:
      "delete-group-category-22222222-2222-2222-2222-222222222223",
  },
  {
    path: "/dashboard/community?tab=event-categories",
    heading: "Event Categories",
    addButton: "Add Event Category",
    usedDeleteId: "delete-event-category-33333333-3333-3333-3333-333333333331",
    unusedDeleteId:
      "delete-event-category-33333333-3333-3333-3333-333333333333",
  },
];

export const ensureCommunityGroupsManagerRole = async (role, page) => {
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

  await waitForActionResponse(page, () => currentRoleSelect.selectOption(role), {
    method: "PUT",
    urlEndsWith: "/role",
    urlIncludes: "/dashboard/community/team/",
  });

  await expect(currentRoleSelect).toHaveValue(role);
};

/**
 * Runs a community dashboard mutation and waits for its table refresh.
 */
export const waitForCommunityDashboardMutation = async (
  page,
  refreshPath,
  action,
  responseOptions,
) => {
  await Promise.all([
    page.waitForResponse((response) => {
      const requestUrl = new URL(response.url());

      return (
        response.request().method() === "GET" &&
        requestUrl.pathname === refreshPath &&
        response.ok()
      );
    }),
    waitForActionResponse(page, action, responseOptions),
  ]);
};
