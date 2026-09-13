import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import {
  deleteNotifications,
  expectNewNotifications,
  snapshotNotifications,
} from "../../../notifications.js";
import {
  cleanupOwnedPaymentPurchase,
  setupExhaustedRefundGraph,
  setupExternalRefundRequestGraph,
  setupRecoverableRefundGraph,
} from "../../../data-graphs/payments.js";
import {
  TEST_FINANCIAL_WORK_JOB_IDS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
} from "../../../seed.js";
import { expectCurrentPaginationNavigation, navigateToPath, waitForActionResponse } from "../../../utils.js";
import { getVisibleStatusBadge, openAttendeesTab } from "../events/attendees-helpers.js";

const REFUND_APPROVAL_USER_ID = "77777777-7777-7777-7777-777777777702";

const REFUND_EXHAUSTED_USER_ID = "77777777-7777-7777-7777-777777777714";

const REFUND_RECOVERY_USER_ID = "77777777-7777-7777-7777-777777777715";

test.describe("group dashboard refunds", () => {
  test("organizer can move between refund result pages", async ({ organizerGroupPage }) => {
    // Wait for the refunds table to load before paginating its rows.
    await openRefundsDashboard(
      organizerGroupPage,
      `/dashboard/group?tab=refunds&view=all&event_id=${TEST_PAYMENT_EVENT_IDS.refunds}&limit=1&offset=0`,
    );

    // Paginate the dedicated seeded refund rows with one result per page.
    await expectCurrentPaginationNavigation(organizerGroupPage, "#dashboard-content tbody tr");
  });

  test("shows every operational refund state across dashboard views", async ({ organizerGroupPage }) => {
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
      ["E2E Community Viewer One", /Recovery required|Refunded/u],
      ["E2E Events Manager One", /Needs retry|Queued|Processing/u],
      ["E2E Group Viewer One", "Queued"],
      ["E2E Groups Manager One", "Needs review"],
      ["E2E Member One", "Needs review"],
      ["E2E Member Two", "Recovery required"],
      ["E2E Organizer Two", "Processing"],
      ["E2E Pending One", "Rejected"],
    ];

    // Verify each seeded refund row shows its expected state.
    for (const [attendeeName, status] of expectedRefundStates) {
      const refundRow = getRefundRow(dashboardContent, attendeeName);
      await expect(refundRow).toBeVisible();
      await expect(refundRow).toContainText(status);
    }

    // Provider-active refunds are visible but expose no retry or review action.
    const processingRefundRow = getRefundRow(dashboardContent, "E2E Organizer Two");
    await expect(processingRefundRow).toContainText("Processing");
    await expect(processingRefundRow.locator("[data-actions-menu]")).toHaveCount(0);

    // Switch to completed work and verify active rows are excluded.
    const refundStatus = dashboardContent.getByLabel("Refund status");
    await Promise.all([waitForRefundsResponse(organizerGroupPage), refundStatus.selectOption("completed")]);
    await expect(getRefundRow(dashboardContent, "E2E Admin One")).toContainText("Refunded");
    const rejectedRefundRow = getRefundRow(dashboardContent, "E2E Pending One");
    await expect(rejectedRefundRow).toContainText("Rejected");
    const refundDetailsButton = rejectedRefundRow.locator('button[aria-describedby^="refund-details-"]');
    const refundDetails = rejectedRefundRow.getByRole("tooltip");
    await refundDetailsButton.focus();
    await expect(refundDetails).toBeVisible();
    await expect(refundDetails.getByText("Reason", { exact: true })).toBeVisible();
    await expect(refundDetails.getByText("Need a different date", { exact: true })).toBeVisible();
    await expect(refundDetails.getByText("Review", { exact: true })).toBeVisible();
    await expect(
      refundDetails.getByText("The request falls outside the refund policy window.", {
        exact: true,
      }),
    ).toBeVisible();
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
    const recoveryTooltipTrigger = recoveryAction.locator("xpath=..");
    const recoveryTooltip = recoveryTooltipTrigger.getByRole("tooltip");
    await recoveryTooltipTrigger.focus();
    await expect(recoveryTooltip).toBeVisible();
    await expect(
      recoveryTooltip.getByText("Events write access is required to complete refund recovery."),
    ).toBeVisible();
    await expect(recoveryTooltip.getByText("Recovery unavailable")).toBeVisible();
    await expect(dashboardContent.locator("[data-refund-approve-open]")).toHaveCount(0);
    await expect(dashboardContent.locator("[data-refund-reject-open]")).toHaveCount(0);
  });

  test("shows exhausted financial work without calling the payment provider", async ({
    groupViewerPage,
    organizerGroupPage,
  }) => {
    // Open every attention item so both deterministic recovery fixtures are shown.
    const dashboardContent = await openRefundsDashboard(
      organizerGroupPage,
      "/dashboard/group?tab=refunds&view=attention&limit=20",
    );
    const recoverySection = dashboardContent.getByRole("table", {
      name: "Financial work needing attention",
    });
    const applicationFeeWork = recoverySection.locator(
      'tbody tr[data-financial-work-kind="event-purchase-application-fee-adjustment"]',
    );
    const creditNoteWork = recoverySection.locator(
      'tbody tr[data-financial-work-kind="event-purchase-credit-note"]',
    );

    // Verify the durable credit-note fixture and its retry details popover.
    await expect(creditNoteWork).toContainText("E2E Events Manager One");
    await expect(creditNoteWork).toContainText(/(?:US)?\$50\.00/u);
    const creditNoteFailureButton = creditNoteWork.getByRole("button", {
      name: "View last failure for Credit note",
    });
    await expect(creditNoteFailureButton).toHaveText("Needs retry");
    await creditNoteFailureButton.focus();
    const creditNoteFailureTooltip = creditNoteWork.getByRole("tooltip");
    await expect(creditNoteFailureTooltip).toBeVisible();
    await expect(creditNoteFailureTooltip).toContainText("Credit note attempts exhausted (10 attempts)");

    // Verify the application-fee fixture when it is available.
    if ((await applicationFeeWork.count()) > 0) {
      await expect(applicationFeeWork).toContainText("E2E Organizer Two");
      await expect(applicationFeeWork).toContainText(/(?:US)?\$5\.00/u);
      await expect(applicationFeeWork).toContainText("Application fee refund attempts exhausted");
    }

    // Verify the retry request contract through an intercepted application route.
    const creditNoteRetryPath = `/dashboard/group/payment-jobs/${TEST_FINANCIAL_WORK_JOB_IDS.creditNote}/retry`;
    await organizerGroupPage.route(`**${creditNoteRetryPath}`, (route) => route.fulfill({ status: 422 }));
    const creditNoteActionsMenu = creditNoteWork.locator("[data-actions-menu]");
    await creditNoteActionsMenu.locator("summary").click();
    const [retryResponse] = await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" && new URL(response.url()).pathname === creditNoteRetryPath,
      ),
      creditNoteActionsMenu.getByRole("button", { name: "Retry operation" }).click(),
    ]);
    expect(retryResponse.status()).toBe(422);
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Something went wrong requeueing this financial work.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();

    // Verify manual recovery collects all evidence without submitting it.
    const manualRecoveryWork = (await applicationFeeWork.count()) > 0 ? applicationFeeWork : creditNoteWork;
    const expectedRecoveryJobId =
      manualRecoveryWork === applicationFeeWork
        ? TEST_FINANCIAL_WORK_JOB_IDS.applicationFeeAdjustment
        : TEST_FINANCIAL_WORK_JOB_IDS.creditNote;
    const manualRecoveryActionsMenu = manualRecoveryWork.locator("[data-actions-menu]");
    if ((await manualRecoveryActionsMenu.getAttribute("open")) === null) {
      await manualRecoveryActionsMenu.locator("summary").click();
    }
    await manualRecoveryActionsMenu.getByText("Complete outside OCG", { exact: true }).click();
    const recoveryForm = dashboardContent.locator('form[hx-put="/dashboard/group/payment-jobs/recovery"]');
    await expect(recoveryForm.locator('input[name="payment_job_id"]')).toHaveValue(expectedRecoveryJobId);
    await expect(recoveryForm.locator('input[name="provider_object_id"]')).toHaveAttribute("required", "");
    await expect(recoveryForm.locator('input[name="recovery_reference"]')).toHaveAttribute("required", "");
    await expect(recoveryForm.locator('textarea[name="recovery_note"]')).toHaveAttribute("required", "");

    // Read-only viewers see the recovery details but cannot mutate them.
    const viewerContent = await openRefundsDashboard(
      groupViewerPage,
      "/dashboard/group?tab=refunds&view=attention&limit=20",
    );
    const viewerRecoverySection = viewerContent.getByRole("table", {
      name: "Financial work needing attention",
    });
    await expect(viewerRecoverySection).toBeVisible();
    await expect(viewerRecoverySection.getByRole("button", { name: "Retry operation" })).toHaveCount(0);
    await expect(viewerRecoverySection.getByText("Complete outside OCG", { exact: true })).toHaveCount(0);
  });

  test("preserves refund view and filter history with keyboard focus", async ({ organizerGroupPage }) => {
    // Open the refunds dashboard and switch to attention-required work.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const refundStatus = dashboardContent.getByLabel("Refund status");
    await refundStatus.focus();
    await Promise.all([waitForRefundsResponse(organizerGroupPage), refundStatus.selectOption("attention")]);

    // Verify the selected view is durable and retains focus after the swap.
    await expect.poll(() => new URL(organizerGroupPage.url()).searchParams.get("view")).toBe("attention");
    await expect(dashboardContent.getByLabel("Refund status")).toBeFocused();

    // Apply a search and verify its URL and focus contract.
    const refundSearch = dashboardContent.getByRole("textbox", {
      name: "Search refunds",
    });
    await refundSearch.fill("E2E Member");
    await Promise.all([waitForRefundsResponse(organizerGroupPage), refundSearch.press("Enter")]);
    await expect
      .poll(() => new URL(organizerGroupPage.url()).searchParams.get("ts_query"))
      .toBe("E2E Member");
    await expect(refundSearch).toBeFocused();

    // Clear filters and move focus to the replacement search control.
    await Promise.all([
      waitForRefundsResponse(organizerGroupPage),
      dashboardContent.getByRole("button", { name: "Clear refund search" }).click(),
    ]);
    await expect.poll(() => new URL(organizerGroupPage.url()).searchParams.has("ts_query")).toBe(false);
    await expect(dashboardContent.getByRole("textbox", { name: "Search refunds" })).toBeFocused();
  });

  test("submits refund actions and refreshes the active queue", async ({ organizerGroupPage }) => {
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
    await expect(reviewNote).toBeVisible();
    await expect(reviewNote).not.toHaveAttribute("required", "");
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

    // Rejecting the same seeded request uses the attendee-visible reason contract and success alert.
    await organizerGroupPage.route("**/dashboard/group/refunds/*/reject", (route) =>
      route.fulfill({
        status: 204,
        headers: { "HX-Trigger": "refresh-group-refunds" },
      }),
    );
    await actionsMenu.locator("summary").click();
    await actionsMenu.getByRole("button", { name: "Reject refund" }).click();
    const rejectDialog = organizerGroupPage.getByRole("dialog", {
      name: "Reject refund request",
    });
    await rejectDialog.getByLabel("Reason shown to attendee").fill("Outside the refund policy window");
    const [rejectResponse] = await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          /\/dashboard\/group\/refunds\/[^/]+\/reject$/u.test(new URL(response.url()).pathname),
      ),
      waitForRefundsResponse(organizerGroupPage),
      rejectDialog.getByRole("button", { name: "Reject refund" }).click(),
    ]);
    const rejectionData = new URLSearchParams(rejectResponse.request().postData());
    expect(rejectionData.get("review_note")).toBe("Outside the refund policy window");
    await expect(rejectDialog).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Refund request rejected.");
    await organizerGroupPage.locator(".swal2-confirm").click();
  });

  test("organizer approval and rejection notify refund request owners", async ({ organizerGroupPage }) => {
    let notificationIds = [];
    const approvedRequest = setupExternalRefundRequestGraph({
      eventId: TEST_PAYMENT_EVENT_IDS.refunds,
      requestedReason: "Approve the external refund",
      userId: REFUND_APPROVAL_USER_ID,
    });

    try {
      // Approve an owned external refund request through the real dashboard handler.
      const dashboardContent = await openRefundsDashboard(
        organizerGroupPage,
        `/dashboard/group?tab=refunds&view=attention&event_id=${TEST_PAYMENT_EVENT_IDS.refunds}`,
      );
      const refundRow = getRefundRow(dashboardContent, approvedRequest.attendeeName);
      await expect(refundRow).toContainText("Needs review");
      const actionsMenu = refundRow.locator("[data-actions-menu]");
      await actionsMenu.locator("summary").click();
      await actionsMenu.getByRole("button", { name: "Approve refund" }).click();
      const dialog = organizerGroupPage.getByRole("dialog", {
        name: "Approve refund request",
      });
      const approvalSnapshot = snapshotNotifications();
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            /\/dashboard\/group\/refunds\/[^/]+\/approve$/u.test(new URL(response.url()).pathname) &&
            response.ok(),
        ),
        waitForRefundsResponse(organizerGroupPage),
        dialog.getByRole("button", { name: "Approve refund" }).click(),
      ]);
      notificationIds = expectNewNotifications(approvalSnapshot, [
        { kind: "event-refund-approved", userIds: [approvedRequest.userId] },
      ]);
      deleteNotifications(notificationIds);
      notificationIds = [];
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Refund recorded");
      await organizerGroupPage.locator(".swal2-confirm").click();
      await expect(refundRow).toHaveCount(0);
    } finally {
      // Remove approval notifications and the approved refund request.
      deleteNotifications(notificationIds);
      cleanupOwnedPaymentPurchase(approvedRequest);
    }

    const rejectedRequest = setupExternalRefundRequestGraph({
      eventId: TEST_PAYMENT_EVENT_IDS.refunds,
      requestedReason: "Reject the external refund",
      userId: REFUND_APPROVAL_USER_ID,
    });

    try {
      // Reject an owned external refund request and notify the purchase owner.
      const dashboardContent = await openRefundsDashboard(
        organizerGroupPage,
        `/dashboard/group?tab=refunds&view=attention&event_id=${TEST_PAYMENT_EVENT_IDS.refunds}`,
      );
      const refundRow = getRefundRow(dashboardContent, rejectedRequest.attendeeName);
      await expect(refundRow).toContainText("Needs review");
      const actionsMenu = refundRow.locator("[data-actions-menu]");
      await actionsMenu.locator("summary").click();
      await actionsMenu.getByRole("button", { name: "Reject refund" }).click();
      const dialog = organizerGroupPage.getByRole("dialog", {
        name: "Reject refund request",
      });
      await dialog.getByLabel("Reason shown to attendee").fill("Outside the organizer policy");
      const rejectionSnapshot = snapshotNotifications();
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            /\/dashboard\/group\/refunds\/[^/]+\/reject$/u.test(new URL(response.url()).pathname) &&
            response.ok(),
        ),
        waitForRefundsResponse(organizerGroupPage),
        dialog.getByRole("button", { name: "Reject refund" }).click(),
      ]);
      notificationIds = expectNewNotifications(rejectionSnapshot, [
        { kind: "event-refund-rejected", userIds: [rejectedRequest.userId] },
      ]);
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Refund request rejected.");
      await organizerGroupPage.locator(".swal2-confirm").click();
      await expect(refundRow).toHaveCount(0);
    } finally {
      // Remove rejection notifications and the rejected refund request.
      deleteNotifications(notificationIds);
      cleanupOwnedPaymentPurchase(rejectedRequest);
    }
  });

  test("preserves approval notes when refund approval fails", async ({ organizerGroupPage }) => {
    // Fail the approval request without mutating the seeded refund state.
    await organizerGroupPage.route("**/dashboard/group/refunds/*/approve", (route) =>
      route.fulfill({ status: 500 }),
    );

    // Open the pending refund approval dialog.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const pendingRefundRow = getRefundRow(dashboardContent, "E2E Member One");
    const actionsMenu = pendingRefundRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    await actionsMenu.getByRole("button", { name: "Approve refund" }).click();
    const approveDialog = organizerGroupPage.getByRole("dialog", {
      name: "Approve refund request",
    });
    const approvalNote = approveDialog.getByLabel("Review note (optional)");
    await approvalNote.fill("Approved by organizer");

    // Verify the error alert keeps the recoverable approval note in place.
    await approveDialog.getByRole("button", { name: "Approve refund" }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Something went wrong approving this refund request. Please try again later.",
    );
    await expect(approveDialog).toBeVisible();
    await expect(approvalNote).toHaveValue("Approved by organizer");
    await organizerGroupPage.locator(".swal2-confirm").click();
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

  test("submits and preserves a required refund rejection reason", async ({ organizerGroupPage }) => {
    // Open the pending refund rejection without changing its seeded state.
    const dashboardContent = await openRefundsDashboard(organizerGroupPage);
    const pendingRefundRow = dashboardContent.locator("tr", {
      hasText: "E2E Member One",
    });
    const actionsMenu = pendingRefundRow.locator("[data-actions-menu]");
    const actionsSummary = actionsMenu.locator("summary");
    await actionsSummary.click();
    await actionsMenu.getByRole("button", { name: "Reject refund" }).click();

    // Enter the attendee-visible reason after focus moves into the rejection dialog.
    const rejectDialog = organizerGroupPage.getByRole("dialog", {
      name: "Reject refund request",
    });
    const reviewNote = rejectDialog.getByLabel("Reason shown to attendee");
    await expect(rejectDialog).toBeVisible();
    await expect(reviewNote).toBeVisible();
    await expect(reviewNote).toHaveAttribute("required", "");
    await expect(rejectDialog).toContainText(
      "This reason appears in the attendee's email, My Events, and the event page.",
    );
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

  test("shows attendee refund cancellation availability across request states", async ({
    organizerGroupPage,
  }) => {
    // Load the attendee refund state matrix from the event dashboard.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.refunds,
      TEST_PAYMENT_EVENT_IDS.refunds,
    );

    // Provider-processing refunds cannot be canceled, retried, or rejected.
    const processingAttendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Organizer Two",
    });
    const processingActionsMenu = processingAttendeeRow.locator("[data-actions-menu]");
    await expect(getVisibleStatusBadge(processingAttendeeRow, "Refund processing")).toBeVisible();
    await processingActionsMenu.locator("summary").click();
    const processingCancelAction = processingActionsMenu.getByRole("menuitem", {
      name: "Cancel attendance and refund",
    });
    await expect(processingCancelAction).toBeDisabled();
    await expect(processingCancelAction).toHaveAttribute(
      "title",
      "A refund is already in progress for this attendee.",
    );
    await expect(processingActionsMenu.getByRole("menuitem", { name: "Retry refund" })).toHaveCount(0);
    await expect(processingActionsMenu.getByRole("menuitem", { name: "Reject refund" })).toHaveCount(0);

    // Approved refunds keep their retained attendance history read-only.
    const approvedAttendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Group Viewer One",
    });
    const approvedActionsMenu = approvedAttendeeRow.locator("[data-actions-menu]");
    await expect(getVisibleStatusBadge(approvedAttendeeRow, "Refund approved")).toBeVisible();
    await approvedActionsMenu.locator("summary").click();
    const approvedCancelAction = approvedActionsMenu.getByRole("menuitem", {
      name: "Cancel attendance and refund",
    });
    await expect(approvedCancelAction).toBeDisabled();
    await expect(approvedCancelAction).toHaveAttribute(
      "title",
      "This attendee's refund has already been approved.",
    );
  });

  test("queues attendee cancellation after a rejected refund and prevents duplicate submits", async ({
    organizerGroupPage,
  }) => {
    // Hold the cancellation response so the pending disabled state remains observable.
    let releaseCancellationResponse;
    const cancellationResponseGate = new Promise((resolve) => {
      releaseCancellationResponse = resolve;
    });
    let cancellationRequestCount = 0;
    await organizerGroupPage.route("**/attendees/*/attendance", async (route) => {
      cancellationRequestCount += 1;
      await cancellationResponseGate;
      await route.fulfill({
        status: 204,
        headers: {
          "HX-Trigger": "refresh-event-attendees, refresh-group-refunds",
        },
      });
    });

    // Open the rejected attendee refund cancellation action.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.refunds,
      TEST_PAYMENT_EVENT_IDS.refunds,
    );
    const rejectedAttendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    const rowActionsMenu = rejectedAttendeeRow.locator("[data-actions-menu]");
    await expect(getVisibleStatusBadge(rejectedAttendeeRow, "Refund rejected")).toBeVisible();
    await rowActionsMenu.locator("summary").click();
    const cancelAttendance = rowActionsMenu.locator('button[id^="cancel-attendance-"]');
    await expect(cancelAttendance).toContainText("Cancel attendance and refund");
    await expect(cancelAttendance).toBeEnabled();
    await expect(cancelAttendance).toHaveAttribute("hx-delete", /attendance$/u);
    await cancelAttendance.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Their attendance will remain active until the refund is confirmed.",
    );

    // Submit once and verify HTMX disables the action until the request completes.
    const cancellationResponse = organizerGroupPage.waitForResponse(
      (response) => response.request().method() === "DELETE" && response.url().endsWith("/attendance"),
    );
    const attendeesRefreshResponse = organizerGroupPage.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/dashboard/group/events/${TEST_PAYMENT_EVENT_IDS.refunds}/attendees`) &&
        response.ok(),
    );
    await organizerGroupPage.getByRole("button", { name: "Queue refund" }).click();
    await expect.poll(() => cancellationRequestCount).toBe(1);
    await expect(cancelAttendance).toBeDisabled();
    await cancelAttendance.evaluate((button) => button.click());
    expect(cancellationRequestCount).toBe(1);

    // Release the response and verify the paid cancellation feedback.
    releaseCancellationResponse();
    await Promise.all([cancellationResponse, attendeesRefreshResponse]);
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Refund queued. Attendance will be canceled after confirmation.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();
    await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
  });

  test("shows paid attendee cancellation errors without losing retry access", async ({
    organizerGroupPage,
  }) => {
    // Fail the cancellation request without mutating shared seeded payment state.
    await organizerGroupPage.route("**/attendees/*/attendance", (route) => route.fulfill({ status: 500 }));

    // Open the paid cancellation action for a rejected refund request.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.refunds,
      TEST_PAYMENT_EVENT_IDS.refunds,
    );
    const rejectedAttendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    const rowActionsMenu = rejectedAttendeeRow.locator("[data-actions-menu]");
    await rowActionsMenu.locator("summary").click();
    const cancelAttendance = rowActionsMenu.locator('button[id^="cancel-attendance-"]');
    await expect(cancelAttendance).toContainText("Cancel attendance and refund");
    await cancelAttendance.click();

    // Submit the cancellation and verify its paid-specific recovery feedback.
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.getByRole("button", { name: "Queue refund" }).click(),
      {
        method: "DELETE",
        status: 500,
        urlIncludes: "/dashboard/group/events/",
        urlEndsWith: "/attendance",
      },
    );
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Something went wrong queueing this refund. Please try again later.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();
    await expect(cancelAttendance).toBeEnabled();
  });

  test("preserves recovery evidence on failure and restores menu focus", async ({ organizerGroupPage }) => {
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
    await expect(recoveryDialog.getByRole("button", { name: "Close modal" })).toBeVisible();
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
    await expect(recoveryDialog.getByLabel("External refund reference")).toHaveValue("external-refund-123");
    await expect(recoveryDialog.getByLabel("Evidence reviewed")).toHaveValue("Provider receipt verified.");
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Something went wrong completing this refund recovery.",
    );
    await organizerGroupPage.locator(".swal2-confirm").click();
    await recoveryDialog.getByRole("button", { name: "Cancel" }).click();
    await expect(recoveryDialog).toBeHidden();
    await expect(actionsSummary).toBeFocused();
  });

  test("retries an exhausted refund from the attention queue", async ({ organizerGroupPage }) => {
    const refundGraph = setupExhaustedRefundGraph({
      eventId: TEST_PAYMENT_EVENT_IDS.refunds,
      userId: REFUND_EXHAUSTED_USER_ID,
    });

    try {
      // Open the owned exhausted provider refund.
      const dashboardContent = await openRefundsDashboard(
        organizerGroupPage,
        "/dashboard/group?tab=refunds&view=attention",
      );
      const retryableRefundRow = getRefundRow(dashboardContent, refundGraph.attendeeName);
      const actionsMenu = retryableRefundRow.locator("[data-actions-menu]");
      await expect(retryableRefundRow).toContainText("Needs retry");
      await actionsMenu.locator("summary").click();

      // Retry the durable refund and wait for the attention queue refresh.
      const retryPath = `/dashboard/group/payment-jobs/${refundGraph.paymentJobId}/retry`;
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            new URL(response.url()).pathname === retryPath &&
            response.ok(),
        ),
        waitForRefundsResponse(organizerGroupPage),
        actionsMenu.getByRole("button", { name: "Retry refund" }).click(),
      ]);
      await expect
        .poll(() => paymentJobDiagnostics(refundGraph.paymentJobId), {
          intervals: [1_000],
          message: `refund job diagnostics: ${paymentJobDiagnostics(refundGraph.paymentJobId)}`,
          timeout: 45_000,
        })
        .toMatch(/^(?:pending|processing)\|0\||^failed\|[0-9]\|/u);
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Refund requeued.");
      await organizerGroupPage.locator(".swal2-confirm").click();
      await expect(retryableRefundRow).toHaveCount(0);

      // Verify the refund returns to active provider work without retry controls.
      await Promise.all([
        waitForRefundsResponse(organizerGroupPage),
        dashboardContent.getByLabel("Refund status").selectOption("active"),
      ]);
      const requeuedRefundRow = getRefundRow(dashboardContent, refundGraph.attendeeName);
      await expect(requeuedRefundRow).toContainText(/Queued|Processing/u);
      await expect(requeuedRefundRow).not.toContainText("Needs retry");
    } finally {
      // Remove the retried refund fixture.
      cleanupOwnedPaymentPurchase(refundGraph);
    }
  });

  test("completes manual recovery through the real refund handler", async ({ organizerGroupPage }) => {
    test.setTimeout(60_000);

    // Prepare a recoverable refund fixture for the real handler.
    const refundGraph = setupRecoverableRefundGraph({
      eventId: TEST_PAYMENT_EVENT_IDS.refunds,
      userId: REFUND_RECOVERY_USER_ID,
    });
    let notificationSnapshot;

    try {
      // Open the owned terminal provider failure.
      const dashboardContent = await openRefundsDashboard(
        organizerGroupPage,
        "/dashboard/group?tab=refunds&view=attention",
      );
      const recoveryRow = getRefundRow(dashboardContent, refundGraph.attendeeName);
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
      notificationSnapshot = snapshotNotifications();
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
      expect(recoveryData.get("event_purchase_id")).toBe(refundGraph.purchaseId);
      expect(recoveryData.get("recovery_reference")).toBe("external-refund-e2e");
      expect(recoveryData.get("recovery_note")).toBe("Provider receipt and attendee confirmation reviewed.");
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Refund recovery completed.");
      await organizerGroupPage.locator(".swal2-confirm").click();

      // Verify the recovered purchase leaves the refreshed attention queue.
      await expect(recoveryRow).toHaveCount(0);
    } finally {
      // Remove generated recovery notifications and refund data.
      if (notificationSnapshot) {
        deleteNotificationsSince(notificationSnapshot, "event-refund-approved", [refundGraph.userId]);
      }
      cleanupOwnedPaymentPurchase(refundGraph);
    }
  });
});

/** Deletes matching notifications from the notification table after a snapshot. */
const deleteNotificationsSince = (snapshot, kind, userIds) => {
  queryE2eDatabase(`
    delete from notification
    where created_at >= '${snapshot.createdAfter}'::timestamptz
    and kind = '${kind}'
    and user_id in (${userIds.map((userId) => `'${userId}'::uuid`).join(", ")});
  `);
};

/** Returns the refund table row matching the attendee name. */
const getRefundRow = (dashboardContent, attendeeName) =>
  dashboardContent
    .getByRole("table", { name: "Refunds list" })
    .locator("tbody tr", { hasText: attendeeName });

/** Opens the refunds dashboard and returns the loaded table region. */
const openRefundsDashboard = async (page, path = "/dashboard/group?tab=refunds") => {
  await navigateToPath(page, path);

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByRole("table", { name: "Refunds list" })).toBeVisible();

  return dashboardContent;
};

/** Returns payment_job status diagnostics for the supplied job ID. */
const paymentJobDiagnostics = (paymentJobId) =>
  queryE2eDatabase(`
    select status || '|' || attempt_count::text || '|' ||
      coalesce(failure_message, '<none>') || '|' ||
      coalesce(claim_id::text, '<unclaimed>')
    from payment_job
    where payment_job_id = '${paymentJobId}';
  `);

/** Waits for the refunds dashboard refresh response. */
const waitForRefundsResponse = (page) =>
  page.waitForResponse((response) => {
    const requestUrl = new URL(response.url());

    return (
      response.request().method() === "GET" &&
      requestUrl.pathname === "/dashboard/group/refunds" &&
      response.ok()
    );
  });
