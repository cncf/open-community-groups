import { expect } from "../fixtures.js";
import { navigateToPath, waitForActionResponse } from "../utils.js";

/**
 * Invites a user through the dashboard team "Add member" form.
 * Returns the pending member row once the invitation is listed.
 */
export const inviteTeamMember = async (page, { fullName, role, scope, username }) => {
  await navigateToPath(page, `/dashboard/${scope}?tab=team`);

  // Open the add member form from the team tab.
  const dashboardContent = page.locator("#dashboard-content");
  await dashboardContent.getByRole("button", { name: "Add member" }).click();
  const addMemberForm = page.locator("#team-add-form");
  await expect(addMemberForm).toBeVisible();

  // Search the invitee, pick the matching suggestion and choose the role.
  await waitForActionResponse(page, () => addMemberForm.locator("#search-input").fill(username), {
    method: "GET",
    urlIncludes: `/dashboard/${scope}/users/search?q=${username}`,
  });
  await addMemberForm.getByText(fullName, { exact: true }).click();
  await addMemberForm.locator("#team-add-role").selectOption(role);

  // Submit the invitation and wait for it to be created.
  await waitForActionResponse(page, () => addMemberForm.locator("#team-add-submit").click(), {
    method: "POST",
    status: 201,
    urlIncludes: `/dashboard/${scope}/team/add`,
  });

  // Verify the invitee shows up as a pending team member.
  const pendingRow = dashboardContent.locator("tr", { hasText: fullName });
  await expect(pendingRow).toContainText("Invitation sent");

  return pendingRow;
};
