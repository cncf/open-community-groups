import { expect, test } from "../../../fixtures.js";

import { E2E_PAYMENTS_ENABLED, TEST_PAYMENT_EVENT_IDS, navigateToPath } from "../../../utils.js";

const getRefundRow = (dashboardContent, attendeeName) =>
  dashboardContent.locator("tbody tr", {
    hasText: attendeeName,
  });

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

  test("shows every operational refund state across dashboard views", async ({
    organizerGroupPage,
  }) => {
    // Open all refunds for the seeded review event.
    const dashboardContent = await openRefundsDashboard(
      organizerGroupPage,
      `/dashboard/group?tab=refunds&view=all&event_id=${TEST_PAYMENT_EVENT_IDS.refunds}`,
    );
    await expect(dashboardContent.getByLabel("Event", { exact: true })).toHaveValue(
      TEST_PAYMENT_EVENT_IDS.refunds,
    );

    // Verify each durable workflow state has its user-facing status.
    const expectedRefundStates = [
      ["E2E Admin One", "Refunded"],
      ["E2E Community Viewer One", "Recovery required"],
      ["E2E Events Manager One", "Needs retry"],
      ["E2E Group Viewer One", "Queued"],
      ["E2E Groups Manager One", "Needs review"],
      ["E2E Member One", "Needs review"],
      ["E2E Member Two", "Recovery required"],
      ["E2E Organizer Two", "Processing"],
      ["E2E Pending One", "Rejected"],
    ];

    for (const [attendeeName, status] of expectedRefundStates) {
      const refundRow = getRefundRow(dashboardContent, attendeeName);
      await expect(refundRow).toBeVisible();
      await expect(refundRow).toContainText(status);
    }

    // Switch to completed work and verify active rows are excluded.
    const refundStatus = dashboardContent.getByLabel("Refund status");
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      refundStatus.selectOption("completed"),
    ]);
    await expect(getRefundRow(dashboardContent, "E2E Admin One")).toContainText("Refunded");
    await expect(getRefundRow(dashboardContent, "E2E Pending One")).toContainText("Rejected");
    await expect(getRefundRow(dashboardContent, "E2E Member One")).toHaveCount(0);
  });

  test("viewer sees refund history without organizer actions", async ({ groupViewerPage }) => {
    // Open attention-required refunds as a read-only group viewer.
    const dashboardContent = await openRefundsDashboard(
      groupViewerPage,
      "/dashboard/group?tab=refunds&view=attention",
    );
    const pendingRefundRow = getRefundRow(dashboardContent, "E2E Member One");
    const recoveryRow = getRefundRow(dashboardContent, "E2E Community Viewer One");
    await expect(pendingRefundRow).toBeVisible();
    await expect(recoveryRow).toBeVisible();

    // Verify review actions are absent and recovery explains its permission requirement.
    await expect(pendingRefundRow.locator("[data-actions-menu]")).toHaveCount(0);
    await recoveryRow.locator("[data-actions-menu] summary").click();
    const recoveryAction = recoveryRow.getByRole("button", {
      name: "Complete recovery",
    });
    await expect(recoveryAction).toBeDisabled();
    await expect(recoveryAction).toHaveAttribute("aria-disabled", "true");
    await expect(recoveryAction.locator("xpath=..")).toHaveAttribute(
      "title",
      "Events write access is required to complete refund recovery.",
    );
    await expect(dashboardContent.locator("[data-refund-approve-open]")).toHaveCount(0);
    await expect(dashboardContent.locator("[data-refund-reject-open]")).toHaveCount(0);
  });

  test("preserves refund view and filter history with keyboard focus", async ({
    organizerGroupPage,
  }) => {
    // Open the refunds dashboard and switch to attention-required work.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const refundStatus = dashboardContent.getByLabel("Refund status");
    await refundStatus.focus();
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      refundStatus.selectOption("attention"),
    ]);

    // Verify the selected view is durable and retains focus after the swap.
    await expect
      .poll(() => new URL(organizerGroupPage.url()).searchParams.get("view"))
      .toBe("attention");
    await expect(dashboardContent.getByLabel("Refund status")).toBeFocused();

    // Apply a search and verify its URL and focus contract.
    const refundSearch = dashboardContent.getByRole("textbox", {
      name: "Search refunds",
    });
    await refundSearch.fill("E2E Member");
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      refundSearch.press("Enter"),
    ]);
    await expect
      .poll(() => new URL(organizerGroupPage.url()).searchParams.get("ts_query"))
      .toBe("E2E Member");
    await expect(refundSearch).toBeFocused();

    // Clear filters and move focus to the replacement search control.
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      dashboardContent.getByRole("button", { name: "Clear refund search" }).click(),
    ]);
    await expect
      .poll(() => new URL(organizerGroupPage.url()).searchParams.has("ts_query"))
      .toBe(false);
    await expect(
      dashboardContent.getByRole("textbox", { name: "Search refunds" }),
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

    // Open the approval modal and add an optional review note.
    await actionsMenu.getByRole("button", { name: "Approve refund" }).click();
    const approveDialog = organizerGroupPage.getByRole("dialog", {
      name: "Approve refund request",
    });
    const reviewNote = approveDialog.getByLabel("Review note (optional)");
    await expect(reviewNote).toBeFocused();
    await reviewNote.fill("Approved by organizer");

    // Return the normal refresh event after a successful approval request.
    await organizerGroupPage.route("**/dashboard/group/refunds/*/approve", (route) =>
      route.fulfill({
        status: 204,
        headers: { "HX-Trigger": "refresh-group-refunds" },
      }),
    );
    const [approveResponse] = await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          /\/dashboard\/group\/refunds\/[^/]+\/approve$/u.test(new URL(response.url()).pathname),
      ),
      waitForRefundsResponse(organizerGroupPage),
      approveDialog.getByRole("button", { name: "Approve refund" }).click(),
    ]);
    const approvalData = new URLSearchParams(approveResponse.request().postData());
    expect(approvalData.get("review_note")).toBe("Approved by organizer");

    // Verify the action feedback remains visible after the queue refreshes.
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Refund queued.");
    await organizerGroupPage.locator(".swal2-confirm").click();
    await expect(dashboardContent.getByRole("table", { name: "Refunds list" })).toBeVisible();
  });

  test("prevents duplicate refund approval submissions", async ({ organizerGroupPage }) => {
    // Hold the approval response open so duplicate-submit state remains observable.
    let releaseApprovalResponse;
    const approvalResponseGate = new Promise((resolve) => {
      releaseApprovalResponse = resolve;
    });
    let approvalRequestCount = 0;
    await organizerGroupPage.route("**/dashboard/group/refunds/*/approve", async (route) => {
      approvalRequestCount += 1;
      await approvalResponseGate;
      await route.fulfill({
        status: 204,
        headers: { "HX-Trigger": "refresh-group-refunds" },
      });
    });

    // Open the seeded pending refund approval.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const pendingRefundRow = getRefundRow(dashboardContent, "E2E Member One");
    const actionsMenu = pendingRefundRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    await actionsMenu.getByRole("button", { name: "Approve refund" }).click();
    const approveDialog = organizerGroupPage.getByRole("dialog", {
      name: "Approve refund request",
    });
    const submitButton = approveDialog.getByRole("button", {
      name: "Approve refund",
    });

    // Submit once and verify the pending control rejects a second activation.
    const approvalResponse = organizerGroupPage.waitForResponse(
      (response) =>
        response.request().method() === "PUT" &&
        /\/dashboard\/group\/refunds\/[^/]+\/approve$/u.test(new URL(response.url()).pathname),
    );
    const refundsResponse = waitForRefundsResponse(organizerGroupPage);
    await submitButton.click();
    await expect.poll(() => approvalRequestCount).toBe(1);
    await expect(submitButton).toBeDisabled();
    await submitButton.evaluate((button) => button.click());
    expect(approvalRequestCount).toBe(1);

    // Release the response and verify the normal success refresh completes.
    releaseApprovalResponse();
    await Promise.all([approvalResponse, refundsResponse]);
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Refund queued.");
    await organizerGroupPage.locator(".swal2-confirm").click();
  });

  test("submits and preserves an optional refund rejection note", async ({ organizerGroupPage }) => {
    // Open the pending refund rejection without changing its seeded state.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const pendingRefundRow = dashboardContent.locator("tr", {
      hasText: "E2E Member One",
    });
    const actionsMenu = pendingRefundRow.locator("[data-actions-menu]");
    const actionsSummary = actionsMenu.locator("summary");
    await actionsSummary.click();
    await actionsMenu.getByRole("button", { name: "Reject refund" }).click();

    // Enter the review note after focus moves into the rejection dialog.
    const rejectDialog = organizerGroupPage.getByRole("dialog", {
      name: "Reject refund request",
    });
    const reviewNote = rejectDialog.getByLabel("Review note (optional)");
    await expect(rejectDialog).toBeVisible();
    await expect(reviewNote).toBeFocused();
    await reviewNote.fill("Duplicate purchase");

    // Fail the request and verify the submitted contract without mutating the fixture.
    await organizerGroupPage.route("**/dashboard/group/refunds/*/reject", (route) =>
      route.fulfill({ status: 422 }),
    );
    const [rejectResponse] = await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          /\/dashboard\/group\/refunds\/[^/]+\/reject$/u.test(new URL(response.url()).pathname),
      ),
      rejectDialog.getByRole("button", { name: "Reject refund" }).click(),
    ]);
    const rejectionData = new URLSearchParams(rejectResponse.request().postData());
    expect(rejectionData.get("review_note")).toBe("Duplicate purchase");

    // Preserve the note after failure and restore focus when the modal closes.
    await expect(rejectDialog).toBeVisible();
    await expect(reviewNote).toHaveValue("Duplicate purchase");
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Something went wrong rejecting this refund request.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();
    await rejectDialog.getByRole("button", { name: "Cancel" }).click();
    await expect(rejectDialog).toBeHidden();
    await expect(actionsSummary).toBeFocused();
  });

  test("preserves recovery evidence on failure and restores menu focus", async ({
    organizerGroupPage,
  }) => {
    // Open the recovery-required refund action.
    const dashboardContent = await openRefundsDashboard(
      organizerGroupPage,
      "/dashboard/group?tab=refunds&view=attention",
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
      "Something went wrong completing this refund recovery.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();
    await recoveryDialog.getByRole("button", { name: "Cancel" }).click();
    await expect(recoveryDialog).toBeHidden();
    await expect(actionsSummary).toBeFocused();
  });

  test("retries an exhausted refund from the attention queue", async ({ organizerGroupPage }) => {
    // Open the seeded exhausted provider refund.
    const dashboardContent = await openRefundsDashboard(
      organizerGroupPage,
      "/dashboard/group?tab=refunds&view=attention",
    );
    const retryableRefundRow = getRefundRow(dashboardContent, "E2E Events Manager One");
    const actionsMenu = retryableRefundRow.locator("[data-actions-menu]");
    await expect(retryableRefundRow).toContainText("Needs retry");
    await actionsMenu.locator("summary").click();

    // Retry the durable refund and wait for the attention queue refresh.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/group/refunds/") &&
          response.url().endsWith("/retry") &&
          response.ok(),
      ),
      waitForRefundsResponse(organizerGroupPage),
      actionsMenu.getByRole("button", { name: "Retry refund" }).click(),
    ]);
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Refund requeued.");
    await organizerGroupPage.locator(".swal2-confirm").click();
    await expect(retryableRefundRow).toHaveCount(0);

    // Verify the refund returns to active provider work without retry controls.
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      dashboardContent.getByLabel("Refund status").selectOption("active"),
    ]);
    const requeuedRefundRow = getRefundRow(dashboardContent, "E2E Events Manager One");
    await expect(requeuedRefundRow).toContainText(/Queued|Processing/u);
    await expect(requeuedRefundRow).not.toContainText("Needs retry");
  });

  test("persists a refund rejection and its review note", async ({ organizerGroupPage }) => {
    // Open the dedicated pending request without mocking the organizer action.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const pendingRefundRow = getRefundRow(dashboardContent, "E2E Groups Manager One");
    const actionsMenu = pendingRefundRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    await actionsMenu.getByRole("button", { name: "Reject refund" }).click();
    const rejectDialog = organizerGroupPage.getByRole("dialog", {
      name: "Reject refund request",
    });
    await rejectDialog.getByLabel("Review note (optional)").fill("Duplicate purchase");

    // Reject the request through the real handler and capture its form contract.
    const [rejectResponse] = await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          /\/dashboard\/group\/refunds\/[^/]+\/reject$/u.test(new URL(response.url()).pathname) &&
          response.ok(),
      ),
      waitForRefundsResponse(organizerGroupPage),
      rejectDialog.getByRole("button", { name: "Reject refund" }).click(),
    ]);
    const rejectionData = new URLSearchParams(rejectResponse.request().postData());
    expect(rejectionData.get("review_note")).toBe("Duplicate purchase");
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Refund request rejected.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();

    // Reopen completed history and verify the persisted reason and review outcome.
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      dashboardContent.getByLabel("Refund status").selectOption("completed"),
    ]);
    const rejectedRefundRow = getRefundRow(dashboardContent, "E2E Groups Manager One");
    await expect(rejectedRefundRow).toContainText("Rejected");
    await expect(rejectedRefundRow).toContainText("Reason: Duplicate registration");
    await expect(rejectedRefundRow).toContainText("Review: Duplicate purchase");
  });

  test("completes manual recovery through the real refund handler", async ({
    organizerGroupPage,
  }) => {
    // Open the dedicated terminal provider failure.
    const dashboardContent = await openRefundsDashboard(
      organizerGroupPage,
      "/dashboard/group?tab=refunds&view=attention",
    );
    const recoveryRow = getRefundRow(dashboardContent, "E2E Community Viewer One");
    const actionsMenu = recoveryRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    await actionsMenu.getByRole("button", { name: "Complete recovery" }).click();
    const recoveryDialog = organizerGroupPage.getByRole("dialog", {
      name: "Complete refund recovery",
    });
    const recoveryReference = recoveryDialog.getByLabel("External refund reference");
    const recoveryNote = recoveryDialog.getByLabel("Evidence reviewed");

    // Verify required evidence blocks an empty submission.
    await recoveryDialog.getByRole("button", { name: "Complete recovery" }).click();
    await expect(recoveryReference).toBeFocused();

    // Complete recovery and assert the submitted evidence contract.
    await recoveryReference.fill("external-refund-e2e");
    await recoveryNote.fill("Provider receipt and attendee confirmation reviewed.");
    const [recoveryResponse] = await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          new URL(response.url()).pathname === "/dashboard/group/refunds/recovery" &&
          response.ok(),
      ),
      waitForRefundsResponse(organizerGroupPage),
      recoveryDialog.getByRole("button", { name: "Complete recovery" }).click(),
    ]);
    const recoveryData = new URLSearchParams(recoveryResponse.request().postData());
    expect(recoveryData.get("event_purchase_id")).toBe("59555555-5555-5555-5555-555555555530");
    expect(recoveryData.get("recovery_reference")).toBe("external-refund-e2e");
    expect(recoveryData.get("recovery_note")).toBe(
      "Provider receipt and attendee confirmation reviewed.",
    );
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Refund recovery completed.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();
    await expect(recoveryRow).toHaveCount(0);

    // Verify the recovered purchase is retained in completed history.
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      dashboardContent.getByLabel("Refund status").selectOption("completed"),
    ]);
    const recoveredRefundRow = getRefundRow(dashboardContent, "E2E Community Viewer One");
    await expect(recoveredRefundRow).toContainText("Refunded");
    await expect(recoveredRefundRow.locator("[data-actions-menu]")).toHaveCount(0);
  });
});
