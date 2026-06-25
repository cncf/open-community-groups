import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUGS,
  TEST_REGISTRATION_WINDOW_EVENTS,
  getAttendanceContainer,
  getAttendButton,
  navigateToEvent,
  waitForAttendanceState,
} from "../../utils.js";

// Return the checkout action inside the ticket modal.
const getCheckoutButton = (page) =>
  page.locator('[data-attendance-role="checkout-btn"]');

// Return the discount code field inside the ticket modal.
const getDiscountCodeInput = (page) =>
  page.locator('[data-attendance-role="discount-code-input"]');

// Return the ticket selection modal.
const getTicketModal = (page) =>
  page.locator('[data-attendance-role="ticket-modal"]');

// Return the first ticket type option in the modal.
const getTicketOption = (page) =>
  page.locator('[data-attendance-role="ticket-type-option"]').first();

// Load a seeded registration-window event and wait for attendance controls.
const navigateToRegistrationWindowEvent = async (page, event) => {
  await navigateToEvent(
    page,
    TEST_COMMUNITY_NAME,
    TEST_GROUP_SLUGS.community1.alpha,
    event.slug,
  );

  await expect(
    page.getByRole("heading", { level: 1, name: event.name }),
  ).toBeVisible();
  await waitForAttendanceState(page);
};

// Assert the durable registration-window state rendered by the event page.
const expectRegistrationWindowState = async (page, open, messagePattern) => {
  const container = getAttendanceContainer(page);

  await expect(container).toHaveAttribute(
    "data-registration-window-open",
    String(open),
  );
  await expect(container).toHaveAttribute(
    "data-registration-window-message",
    messagePattern,
  );
};

test.describe("event registration windows", () => {
  test("ticketed events disable checkout until registration opens", async ({
    member2Page,
  }) => {
    // Load the ticketed event before its registration window opens.
    await navigateToRegistrationWindowEvent(
      member2Page,
      TEST_REGISTRATION_WINDOW_EVENTS.ticketedFuture,
    );

    // Verify registration-window state blocks ticket checkout controls.
    await expectRegistrationWindowState(
      member2Page,
      false,
      /Registration opens/,
    );
    await expect(getAttendButton(member2Page)).toContainText("Buy ticket");
    await expect(getAttendButton(member2Page)).toBeDisabled();
    await expect(getTicketOption(member2Page)).toBeDisabled();
    await expect(getDiscountCodeInput(member2Page)).toBeDisabled();
    await expect(getCheckoutButton(member2Page)).toBeDisabled();
  });

  test("ticketed events disable checkout after registration closes", async ({
    member2Page,
  }) => {
    // Load the ticketed event after its registration window closes.
    await navigateToRegistrationWindowEvent(
      member2Page,
      TEST_REGISTRATION_WINDOW_EVENTS.ticketedClosed,
    );

    // Verify closed registration blocks ticket checkout controls.
    await expectRegistrationWindowState(
      member2Page,
      false,
      /Registration closed/,
    );
    await expect(getAttendButton(member2Page)).toContainText("Buy ticket");
    await expect(getAttendButton(member2Page)).toBeDisabled();
    await expect(getTicketOption(member2Page)).toBeDisabled();
    await expect(getDiscountCodeInput(member2Page)).toBeDisabled();
    await expect(getCheckoutButton(member2Page)).toBeDisabled();
  });

  test("ticketed events allow checkout controls while registration is open", async ({
    member2Page,
  }) => {
    // Load the ticketed event while registration is open.
    await navigateToRegistrationWindowEvent(
      member2Page,
      TEST_REGISTRATION_WINDOW_EVENTS.ticketedOpen,
    );

    // Verify the ticket purchase action is available.
    await expectRegistrationWindowState(
      member2Page,
      true,
      /Registration is open until/,
    );
    await expect(getAttendButton(member2Page)).toContainText("Buy ticket");
    await expect(getAttendButton(member2Page)).toBeEnabled();

    // Open the ticket modal and verify checkout waits for a ticket selection.
    await getAttendButton(member2Page).click();
    await expect(getTicketModal(member2Page)).toBeVisible();
    await expect(getTicketOption(member2Page)).toBeEnabled();
    await expect(getDiscountCodeInput(member2Page)).toBeEnabled();
    await expect(getCheckoutButton(member2Page)).toBeDisabled();

    // Select a ticket and verify checkout becomes available.
    await getTicketModal(member2Page)
      .locator("label", { hasText: "Registration window pass" })
      .click();
    await expect(getCheckoutButton(member2Page)).toBeEnabled();

    // Close the ticket modal without creating a checkout.
    await getTicketModal(member2Page)
      .locator('[data-attendance-role="ticket-modal-cancel"]')
      .click();
    await expect(getTicketModal(member2Page)).toBeHidden();
  });

  test("free registration actions respect closed and close-only windows", async ({
    member2Page,
  }) => {
    // Load the free event after its registration window closes.
    await navigateToRegistrationWindowEvent(
      member2Page,
      TEST_REGISTRATION_WINDOW_EVENTS.freeClosed,
    );

    // Verify a closed registration window disables attendance.
    await expectRegistrationWindowState(
      member2Page,
      false,
      /Registration closed/,
    );
    await expect(getAttendButton(member2Page)).toContainText("Attend event");
    await expect(getAttendButton(member2Page)).toBeDisabled();

    // Load the free event with only a future registration close date.
    await navigateToRegistrationWindowEvent(
      member2Page,
      TEST_REGISTRATION_WINDOW_EVENTS.closeOnlyOpen,
    );

    // Verify close-only registration allows attendance before it closes.
    await expectRegistrationWindowState(
      member2Page,
      true,
      /Registration is open until/,
    );
    await expect(getAttendButton(member2Page)).toContainText("Attend event");
    await expect(getAttendButton(member2Page)).toBeEnabled();

    // Load the free event after its implicit event-start close.
    await navigateToRegistrationWindowEvent(
      member2Page,
      TEST_REGISTRATION_WINDOW_EVENTS.openOnlyClosed,
    );

    // Verify open-only registration closes when the event starts.
    await expectRegistrationWindowState(
      member2Page,
      false,
      /Registration closed/,
    );
    await expect(getAttendButton(member2Page)).toContainText("Attend event");
    await expect(getAttendButton(member2Page)).toBeDisabled();
  });

  test("approval and waitlist actions remain blocked when registration is closed", async ({
    member2Page,
  }) => {
    // Load the approval-required event after registration closes.
    await navigateToRegistrationWindowEvent(
      member2Page,
      TEST_REGISTRATION_WINDOW_EVENTS.approvalClosed,
    );

    // Verify invitation requests are blocked by the closed window.
    await expectRegistrationWindowState(
      member2Page,
      false,
      /Registration closed/,
    );
    await expect(getAttendButton(member2Page)).toContainText(
      "Request invitation",
    );
    await expect(getAttendButton(member2Page)).toBeDisabled();

    // Load the waitlist event after registration closes.
    await navigateToRegistrationWindowEvent(
      member2Page,
      TEST_REGISTRATION_WINDOW_EVENTS.waitlistClosed,
    );

    // Verify waitlist registration remains blocked while waitlist is enabled.
    await expectRegistrationWindowState(
      member2Page,
      false,
      /Registration closed/,
    );
    await expect(getAttendanceContainer(member2Page)).toHaveAttribute(
      "data-waitlist-enabled",
      "true",
    );
    await expect(getAttendButton(member2Page)).toBeDisabled();
  });
});
