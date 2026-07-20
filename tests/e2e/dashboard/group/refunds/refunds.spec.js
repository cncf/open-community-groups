import { expect, test } from "../../../fixtures.js";

import { E2E_PAYMENTS_ENABLED, navigateToPath } from "../../../utils.js";

const openRefundsDashboard = async (page, path = "/dashboard/group?tab=refunds") => {
  await navigateToPath(page, path);

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByRole("table", { name: "Refunds list" })).toBeVisible();

  return dashboardContent;
};

const waitForRefundsResponse = (page) =>
  page.waitForResponse((response) => {
    const requestUrl = new URL(response.url());

    return (
      response.request().method() === "GET" &&
      requestUrl.pathname === "/dashboard/group/refunds" &&
      response.ok()
    );
  });

test.describe("group dashboard refunds", () => {
  test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

  test("preserves refund view and filter history with keyboard focus", async ({
    organizerGroupPage,
  }) => {
    // Open the refunds dashboard and switch to attention-required work.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const needsAttentionLink = dashboardContent.getByRole("link", {
      name: "Needs attention",
    });
    await Promise.all([waitForRefundsResponse(organizerGroupPage), needsAttentionLink.click()]);

    // Verify the selected view is durable and retains focus after the swap.
    await expect
      .poll(() => new URL(organizerGroupPage.url()).searchParams.get("view"))
      .toBe("needs-attention");
    await expect(
      dashboardContent.getByRole("link", { name: "Needs attention" }),
    ).toBeFocused();

    // Apply a search and verify its URL and focus contract.
    const refundSearch = dashboardContent.getByRole("searchbox", {
      name: "Search refunds",
    });
    await refundSearch.fill("E2E Member");
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      dashboardContent.getByRole("button", { name: "Apply" }).click(),
    ]);
    await expect
      .poll(() => new URL(organizerGroupPage.url()).searchParams.get("ts_query"))
      .toBe("E2E Member");
    await expect(dashboardContent.getByRole("button", { name: "Apply" })).toBeFocused();

    // Clear filters and move focus to the replacement search control.
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      dashboardContent.getByRole("link", { name: "Clear" }).click(),
    ]);
    await expect
      .poll(() => new URL(organizerGroupPage.url()).searchParams.has("ts_query"))
      .toBe(false);
    await expect(
      dashboardContent.getByRole("searchbox", { name: "Search refunds" }),
    ).toBeFocused();
  });

  test("submits refund actions and refreshes the active queue", async ({
    organizerGroupPage,
  }) => {
    // Open the pending refund action without changing its seeded state.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const pendingRefundRow = dashboardContent.locator("tr", {
      hasText: "E2E Member One",
    });
    const actionsMenu = pendingRefundRow.locator("[data-actions-menu]");
    await expect(pendingRefundRow).toBeVisible();
    await actionsMenu.locator("summary").click();

    // Return the normal refresh event after a successful approval request.
    await organizerGroupPage.route("**/dashboard/group/refunds/*/approve", (route) =>
      route.fulfill({
        status: 204,
        headers: { "HX-Trigger": "refresh-group-refunds" },
      }),
    );
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          /\/dashboard\/group\/refunds\/[^/]+\/approve$/u.test(new URL(response.url()).pathname),
      ),
      waitForRefundsResponse(organizerGroupPage),
      actionsMenu.getByRole("button", { name: "Approve refund" }).click(),
    ]);

    // Verify the action feedback remains visible after the queue refreshes.
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Refund queued.");
    await organizerGroupPage.locator(".swal2-confirm").click();
    await expect(dashboardContent.getByRole("table", { name: "Refunds list" })).toBeVisible();
  });

  test("preserves recovery evidence on failure and restores menu focus", async ({
    organizerGroupPage,
  }) => {
    // Open the recovery-required refund action.
    const dashboardContent = await openRefundsDashboard(
      organizerGroupPage,
      "/dashboard/group?tab=refunds&view=needs-attention",
    );
    const recoveryRow = dashboardContent
      .locator("tr", {
        hasText: "Recovery required",
      })
      .first();
    const actionsMenu = recoveryRow.locator("[data-actions-menu]");
    const actionsSummary = actionsMenu.locator("summary");
    await expect(recoveryRow).toBeVisible();
    await actionsSummary.click();
    await actionsMenu.getByRole("button", { name: "Complete recovery" }).click();

    // Fill the recovery evidence after focus enters the dialog.
    const recoveryDialog = organizerGroupPage.getByRole("dialog", {
      name: "Complete refund recovery",
    });
    await expect(recoveryDialog).toBeVisible();
    await expect(recoveryDialog.getByRole("button", { name: "Close modal" })).toBeFocused();
    await recoveryDialog.getByLabel("External refund reference").fill("external-refund-123");
    await recoveryDialog.getByLabel("Evidence reviewed").fill("Provider receipt verified.");

    // Reject the request without mutating the seeded refund state.
    await organizerGroupPage.route("**/dashboard/group/refunds/recovery", (route) =>
      route.fulfill({ status: 422 }),
    );
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          new URL(response.url()).pathname === "/dashboard/group/refunds/recovery",
      ),
      recoveryDialog.getByRole("button", { name: "Complete recovery" }).click(),
    ]);

    // Verify recoverable work remains available before closing the dialog.
    await expect(recoveryDialog).toBeVisible();
    await expect(recoveryDialog.getByLabel("External refund reference")).toHaveValue(
      "external-refund-123",
    );
    await expect(recoveryDialog.getByLabel("Evidence reviewed")).toHaveValue(
      "Provider receipt verified.",
    );
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Something went wrong completing this refund recovery. Please try again later.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();
    await recoveryDialog.getByRole("button", { name: "Cancel" }).click();
    await expect(recoveryDialog).toBeHidden();
    await expect(actionsSummary).toBeFocused();
  });
});
