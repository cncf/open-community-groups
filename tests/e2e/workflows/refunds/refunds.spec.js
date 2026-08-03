import { expect, test } from "../../fixtures.js";

import {
  E2E_PAYMENTS_ENABLED,
  TEST_PAYMENT_EVENT_NAMES,
  navigateToPath,
} from "../../utils.js";

// Find the refund row that belongs to the given attendee name.
const getRefundRow = (dashboardContent, attendeeName) =>
  dashboardContent.locator("tbody tr", {
    hasText: attendeeName,
  });

// Open the refunds dashboard and return its loaded content container.
const openRefundsDashboard = async (
  page,
  path = "/dashboard/group?tab=refunds",
) => {
  await navigateToPath(page, path);

  const dashboardContent = page.locator("#dashboard-content");
  await expect(
    dashboardContent.getByRole("table", { name: "Refunds list" }),
  ).toBeVisible();

  return dashboardContent;
};

// Wait for the refunds list refresh triggered by a review action.
const waitForRefundsResponse = (page) =>
  page.waitForResponse((response) => {
    const requestUrl = new URL(response.url());

    return (
      response.request().method() === "GET" &&
      requestUrl.pathname === "/dashboard/group/refunds" &&
      response.ok()
    );
  });

test.describe("refund rejection workflow", () => {
  test.skip(
    !E2E_PAYMENTS_ENABLED,
    "Payments are disabled in this environment.",
  );

  test("persists a refund rejection and its reason", async ({
    groupsManagerPage,
    organizerGroupPage,
  }) => {
    test.setTimeout(60_000);

    // Open the dedicated pending request without mocking the organizer action.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const pendingRefundRow = getRefundRow(
      dashboardContent,
      "E2E Groups Manager One",
    );
    const actionsMenu = pendingRefundRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    await actionsMenu.getByRole("button", { name: "Reject refund" }).click();
    const rejectDialog = organizerGroupPage.getByRole("dialog", {
      name: "Reject refund request",
    });
    await expect(rejectDialog).toContainText("Duplicate registration");
    await rejectDialog
      .getByLabel("Reason shown to attendee")
      .fill("Duplicate purchase");

    // Reject the request through the real handler and capture its form contract.
    const [rejectResponse] = await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          /\/dashboard\/group\/refunds\/[^/]+\/reject$/u.test(
            new URL(response.url()).pathname,
          ) &&
          response.ok(),
      ),
      waitForRefundsResponse(organizerGroupPage),
      rejectDialog.getByRole("button", { name: "Reject refund" }).click(),
    ]);
    const rejectionData = new URLSearchParams(
      rejectResponse.request().postData(),
    );
    expect(rejectionData.get("review_note")).toBe("Duplicate purchase");
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Refund request rejected.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();

    // Verify the rejected request leaves the refreshed active queue.
    await expect(pendingRefundRow).toHaveCount(0);

    // Verify the attendee sees the persisted rejection and organizer reason.
    await navigateToPath(groupsManagerPage, "/dashboard/user?tab=events");
    const rejectedEventRow = groupsManagerPage.locator(
      "#dashboard-content tbody tr",
      {
        hasText: TEST_PAYMENT_EVENT_NAMES.refunds,
      },
    );
    const refundStatusButton = rejectedEventRow.getByRole("button", {
      name: "Refund rejected",
    });
    const rejectionReason = rejectedEventRow.getByRole("tooltip");
    await expect(rejectedEventRow).toBeVisible();
    await refundStatusButton.focus();
    await expect(rejectionReason).toBeVisible();
    await expect(
      rejectionReason.getByText("Reason", { exact: true }),
    ).toBeVisible();
    await expect(
      rejectionReason.getByText("Duplicate purchase", { exact: true }),
    ).toBeVisible();
  });
});
