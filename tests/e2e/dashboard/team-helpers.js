import { expect } from "../fixtures.js";
import { navigateToPath, waitForActionResponse } from "../utils.js";

/**
 * Checks that a pending member shows its invitation badge under the role below 2xl
 * and next to the name from 2xl, then restores the viewport the check started from.
 * @param {import("@playwright/test").Page} page - Page showing the team list.
 * @param {import("@playwright/test").Locator} pendingRow - Row of a pending team member.
 */
export const expectPendingBadgePlacement = async (page, pendingRow) => {
  const initialViewport = page.viewportSize();
  const memberBadge = pendingRow.getByRole("cell").nth(0).getByText("Invitation sent");
  const roleBadge = pendingRow.getByRole("cell").nth(2).getByText("Invitation sent");

  // At xl the badge sits under the role so the name keeps its width.
  await page.setViewportSize({ width: 1280, height: 900 });
  await expect(roleBadge).toBeVisible();
  await expect(memberBadge).toBeHidden();

  // At 2xl the badge returns to the name row.
  await page.setViewportSize({ width: 1536, height: 900 });
  await expect(memberBadge).toBeVisible();
  await expect(roleBadge).toBeHidden();

  if (initialViewport) {
    await page.setViewportSize(initialViewport);
  }
};

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
