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
  addDiscountCode,
  openEventUpdateFormByName,
  openPaymentsSection,
  setDiscountCodeActive,
} from "../../dashboard/group/events/helpers.js";

test.describe("paid event discount checkout workflow", () => {
  test("organizer creates a full discount that completes paid question checkout for free", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    const discountCode = "FULLCOMP";
    const event = TEST_TICKETING_EVENTS.paidQuestions;
    const saveEvent = async () => {
      const [response] = await Promise.all([
        organizerGroupPage.waitForResponse(
          (candidateResponse) =>
            candidateResponse.request().method() === "PUT" &&
            candidateResponse
              .url()
              .includes(`/dashboard/group/events/${event.id}/update`),
        ),
        organizerGroupPage.locator("#update-event-button").click(),
      ]);

      expect(response.ok()).toBeTruthy();
      await expect(
        organizerGroupPage.locator("#dashboard-content"),
      ).not.toHaveClass(/htmx-(?:request|settling)/);
    };
    let attendanceCreated = false;
    let discountConfigured = false;

    try {
      // Prepare a 100-percent code on the dedicated paid questions event.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
      await openEventUpdateFormByName(organizerGroupPage, event.name, event.id);
      await openPaymentsSection(organizerGroupPage);
      const existingDiscountRow = organizerGroupPage
        .locator('#discount-codes-ui [data-ticketing-role="table-body"] tr')
        .filter({ hasText: discountCode });
      if ((await existingDiscountRow.count()) > 0) {
        if (
          (await existingDiscountRow
            .getByText("Active", { exact: true })
            .count()) === 0
        ) {
          await setDiscountCodeActive(organizerGroupPage, discountCode, true);
          await saveEvent();
        }
      } else {
        await addDiscountCode(organizerGroupPage, {
          code: discountCode,
          kind: "percentage",
          percentage: "100",
          title: "Complimentary registration",
        });
        await saveEvent();
      }
      discountConfigured = true;

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
      // Restore the reusable attendee and event configuration.
      if (attendanceCreated) {
        const cleanupResponse = await member2Page.request.delete(
          buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${event.id}/leave`),
        );
        expect(cleanupResponse.ok()).toBeTruthy();
      }

      if (discountConfigured) {
        await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
        await openEventUpdateFormByName(
          organizerGroupPage,
          event.name,
          event.id,
        );
        await openPaymentsSection(organizerGroupPage);
        await setDiscountCodeActive(organizerGroupPage, discountCode, false);
        await saveEvent();
      }
    }
  });
});
