import { expect, test } from "../../fixtures.js";

import {
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUGS,
  TEST_TICKETING_EVENTS,
  buildE2eUrl,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  navigateToPath,
  waitForActionResponse,
  waitForAttendanceState,
} from "../../utils.js";
import {
  openEventUpdateFormByName,
  openPaymentsSection,
} from "../../dashboard/group/events/helpers.js";

test.describe("paid event discount checkout workflow", () => {
  test("a full discount completes paid question checkout for free", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    const discountCode = "FULLCOMP";
    const event = TEST_TICKETING_EVENTS.paidQuestions;
    let attendanceCreated = false;

    try {
      // Verify the dedicated event exposes its seeded provider-free discount.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
      await openEventUpdateFormByName(organizerGroupPage, event.name, event.id);
      await openPaymentsSection(organizerGroupPage);
      const discountRow = organizerGroupPage
        .locator('#discount-codes-ui [data-ticketing-role="table-body"] tr')
        .filter({ hasText: discountCode });
      await expect(discountRow).toContainText("Complimentary registration");
      await expect(discountRow.getByText("100% off", { exact: true }).first()).toBeVisible();
      await expect(discountRow.getByText("Active", { exact: true }).first()).toBeVisible();

      // Select the paid ticket and redeem the configured code.
      await navigateToEvent(
        member2Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        event.slug,
      );
      await waitForAttendanceState(member2Page);
      await getAttendButton(member2Page).click();
      const ticketModal = member2Page.locator(
        '[data-attendance-role="ticket-modal"]',
      );
      await ticketModal
        .locator("label", { hasText: "Questions conference pass" })
        .click();
      await ticketModal
        .locator('[data-attendance-role="discount-code-input"]')
        .fill(discountCode);
      await ticketModal
        .locator('[data-attendance-role="checkout-btn"]')
        .click();

      // Answer the required question before the checkout request resumes.
      const registrationModal = member2Page.locator(
        '[data-attendance-role="registration-modal"]',
      );
      await expect(registrationModal).toBeVisible();
      await registrationModal
        .getByRole("textbox")
        .fill("Please prepare accessible workshop materials.");
      const checkoutRequest = member2Page.waitForRequest(
        (request) =>
          request.method() === "POST" &&
          request.url().includes(`/event/${event.id}/checkout`),
      );
      await waitForActionResponse(
        member2Page,
        () =>
          registrationModal
            .locator('[data-attendance-role="registration-modal-submit"]')
            .click(),
        {
          method: "POST",
          urlIncludes: `/event/${event.id}/checkout`,
        },
      );
      attendanceCreated = true;
      const requestData = new URLSearchParams(
        (await checkoutRequest).postData() ?? "",
      );
      const answers = JSON.parse(
        requestData.get("registration_answers") ?? "{}",
      );

      // The full discount completes without handing control to a provider.
      expect(requestData.get("discount_code")).toBe(discountCode);
      expect(answers.answers?.[0]?.value).toBe(
        "Please prepare accessible workshop materials.",
      );
      await expect(getLeaveButton(member2Page)).toContainText(
        "Cancel attendance",
      );
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "You have successfully registered for this event.",
      );
    } finally {
      // Restore the reusable attendee configuration.
      if (attendanceCreated) {
        const cleanupResponse = await member2Page.request.delete(
          buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${event.id}/leave`),
        );
        expect(cleanupResponse.ok()).toBeTruthy();
      }
    }
  });
});
