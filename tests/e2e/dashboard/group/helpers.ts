import type { Page } from "@playwright/test";

import { expect } from "../../fixtures";
import { navigateToPath } from "../../utils";

export const ATTENDEE_NOTIFICATION_SUBJECT = "E2E attendee notification";
export const ATTENDEE_NOTIFICATION_BODY =
  "Reminder for all event attendees from the e2e suite.";

export const ensureGroupViewerRole = async (page: Page, role: string) => {
  const teamTabPath = "/dashboard/group?tab=team";

  await navigateToPath(page, teamTabPath);

  const dashboardContent = page.locator("#dashboard-content");
  const viewerRow = dashboardContent.locator("tr", {
    hasText: "E2E Group Viewer One",
  });
  const currentRoleSelect = viewerRow.locator('select[name="role"]');

  await expect(viewerRow).toBeVisible();

  if ((await currentRoleSelect.inputValue()) === role) {
    return;
  }

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "PUT" &&
        response.url().includes("/dashboard/group/team/") &&
        response.url().endsWith("/role") &&
        response.ok(),
    ),
    currentRoleSelect.selectOption(role),
  ]);

  await expect(currentRoleSelect).toHaveValue(role);
};
