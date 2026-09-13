import { expect, test } from "../../../fixtures.js";

import { TEST_PAYMENT_EVENT_IDS, TEST_PAYMENT_EVENT_NAMES } from "../../../seed.js";

import { getVisibleStatusBadge, openAttendeesTab } from "./attendees-helpers.js";

test.describe("group dashboard attendees tab — refunds", () => {
  test("organizer can act on a pending refund request from the attendee row menu", async ({
    organizerGroupPage,
  }) => {
    // Load the attendees tab for the seeded refund review event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.refunds,
      TEST_PAYMENT_EVENT_IDS.refunds,
    );
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member One",
    });
    const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");

    // Assert that Refund requested is visible.
    await expect(getVisibleStatusBadge(attendeeRow, "Refund requested")).toBeVisible();
    await expect(rowActionsMenu).toBeVisible();

    // Verify pending refunds expose approve and reject actions.
    await rowActionsMenu.locator("summary").click();
    const approveRefundAction = rowActionsMenu.getByRole("menuitem", {
      name: "Approve refund",
    });
    await expect(approveRefundAction).toHaveAttribute(
      "data-refund-approve-url",
      /\/refunds\/[^/]+\/approve$/,
    );
    await expect(approveRefundAction).toHaveAttribute("data-attendee-refund-approve-open", "");
    const rejectRefundAction = rowActionsMenu.getByRole("menuitem", {
      name: "Reject refund",
    });
    await expect(rejectRefundAction).toHaveAttribute("data-refund-reject-url", /\/refunds\/[^/]+\/reject$/);
    await expect(rejectRefundAction).toHaveAttribute("data-attendee-refund-reject-open", "");
    const cancelAttendance = rowActionsMenu.getByRole("menuitem", {
      name: "Cancel attendance and refund",
    });
    await expect(cancelAttendance).toBeEnabled();
    await expect(cancelAttendance).toHaveAttribute("hx-delete", /\/attendance$/u);

    // Verify approval opens the optional review-note modal.
    await approveRefundAction.click();
    const approveDialog = organizerGroupPage.getByRole("dialog", {
      name: "Approve refund request",
    });
    await expect(approveDialog).toBeVisible();
    const approvalNote = approveDialog.getByLabel("Review note (optional)");
    await expect(approvalNote).toBeFocused();
    await expect(approvalNote).not.toHaveAttribute("required", "");
    await approveDialog.getByRole("button", { name: "Cancel" }).click();
    await expect(approveDialog).toBeHidden();
    await expect(rowActionsMenu.locator("summary")).toBeFocused();

    // Verify rejection opens the attendee-visible reason modal.
    await rowActionsMenu.locator("summary").click();
    await rejectRefundAction.click();
    const rejectDialog = organizerGroupPage.getByRole("dialog", {
      name: "Reject refund request",
    });
    await expect(rejectDialog).toBeVisible();
    await expect(rejectDialog.getByLabel("Reason shown to attendee")).toBeFocused();
    await rejectDialog.getByRole("button", { name: "Cancel" }).click();
    await expect(rejectDialog).toBeHidden();
    await expect(rowActionsMenu.locator("summary")).toBeFocused();
  });

  test("viewer cannot manage attendee refunds", async ({ groupViewerPage }) => {
    // Load the attendees tab for the seeded refund review event.
    const attendeesContent = await openAttendeesTab(
      groupViewerPage,
      TEST_PAYMENT_EVENT_NAMES.refunds,
      TEST_PAYMENT_EVENT_IDS.refunds,
    );

    // Verify refund review controls are hidden for read-only viewers.
    await expect(attendeesContent.locator("[data-attendee-refund-approve-open]")).toHaveCount(0);
    await expect(attendeesContent.locator("[data-attendee-refund-reject-open]")).toHaveCount(0);
    await expect(groupViewerPage.locator("#attendee-refund-approve-modal")).toHaveCount(0);
    await expect(groupViewerPage.locator("#attendee-refund-reject-modal")).toHaveCount(0);
    await expect(
      attendeesContent.getByRole("menuitem", {
        name: "Cancel attendance and refund",
      }),
    ).toHaveCount(0);
  });
});
