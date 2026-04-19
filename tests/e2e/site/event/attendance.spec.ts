import type { Page } from "@playwright/test";

import { expect, test } from "../../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_PAYMENT_EVENT_SLUGS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  waitForAttendanceState,
} from "../../utils";

/** Cancels attendance when the current user is already registered. */
const cancelAttendance = async (page: Page, eventId: string) => {
  const leaveButton = getLeaveButton(page);
  await expect(leaveButton).toBeVisible();

  await leaveButton.click();
  const confirmButton = page.getByRole("button", { name: "Yes" });
  await expect(confirmButton).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "DELETE" &&
        response.url().includes(`/event/${eventId}/leave`) &&
        response.ok(),
    ),
    confirmButton.click(),
  ]);

  await expect(getAttendButton(page)).toBeVisible();
};

const getTicketModal = (page: Page) =>
  page.locator('[data-attendance-role="ticket-modal"]');

const getCheckoutButton = (page: Page) =>
  page.locator('[data-attendance-role="checkout-btn"]');

const getRefundButton = (page: Page) =>
  page.locator('[data-attendance-role="refund-btn"]');

const getSignInButton = (page: Page) =>
  page.locator('[data-attendance-role="signin-btn"]');

test.describe("event attendance", () => {
  test("member can attend and cancel from the public event page", async ({
    member2Page,
  }) => {
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    await expect(
      member2Page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();

    await waitForAttendanceState(member2Page);

    if (await getLeaveButton(member2Page).isVisible()) {
      await cancelAttendance(member2Page, TEST_EVENT_IDS.alpha.one);
    }

    const attendButton = getAttendButton(member2Page);
    await expect(attendButton).toBeVisible();

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    await expect(getLeaveButton(member2Page)).toBeVisible();

    await cancelAttendance(member2Page, TEST_EVENT_IDS.alpha.one);
  });

  test("guest sees the buy ticket CTA on a ticketed event", async ({ page }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.draft,
    );

    await expect(
      page.getByRole("heading", {
        level: 1,
        name: TEST_PAYMENT_EVENT_NAMES.draft,
      }),
    ).toBeVisible();
    await expect(getSignInButton(page)).toContainText("Buy ticket");
  });

  test("member sees checkout validation and unavailable tickets in the ticket modal", async ({
    member1Page,
  }) => {
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.draft,
    );

    await waitForAttendanceState(member1Page);
    await expect(getAttendButton(member1Page)).toContainText("Buy ticket");

    await getAttendButton(member1Page).click();

    const ticketModal = getTicketModal(member1Page);
    await expect(ticketModal).toBeVisible();
    await expect(getCheckoutButton(member1Page)).toBeDisabled();
    await expect(getCheckoutButton(member1Page)).toHaveAttribute(
      "title",
      "Choose a ticket to continue.",
    );
    await expect(
      ticketModal
        .locator("label", { hasText: "Backstage pass" })
        .locator('[data-attendance-role="ticket-type-option"]'),
    ).toBeDisabled();

    await ticketModal.locator('[data-attendance-role="ticket-modal-cancel"]').click();

    await expect(ticketModal).toBeHidden();
    await expect(getLeaveButton(member1Page)).toBeHidden();
    await expect(getAttendButton(member1Page)).toContainText("Buy ticket");
  });

  test("member can complete a free ticket checkout without a discount code", async ({
    member2Page,
  }) => {
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.draft,
    );

    await waitForAttendanceState(member2Page);
    await getAttendButton(member2Page).click();

    const ticketModal = getTicketModal(member2Page);
    await expect(ticketModal).toBeVisible();
    await ticketModal.locator("label", { hasText: "Community ticket" }).click();

    const checkoutRequest = member2Page.waitForRequest(
      (request) =>
        request.method() === "POST" &&
        request.url().includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`),
    );
    const checkoutResponse = member2Page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`) &&
        response.ok(),
    );

    await getCheckoutButton(member2Page).click();

    const [request] = await Promise.all([checkoutRequest, checkoutResponse]);
    const postData = request.postData() ?? "";

    expect(postData).not.toContain("discount_code=");
    await expect(member2Page).toHaveURL(
      new RegExp(TEST_PAYMENT_EVENT_SLUGS.draft),
    );
    await expect(getLeaveButton(member2Page)).toContainText("Cancel attendance");
    await expect(member2Page.locator(".swal2-popup")).toContainText(
      "You have successfully registered for this event.",
    );

    await cancelAttendance(member2Page, TEST_PAYMENT_EVENT_IDS.draft);
  });

  test("member trims the discount code before a free ticket checkout", async ({
    pending1Page,
  }) => {
    await navigateToEvent(
      pending1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.draft,
    );

    await waitForAttendanceState(pending1Page);
    await getAttendButton(pending1Page).click();

    const ticketModal = getTicketModal(pending1Page);
    await expect(ticketModal).toBeVisible();
    await ticketModal.locator("label", { hasText: "Community ticket" }).click();
    await ticketModal
      .locator('[data-attendance-role="discount-code-input"]')
      .fill("  SAVE10  ");

    const checkoutRequest = pending1Page.waitForRequest(
      (request) =>
        request.method() === "POST" &&
        request.url().includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`),
    );
    const checkoutResponse = pending1Page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`) &&
        response.ok(),
    );

    await getCheckoutButton(pending1Page).click();

    const [request] = await Promise.all([checkoutRequest, checkoutResponse]);
    const postData = request.postData() ?? "";

    expect(postData).toContain("discount_code=SAVE10");
    expect(postData).not.toContain("discount_code=%20%20SAVE10%20%20");
    await expect(getLeaveButton(pending1Page)).toContainText("Cancel attendance");

    await cancelAttendance(pending1Page, TEST_PAYMENT_EVENT_IDS.draft);
  });

  test("member sees an error for expired discount codes during checkout", async ({
    member1Page,
  }) => {
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.draft,
    );

    await waitForAttendanceState(member1Page);
    await getAttendButton(member1Page).click();

    const ticketModal = getTicketModal(member1Page);
    await ticketModal.locator("label", { hasText: "Community ticket" }).click();
    await ticketModal
      .locator('[data-attendance-role="discount-code-input"]')
      .fill("EXPIRED15");

    await Promise.all([
      member1Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`) &&
          response.status() === 422,
      ),
      getCheckoutButton(member1Page).click(),
    ]);

    await expect(member1Page.locator(".swal2-popup")).toContainText(
      "discount code is not available",
    );
    await expect(ticketModal).toBeVisible();
  });

  test("member sees an error for unavailable discount codes during checkout", async ({
    member1Page,
  }) => {
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.draft,
    );

    await waitForAttendanceState(member1Page);
    await getAttendButton(member1Page).click();

    const ticketModal = getTicketModal(member1Page);
    await ticketModal.locator("label", { hasText: "Community ticket" }).click();
    await ticketModal
      .locator('[data-attendance-role="discount-code-input"]')
      .fill("LIMIT5");

    await Promise.all([
      member1Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`) &&
          response.status() === 422,
      ),
      getCheckoutButton(member1Page).click(),
    ]);

    await expect(member1Page.locator(".swal2-popup")).toContainText(
      "discount code is not available",
    );
    await expect(ticketModal).toBeVisible();
  });

  test("paid attendee sees a pending refund request on the event page", async ({
    member1Page,
  }) => {
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.refunds,
    );

    const refundButton = getRefundButton(member1Page);
    await expect(refundButton).toBeVisible();
    await expect(refundButton).toContainText("Refund requested");
    await expect(refundButton).toBeDisabled();
    await expect(getLeaveButton(member1Page)).toBeHidden();
  });

  test("paid attendee sees refund processing on the event page", async ({
    member2Page,
  }) => {
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.refunds,
    );

    const refundButton = getRefundButton(member2Page);
    await expect(refundButton).toBeVisible();
    await expect(refundButton).toContainText("Refund processing");
    await expect(refundButton).toBeDisabled();
    await expect(getLeaveButton(member2Page)).toBeHidden();
  });

  test("paid attendee sees refund unavailable when a request was rejected", async ({
    pending1Page,
  }) => {
    await navigateToEvent(
      pending1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.refunds,
    );

    const refundButton = getRefundButton(pending1Page);
    await expect(refundButton).toBeVisible();
    await expect(refundButton).toContainText("Refund unavailable");
    await expect(refundButton).toBeDisabled();
    await expect(getLeaveButton(pending1Page)).toBeHidden();
  });

  test("paid attendee can request a refund before the event starts", async ({
    pending2Page,
  }) => {
    await navigateToEvent(
      pending2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_PAYMENT_EVENT_SLUGS.refunds,
    );

    const refundButton = getRefundButton(pending2Page);
    await expect(refundButton).toBeVisible();
    await expect(refundButton).toContainText("Request refund");
    await expect(refundButton).toBeEnabled();
    await expect(getLeaveButton(pending2Page)).toBeHidden();

    await refundButton.click();
    const confirmButton = pending2Page.getByRole("button", { name: "Yes" });
    await expect(confirmButton).toBeVisible();

    await Promise.all([
      pending2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${TEST_PAYMENT_EVENT_IDS.refunds}/refund-request`) &&
          response.ok(),
      ),
      confirmButton.click(),
    ]);

    await expect(pending2Page.locator(".swal2-popup")).toContainText(
      "Your refund request has been sent to the organizers.",
    );
    await expect(refundButton).toContainText("Refund requested");
    await expect(refundButton).toBeDisabled();
  });
});
