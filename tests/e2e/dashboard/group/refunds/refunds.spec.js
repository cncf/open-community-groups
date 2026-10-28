import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase, queryE2eDatabaseRows, sqlUuid } from "../../../database.js";
import { cleanupEventsByIds, insertOwnedEvent } from "../../../data-graphs/events.js";
import {
  cleanupOwnedPaymentPurchase,
  setupExhaustedFinancialWorkGraph,
  setupExhaustedRefundGraph,
  setupExternalRefundRequestGraph,
  setupOwnedCompletedRefundPurchase,
  setupOwnedExternalCompletedPurchase,
  setupRecoverableRefundGraph,
} from "../../../data-graphs/payments.js";
import {
  TEST_FINANCIAL_WORK_JOB_IDS,
  TEST_GROUP_IDS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_USER_IDS,
} from "../../../seed.js";
import {
  dismissAlert,
  expectCurrentPaginationNavigation,
  shortId,
  waitForActionResponse,
  waitForActionResponses,
  waitForResponseMatching,
} from "../../../utils.js";
import { getVisibleStatusBadge, openAttendeesTab } from "../events/attendees-helpers.js";
import { openGroupEventsTabWithEvent } from "../events/helpers.js";
import {
  REFUNDS_REFRESH_RESPONSE,
  getRefundRow,
  openRefundsDashboard,
  waitForRefundsRefresh,
} from "./helpers.js";

const ATTENDANCE_CANCELLATION_PATHNAME = new RegExp(
  `^/dashboard/group/events/${TEST_PAYMENT_EVENT_IDS.refunds}/attendees/[^/]+/attendance$`,
  "u",
);

const FINANCIAL_RECOVERY_PATHNAME = "/dashboard/group/payment-jobs/recovery";

const REFUND_APPROVE_PATHNAME = /^\/dashboard\/group\/refunds\/[^/]+\/approve$/u;

const REFUND_RECOVERY_PATHNAME = "/dashboard/group/refunds/recovery";

const REFUND_REJECT_PATHNAME = /^\/dashboard\/group\/refunds\/[^/]+\/reject$/u;

const REFUND_APPROVAL_USER_ID = TEST_USER_IDS.admin2;

const REFUND_EXHAUSTED_USER_ID = TEST_USER_IDS.member3;

const REFUND_RECOVERY_USER_ID = TEST_USER_IDS.checkInManager1;

const REFUND_RECOVERY_USER_NAME = "E2E Check-In Manager One";

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
    await waitForActionResponse(organizerGroupPage, () => refundStatus.selectOption("completed"), {
      ...REFUNDS_REFRESH_RESPONSE,
      params: { view: "completed" },
    });
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
    await waitForActionResponse(
      organizerGroupPage,
      () => creditNoteActionsMenu.getByRole("button", { name: "Retry operation" }).click(),
      { method: "PUT", pathname: creditNoteRetryPath, status: 422 },
    );
    await dismissAlert(organizerGroupPage, {
      message: "Something went wrong requeueing this financial work.",
    });

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
    await waitForActionResponse(organizerGroupPage, () => refundStatus.selectOption("attention"), {
      ...REFUNDS_REFRESH_RESPONSE,
      params: { view: "attention" },
    });

    // Verify the selected view is durable and retains focus after the swap.
    await expect.poll(() => new URL(organizerGroupPage.url()).searchParams.get("view")).toBe("attention");
    await expect(dashboardContent.getByLabel("Refund status")).toBeFocused();

    // Apply a search and verify its URL and focus contract.
    const refundSearch = dashboardContent.getByRole("textbox", {
      name: "Search refunds",
    });
    await refundSearch.fill("E2E Member");
    await waitForActionResponse(organizerGroupPage, () => refundSearch.press("Enter"), {
      ...REFUNDS_REFRESH_RESPONSE,
      params: { ts_query: "E2E Member" },
    });
    await expect
      .poll(() => new URL(organizerGroupPage.url()).searchParams.get("ts_query"))
      .toBe("E2E Member");
    await expect(refundSearch).toBeFocused();

    // Clear filters and move focus to the replacement search control.
    await waitForActionResponse(
      organizerGroupPage,
      () => dashboardContent.getByRole("button", { name: "Clear refund search" }).click(),
      { ...REFUNDS_REFRESH_RESPONSE, params: { ts_query: null } },
    );
    await expect.poll(() => new URL(organizerGroupPage.url()).searchParams.has("ts_query")).toBe(false);
    await expect(dashboardContent.getByRole("textbox", { name: "Search refunds" })).toBeFocused();
  });

  test("submits a refund approval and refreshes the active queue", async ({ organizerGroupPage }) => {
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
    const [approveResponse] = await waitForActionResponses(
      organizerGroupPage,
      () => approveDialog.getByRole("button", { name: "Approve refund" }).click(),
      [{ method: "PUT", pathname: REFUND_APPROVE_PATHNAME, status: 204 }, REFUNDS_REFRESH_RESPONSE],
    );
    const approvalData = new URLSearchParams(approveResponse.request().postData());
    expect(approvalData.get("review_note")).toBe("Approved by organizer");

    // Verify the action feedback remains visible after the queue refreshes.
    await dismissAlert(organizerGroupPage, { message: "Refund queued." });
    await expect(dashboardContent.getByRole("table", { name: "Refunds list" })).toBeVisible();
  });

  test("organizer approval and rejection notify refund request owners", async ({
    notifications,
    organizerGroupPage,
  }) => {
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
      await waitForActionResponses(
        organizerGroupPage,
        () => dialog.getByRole("button", { name: "Approve refund" }).click(),
        [
          {
            method: "PUT",
            pathname: `/dashboard/group/refunds/${approvedRequest.purchaseId}/approve`,
            status: 204,
          },
          REFUNDS_REFRESH_RESPONSE,
        ],
      );
      notifications.expectNew([{ kind: "event-refund-approved", userIds: [approvedRequest.userId] }]);
      await dismissAlert(organizerGroupPage, { message: "Refund recorded" });
      await expect(refundRow).toHaveCount(0);
    } finally {
      // Remove the approved refund request.
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
      const rejectionCheckpoint = notifications.checkpoint();
      await waitForActionResponses(
        organizerGroupPage,
        () => dialog.getByRole("button", { name: "Reject refund" }).click(),
        [
          {
            method: "PUT",
            pathname: `/dashboard/group/refunds/${rejectedRequest.purchaseId}/reject`,
            status: 204,
          },
          REFUNDS_REFRESH_RESPONSE,
        ],
      );
      notifications.expectNew([{ kind: "event-refund-rejected", userIds: [rejectedRequest.userId] }], {
        since: rejectionCheckpoint,
      });
      await dismissAlert(organizerGroupPage, { message: "Refund request rejected." });
      await expect(refundRow).toHaveCount(0);
    } finally {
      // Remove the rejected refund request.
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
    await dismissAlert(organizerGroupPage, {
      message: "Something went wrong approving this refund request. Please try again later.",
    });
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
    const approvalResponse = waitForResponseMatching(organizerGroupPage, {
      method: "PUT",
      pathname: REFUND_APPROVE_PATHNAME,
      status: 204,
    });
    const refundsResponse = waitForRefundsRefresh(organizerGroupPage);
    await submitButton.click();
    await expect.poll(() => approvalRequestCount).toBe(1);
    await expect(submitButton).toBeDisabled();
    await submitButton.evaluate((button) => button.click());
    expect(approvalRequestCount).toBe(1);

    // Release the response and verify the normal success refresh completes.
    releaseApprovalResponse();
    await Promise.all([approvalResponse, refundsResponse]);
    await dismissAlert(organizerGroupPage, { message: "Refund queued." });
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
    const rejectResponse = await waitForActionResponse(
      organizerGroupPage,
      () => rejectDialog.getByRole("button", { name: "Reject refund" }).click(),
      { method: "PUT", pathname: REFUND_REJECT_PATHNAME, status: 422 },
    );
    const rejectionData = new URLSearchParams(rejectResponse.request().postData());
    expect(rejectionData.get("review_note")).toBe("Duplicate purchase");

    // Preserve the note after failure and restore focus when the modal closes.
    await expect(rejectDialog).toBeVisible();
    await expect(reviewNote).toHaveValue("Duplicate purchase");
    await dismissAlert(organizerGroupPage, {
      message: "Something went wrong rejecting this refund request.",
    });
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
    const cancellationResponse = waitForResponseMatching(organizerGroupPage, {
      method: "DELETE",
      pathname: ATTENDANCE_CANCELLATION_PATHNAME,
      status: 204,
    });
    const attendeesRefreshResponse = waitForResponseMatching(organizerGroupPage, {
      method: "GET",
      pathname: `/dashboard/group/events/${TEST_PAYMENT_EVENT_IDS.refunds}/attendees`,
      status: 200,
    });
    await organizerGroupPage.getByRole("button", { name: "Queue refund" }).click();
    await expect.poll(() => cancellationRequestCount).toBe(1);
    await expect(cancelAttendance).toBeDisabled();
    await cancelAttendance.evaluate((button) => button.click());
    expect(cancellationRequestCount).toBe(1);

    // Release the response and verify the paid cancellation feedback.
    releaseCancellationResponse();
    await Promise.all([cancellationResponse, attendeesRefreshResponse]);
    await dismissAlert(organizerGroupPage, {
      message: "Refund queued. Attendance will be canceled after confirmation.",
    });
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
      { method: "DELETE", pathname: ATTENDANCE_CANCELLATION_PATHNAME, status: 500 },
    );
    await dismissAlert(organizerGroupPage, {
      message: "Something went wrong queueing this refund. Please try again later.",
    });
    await expect(cancelAttendance).toBeEnabled();
  });

  test("queues a real refund when cancelling a paid attendee", async ({
    notifications,
    organizerGroupPage,
  }) => {
    // Sequential reuse of the manual-recovery attendee is safe because setup pre-cleans.
    const purchase = setupOwnedCompletedRefundPurchase({
      eventId: TEST_PAYMENT_EVENT_IDS.refunds,
      userId: REFUND_RECOVERY_USER_ID,
    });

    try {
      // Open the owned paid attendee's cancellation action.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", { hasText: REFUND_RECOVERY_USER_NAME });
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.locator('button[id^="cancel-attendance-"]');
      await expect(cancelAttendance).toContainText("Cancel attendance and refund");
      await cancelAttendance.click();

      // Queue the refund through the real handler and wait for the attendees refresh.
      await waitForActionResponses(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Queue refund" }).click(),
        [
          { method: "DELETE", pathname: ATTENDANCE_CANCELLATION_PATHNAME, status: 204 },
          {
            method: "GET",
            pathname: `/dashboard/group/events/${TEST_PAYMENT_EVENT_IDS.refunds}/attendees`,
            status: 200,
          },
        ],
      );
      await dismissAlert(organizerGroupPage, {
        message: "Refund queued. Attendance will be canceled after confirmation.",
      });
      await expect(attendeeRow).toBeVisible();

      // Verify the durable refund work exists while attendance stays confirmed.
      await expect
        .poll(() => attendanceCancellationState(purchase), {
          message: "attendance-cancellation refund exists; received value includes payment_job diagnostics",
        })
        .toMatchObject({ attendeeStatus: "confirmed", refundKind: "attendance-cancellation" });
      expect(attendanceCancellationState(purchase).purchaseStatus).not.toBe("completed");

      // Paid cancellations notify only after the provider confirms the refund.
      const canceledNotifications = notifications
        .list()
        .filter(({ kind }) => kind === "event-attendance-canceled");
      expect(canceledNotifications).toEqual([]);

      // Verify the queued refund appears in the group refunds dashboard.
      const dashboardContent = await openRefundsDashboard(
        organizerGroupPage,
        `/dashboard/group?tab=refunds&view=all&event_id=${TEST_PAYMENT_EVENT_IDS.refunds}`,
      );
      const refundRow = getRefundRow(dashboardContent, REFUND_RECOVERY_USER_NAME);
      await expect(refundRow).toBeVisible();
      await expect(refundRow).toContainText("Attendance cancellation");
    } finally {
      // Remove the queued refund, its payment job and the owned attendance.
      cleanupOwnedPaymentPurchase(purchase);
    }
  });

  test("cancelling a paid event queues provider refunds and refunds external purchases locally", async ({
    notifications,
    organizerGroupPage,
  }) => {
    // Create an owned USD event with one Stripe and one external completed purchase.
    const event = insertOwnedEvent({
      groupId: TEST_GROUP_IDS.community1.alpha,
      paymentCurrencyCode: "USD",
      tiers: [{ amountMinor: 5000, key: "general", seats: 10, title: "General admission" }],
    });

    try {
      const stripePurchase = setupOwnedCompletedRefundPurchase({
        eventId: event.eventId,
        userId: TEST_USER_IDS.member1,
      });
      const externalPurchase = setupOwnedExternalCompletedPurchase({
        eventId: event.eventId,
        userId: TEST_USER_IDS.member2,
      });

      // Open the owned event's cancel action from the events list.
      const eventRow = await openGroupEventsTabWithEvent(organizerGroupPage, event.name);
      await eventRow.locator(".btn-actions").click();
      await eventRow.locator('button[id^="cancel-event-"]').click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Cancel this event? This cannot be undone. All attendee registrations will be canceled immediately. Full refunds for eligible paid purchases will be queued and may take time to process.",
      );

      // Confirm the cancellation through the real handler.
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Cancel event" }).click(),
        {
          method: "PUT",
          pathname: `/dashboard/group/events/${event.eventId}/cancel`,
          status: 204,
        },
      );
      notifications.expectNew([
        {
          kind: "event-canceled",
          templateDataContains: { event: { event_id: event.eventId } },
          userIds: [TEST_USER_IDS.member1, TEST_USER_IDS.member2],
        },
      ]);

      // Reopen the events list and verify the row reflects the canceled state.
      const canceledEventRow = await openGroupEventsTabWithEvent(organizerGroupPage, event.name);
      await expect(canceledEventRow).toContainText("Canceled");

      // The Stripe purchase gets an event-cancellation refund backed by a provider job.
      await expect
        .poll(() => paidEventCancellationState(stripePurchase), {
          message: "event-cancellation refund and payment job exist for the Stripe purchase",
        })
        .toMatchObject({
          paymentJobKind: "event-purchase-refund",
          purchaseStatus: expect.not.stringMatching(/^completed$/u),
          refundKind: "event-cancellation",
        });

      // The external purchase is refunded locally without provider work (cancel_event.sql).
      expect(paidEventCancellationState(externalPurchase)).toEqual({
        paymentJobKind: null,
        purchaseStatus: "refunded",
        refundKind: null,
      });

      // Verify the queued Stripe refund appears in the group refunds dashboard.
      const dashboardContent = await openRefundsDashboard(
        organizerGroupPage,
        `/dashboard/group?tab=refunds&view=all&event_id=${event.eventId}`,
      );
      const stripeRefundRow = getRefundRow(dashboardContent, "E2E Member One");
      await expect(stripeRefundRow).toBeVisible();
      await expect(stripeRefundRow).toContainText("Event cancellation");
      await expect(getRefundRow(dashboardContent, externalPurchase.attendeeName)).toContainText("Refunded");
    } finally {
      // Remove the event with its purchases, refunds, payment jobs and attendance.
      cleanupEventsByIds([event.eventId]);
    }
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
    await waitForActionResponse(
      organizerGroupPage,
      () => recoveryDialog.getByRole("button", { name: "Complete recovery" }).click(),
      { method: "PUT", pathname: REFUND_RECOVERY_PATHNAME, status: 422 },
    );

    // Verify recoverable work remains available before closing the dialog.
    await expect(recoveryDialog).toBeVisible();
    await expect(recoveryDialog.getByLabel("External refund reference")).toHaveValue("external-refund-123");
    await expect(recoveryDialog.getByLabel("Evidence reviewed")).toHaveValue("Provider receipt verified.");
    await dismissAlert(organizerGroupPage, {
      message: "Something went wrong completing this refund recovery.",
    });
    await recoveryDialog.getByRole("button", { name: "Cancel" }).click();
    await expect(recoveryDialog).toBeHidden();
    await expect(actionsSummary).toBeFocused();
  });

  test("retries an exhausted refund from the attention queue", async ({ organizerGroupPage }) => {
    // The payment job poll below allows up to 45s for the worker, beyond the default test budget.
    test.setTimeout(60_000);

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
      await waitForActionResponses(
        organizerGroupPage,
        () => actionsMenu.getByRole("button", { name: "Retry refund" }).click(),
        [{ method: "PUT", pathname: retryPath, status: 204 }, REFUNDS_REFRESH_RESPONSE],
      );
      await expect
        .poll(() => paymentJobDiagnostics(refundGraph.paymentJobId), {
          intervals: [1_000],
          message: "retried refund job is requeued or picked up by the payments worker",
          timeout: 45_000,
        })
        .toMatch(/^(?:pending|processing)\|0\||^failed\|[0-9]\|/u);
      await dismissAlert(organizerGroupPage, { message: "Refund requeued." });
      await expect(retryableRefundRow).toHaveCount(0);

      // Verify the refund returns to active provider work without retry controls.
      await waitForActionResponse(
        organizerGroupPage,
        () => dashboardContent.getByLabel("Refund status").selectOption("active"),
        { ...REFUNDS_REFRESH_RESPONSE, params: { view: "active" } },
      );
      const requeuedRefundRow = getRefundRow(dashboardContent, refundGraph.attendeeName);
      await expect(requeuedRefundRow).toContainText(/Queued|Processing/u);
      await expect(requeuedRefundRow).not.toContainText("Needs retry");
    } finally {
      // Remove the retried refund fixture.
      cleanupOwnedPaymentPurchase(refundGraph);
    }
  });

  test("completes manual recovery through the real refund handler", async ({ organizerGroupPage }) => {
    // Prepare a recoverable refund fixture for the real handler.
    const refundGraph = setupRecoverableRefundGraph({
      eventId: TEST_PAYMENT_EVENT_IDS.refunds,
      userId: REFUND_RECOVERY_USER_ID,
    });

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
      const [recoveryResponse] = await waitForActionResponses(
        organizerGroupPage,
        () => recoveryDialog.getByRole("button", { name: "Complete recovery" }).click(),
        [{ method: "PUT", pathname: REFUND_RECOVERY_PATHNAME, status: 204 }, REFUNDS_REFRESH_RESPONSE],
      );
      const recoveryData = new URLSearchParams(recoveryResponse.request().postData());
      expect(recoveryData.get("event_purchase_id")).toBe(refundGraph.purchaseId);
      expect(recoveryData.get("recovery_reference")).toBe("external-refund-e2e");
      expect(recoveryData.get("recovery_note")).toBe("Provider receipt and attendee confirmation reviewed.");
      await dismissAlert(organizerGroupPage, { message: "Refund recovery completed." });

      // Verify the recovered purchase leaves the refreshed attention queue.
      await expect(recoveryRow).toHaveCount(0);
    } finally {
      // Remove the recovered refund data.
      cleanupOwnedPaymentPurchase(refundGraph);
    }
  });

  test("completes exhausted financial work outside OCG through the real handler", async ({
    organizerGroupPage,
  }) => {
    // Sequential reuse of the exhausted-refund attendee is safe because setup pre-cleans.
    const workGraph = setupExhaustedFinancialWorkGraph({
      eventId: TEST_PAYMENT_EVENT_IDS.refunds,
      userId: REFUND_EXHAUSTED_USER_ID,
    });
    const providerCreditNoteId = `cn_e2e_recovery_${shortId(workGraph.creditNoteId)}`;
    const recoveryNote = "Credit note issued in the Stripe dashboard and checked against the refund.";
    const recoveryReference = `stripe-dashboard-${shortId(workGraph.paymentJobId)}`;

    try {
      // Open the owned exhausted credit-note work in the attention view.
      const dashboardContent = await openRefundsDashboard(
        organizerGroupPage,
        `/dashboard/group?tab=refunds&view=attention&event_id=${TEST_PAYMENT_EVENT_IDS.refunds}`,
      );
      const financialWorkRow = dashboardContent
        .getByRole("table", { name: "Financial work needing attention" })
        .locator("tbody tr", { hasText: workGraph.attendeeName });
      await expect(financialWorkRow).toHaveAttribute(
        "data-financial-work-kind",
        "event-purchase-credit-note",
      );
      await expect(financialWorkRow).toContainText("Credit note");
      const actionsMenu = financialWorkRow.locator("[data-actions-menu]");
      await actionsMenu.locator("summary").click();
      await actionsMenu.getByRole("button", { name: "Complete outside OCG" }).click();

      // Fill the provider credit note and the evidence reviewed outside OCG.
      const recoveryDialog = organizerGroupPage.getByRole("dialog", { name: "Complete outside OCG" });
      await expect(recoveryDialog.locator('input[name="payment_job_id"]')).toHaveValue(
        workGraph.paymentJobId,
      );
      await recoveryDialog.getByLabel("Stripe credit note ID").fill(providerCreditNoteId);
      await recoveryDialog.getByLabel("External recovery reference").fill(recoveryReference);
      await recoveryDialog.getByLabel("Evidence reviewed").fill(recoveryNote);

      // Submit through the real handler and wait for the attention view refresh.
      const [recoveryResponse] = await waitForActionResponses(
        organizerGroupPage,
        () => recoveryDialog.getByRole("button", { name: "Complete recovery" }).click(),
        [{ method: "PUT", pathname: FINANCIAL_RECOVERY_PATHNAME, status: 204 }, REFUNDS_REFRESH_RESPONSE],
      );
      const recoveryData = new URLSearchParams(recoveryResponse.request().postData());
      expect(recoveryData.get("payment_job_id")).toBe(workGraph.paymentJobId);
      expect(recoveryData.get("provider_object_id")).toBe(providerCreditNoteId);
      await dismissAlert(organizerGroupPage, { message: "Financial recovery completed." });

      // Verify the completed work leaves the refreshed attention view.
      await expect(financialWorkRow).toHaveCount(0);

      // Verify the job recovery evidence, the credit note outcome, and one audit row.
      expect(financialWorkRecovery(workGraph)).toEqual({
        auditRows: [[TEST_USER_IDS.organizer1, workGraph.eventId]],
        creditNote: [providerCreditNoteId, "<none>", "<none>"],
        paymentJob: [
          "completed",
          "<none>",
          "true",
          TEST_USER_IDS.organizer1,
          recoveryNote,
          recoveryReference,
        ],
      });
    } finally {
      // Remove the recovered financial work.
      cleanupOwnedPaymentPurchase(workGraph);
    }
  });
});

/** Returns attendance, purchase, refund and payment_job diagnostics for a paid cancellation. */
const attendanceCancellationState = ({ eventId, purchaseId, userId }) =>
  JSON.parse(
    queryE2eDatabase(`
      select json_build_object(
        'attendeeStatus', (
          select status
          from event_attendee
          where event_id = ${sqlUuid(eventId)}
          and user_id = ${sqlUuid(userId)}
        ),
        'paymentJob', (
          select json_build_object(
            'attemptCount', pj.attempt_count,
            'failureMessage', pj.failure_message,
            'status', pj.status
          )
          from event_purchase_refund epr
          join payment_job pj using (payment_job_id)
          where epr.event_purchase_id = ${sqlUuid(purchaseId)}
        ),
        'purchaseStatus', (
          select status
          from event_purchase
          where event_purchase_id = ${sqlUuid(purchaseId)}
        ),
        'refundKind', (
          select kind
          from event_purchase_refund
          where event_purchase_id = ${sqlUuid(purchaseId)}
        )
      );
    `),
  );

/** Returns the purchase status and any refund and payment job kinds for an event cancellation. */
const paidEventCancellationState = ({ purchaseId }) =>
  JSON.parse(
    queryE2eDatabase(`
      select json_build_object(
        'paymentJobKind', (
          select kind
          from payment_job
          where event_purchase_id = ${sqlUuid(purchaseId)}
        ),
        'purchaseStatus', (
          select status
          from event_purchase
          where event_purchase_id = ${sqlUuid(purchaseId)}
        ),
        'refundKind', (
          select kind
          from event_purchase_refund
          where event_purchase_id = ${sqlUuid(purchaseId)}
        )
      );
    `),
  );

/** Returns the durable payment job, credit note and audit outcome of a financial work recovery. */
const financialWorkRecovery = ({ creditNoteId, paymentJobId }) => ({
  auditRows: queryE2eDatabaseRows(`
    select actor_user_id, resource_id
    from audit_log
    where action = 'event_credit_note_recovery_completed'
    and details->>'payment_job_id' = ${sqlUuid(paymentJobId)}::text
    order by created_at;
  `),
  creditNote: queryE2eDatabaseRows(`
    select
      coalesce(provider_credit_note_id, '<none>'),
      coalesce(provider_hosted_url, '<none>'),
      coalesce(provider_pdf_url, '<none>')
    from event_purchase_credit_note
    where event_purchase_credit_note_id = ${sqlUuid(creditNoteId)};
  `).at(0),
  paymentJob: queryE2eDatabaseRows(`
    select
      status,
      coalesce(failure_message, '<none>'),
      (completed_at is not null and recovery_completed_at is not null)::text,
      recovery_completed_by_user_id,
      recovery_note,
      recovery_reference
    from payment_job
    where payment_job_id = ${sqlUuid(paymentJobId)};
  `).at(0),
});

/** Returns payment_job status diagnostics for the supplied job ID. */
const paymentJobDiagnostics = (paymentJobId) =>
  queryE2eDatabase(`
    select status || '|' || attempt_count::text || '|' ||
      coalesce(failure_message, '<none>') || '|' ||
      coalesce(claim_id::text, '<unclaimed>')
    from payment_job
    where payment_job_id = '${paymentJobId}';
  `);
