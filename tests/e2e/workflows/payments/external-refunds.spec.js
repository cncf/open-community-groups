import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase } from "../../database.js";
import { TEST_EXTERNAL_PAYMENT_EVENTS, TEST_USER_IDS } from "../../seed.js";
import { getAttendanceContainer } from "../../site/event/helpers.js";
import { navigateToPath, waitForActionResponse } from "../../utils.js";
import {
  dismissAlert,
  getRefundButton,
  markExternalPurchasePaid,
  openExternalEvent,
  resetExternalPaymentFixtures,
  startExternalCheckout,
} from "./external-helpers.js";

test.describe("external payment refunds", () => {
  test.describe.configure({ mode: "serial" });

  test.beforeEach(() => {
    resetExternalPaymentFixtures();
  });

  test("records an external refund and cancels attendance immediately", async ({
    member1Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Complete an external purchase and submit its attendee refund request.
    await startExternalCheckout(member1Page, event);
    await markExternalPurchasePaid(
      organizerExternalGroupPage,
      event,
      "E2E Member One",
      "Payment confirmed before refund",
    );

    // Request the attendee refund from the event page.
    await requestExternalRefund(member1Page, event, "Unable to attend");

    // Open the group refund action and verify its external context contract.
    await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=refunds");
    const refundRow = organizerExternalGroupPage.locator("#dashboard-content tbody tr", {
      hasText: "E2E Member One",
    });
    await expect(refundRow).toContainText(event.name);
    const refundAmountCell = refundRow.locator("td").nth(2);
    const refundStatusCell = refundRow.locator("td").nth(3);
    await expect(refundAmountCell).toContainText(/(?:US)?\$12\.34/u);
    await expect(refundAmountCell).toContainText("External");
    await expect(refundStatusCell).toContainText("Needs review");
    await expect(refundStatusCell).not.toContainText("External");
    await expect(
      organizerExternalGroupPage.getByText(
        /external refunds can still be recorded after the money is returned outside OCG/u,
      ),
    ).toBeVisible();
    const actionsMenu = refundRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    const approveButton = actionsMenu.getByRole("button", {
      name: "Approve refund",
    });
    await expect(approveButton).toHaveAttribute("data-refund-external", "true");
    await approveButton.click();

    // Review the external refund approval dialog and enter the organizer note.
    const approveDialog = organizerExternalGroupPage.getByRole("dialog", {
      name: "Approve refund request",
    });
    await expect(approveDialog).toContainText("This payment was collected outside this platform.");
    await expect(approveDialog).toContainText("Unable to attend");
    await approveDialog.getByLabel("Review note (optional)").fill("Refund confirmed externally");

    // Record the external refund and verify the organizer success feedback.
    await waitForActionResponse(
      organizerExternalGroupPage,
      () => approveDialog.getByRole("button", { name: "Approve refund" }).click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/refunds/",
        urlEndsWith: "/approve",
      },
    );
    await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
      "Refund recorded. Attendance canceled.",
    );
    await dismissAlert(organizerExternalGroupPage);

    // Verify external approval cancels attendance without a provider refund row.
    expect(
      queryE2eDatabase(`
        select ep.status || '|' || err.status || '|' || coalesce(ea.status, '')
        from event_purchase ep
        join event_refund_request err using (event_purchase_id)
        left join event_attendee ea
          on ea.event_id = ep.event_id and ea.user_id = ep.user_id
        where ep.event_id = '${event.id}' and ep.user_id = '${TEST_USER_IDS.member1}';
      `),
    ).toBe("refunded|approved|attendance-canceled");
    expect(
      queryE2eDatabase(`
        select count(*) from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        where ep.event_id = '${event.id}';
      `),
    ).toBe("0");
  });

  test("preserves external context when rejecting a refund", async ({
    member2Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Complete another external purchase and request a refund for rejection.
    await startExternalCheckout(member2Page, event);
    await markExternalPurchasePaid(
      organizerExternalGroupPage,
      event,
      "E2E Member Two",
      "Payment confirmed before rejection",
    );
    await requestExternalRefund(member2Page, event, "Duplicate reservation");

    // Open rejection from the production refund row and retain external context.
    await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=refunds");
    const refundRow = organizerExternalGroupPage.locator("#dashboard-content tbody tr", {
      hasText: "E2E Member Two",
    });
    const actionsMenu = refundRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    const rejectButton = actionsMenu.getByRole("button", {
      name: "Reject refund",
    });
    await expect(rejectButton).toHaveAttribute("data-refund-external", "true");
    await rejectButton.click();

    // Review the external refund rejection dialog and enter the attendee reason.
    const rejectDialog = organizerExternalGroupPage.getByRole("dialog", {
      name: "Reject refund request",
    });
    await expect(rejectDialog).toContainText("This payment was collected outside this platform.");
    await expect(rejectDialog).toContainText("Duplicate reservation");
    const rejectionReason = "The reservation is outside the refund policy";
    await rejectDialog.getByLabel("Reason shown to attendee").fill(rejectionReason);

    // Reject the request and verify the organizer receives specific feedback.
    await waitForActionResponse(
      organizerExternalGroupPage,
      () => rejectDialog.getByRole("button", { name: "Reject refund" }).click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/refunds/",
        urlEndsWith: "/reject",
      },
    );
    await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
      "Refund request rejected.",
    );
    await dismissAlert(organizerExternalGroupPage);

    // Verify the attendee sees the preserved rejection reason on the event.
    await openExternalEvent(member2Page, event);
    await expect(getRefundButton(member2Page)).toContainText("Refund rejected");
    await getAttendanceContainer(member2Page)
      .locator('[data-attendance-role="refund-rejection-trigger"]')
      .focus();
    await expect(getAttendanceContainer(member2Page)).toContainText(rejectionReason);

    // Confirm rejection keeps the purchase completed and stores its review note.
    expect(
      queryE2eDatabase(`
        select ep.status || '|' || err.status || '|' || err.review_note
        from event_purchase ep
        join event_refund_request err using (event_purchase_id)
        where ep.event_id = '${event.id}' and ep.user_id = '${TEST_USER_IDS.member2}';
      `),
    ).toBe(`completed|rejected|${rejectionReason}`);
  });
});

/** Submits an attendee refund request for a completed external purchase. */
const requestExternalRefund = async (page, event, reason) => {
  await openExternalEvent(page, event);
  await getRefundButton(page).click();
  const requestDialog = page.getByRole("dialog", {
    name: "Request a refund",
  });
  await requestDialog.getByLabel("Reason (optional)").fill(reason);
  await waitForActionResponse(
    page,
    () => requestDialog.getByRole("button", { name: "Request refund" }).click(),
    {
      method: "POST",
      urlIncludes: `/event/${event.id}/refund-request`,
    },
  );
  await expect(page.locator(".swal2-popup")).toContainText(
    "Your refund request has been sent to the organizers.",
  );
  await dismissAlert(page);
};
