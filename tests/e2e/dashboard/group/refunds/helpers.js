import { expect } from "../../../fixtures.js";
import { navigateToPath, waitForResponseMatching } from "../../../utils.js";

/** Response matcher for the group refunds dashboard refresh. */
export const REFUNDS_REFRESH_RESPONSE = {
  method: "GET",
  pathname: "/dashboard/group/refunds",
  status: 200,
};

/** Returns the refunds table row matching the attendee name. */
export const getRefundRow = (dashboardContent, attendeeName) =>
  dashboardContent
    .getByRole("table", { name: "Refunds list" })
    .locator("tbody tr", { hasText: attendeeName });

/** Opens the group refunds dashboard path and returns the loaded content region. */
export const openRefundsDashboard = async (page, path = "/dashboard/group?tab=refunds") => {
  await navigateToPath(page, path);

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByRole("table", { name: "Refunds list" })).toBeVisible();

  return dashboardContent;
};

/**
 * Arms a wait for the next refunds dashboard refresh. Use it when the refresh must be armed
 * before steps that cannot run inside one action.
 * @param {import("@playwright/test").Page} page - Page showing the refunds dashboard.
 * @returns {Promise<import("@playwright/test").Response>} Refresh response.
 */
export const waitForRefundsRefresh = (page) => waitForResponseMatching(page, REFUNDS_REFRESH_RESPONSE);
