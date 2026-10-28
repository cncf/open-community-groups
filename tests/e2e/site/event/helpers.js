import { expect } from "@playwright/test";

import { confirmAlert, dismissAlertIfPresent, getIntroSection, waitForActionResponses } from "../../utils.js";

// Shared prefix of the leave confirmations for attendance, waitlist and invitation requests.
const LEAVE_CONFIRMATION_MESSAGE = "Are you sure you want to";

/** Selects the public attendance controls container. */
export const getAttendanceContainer = (page) => page.locator("[data-attendance-container]").first();

/** Selects the public attend button. */
export const getAttendButton = (page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="attend-btn"]');

/** Selects the public leave button. */
export const getLeaveButton = (page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="leave-btn"]');

/** Waits until public attendance controls resolve to a stable state. */
export const waitForAttendanceState = async (page) => {
  const attendanceContainer = getAttendanceContainer(page);

  await expect(attendanceContainer).toHaveAttribute("data-attendance-ready", "true");
  await expect(attendanceContainer).toHaveAttribute("data-availability-hydrated", "true");
  await Promise.race([
    getAttendButton(page).waitFor({ state: "visible" }),
    getLeaveButton(page).waitFor({ state: "visible" }),
    attendanceContainer.locator('[data-attendance-role="refund-btn"]').waitFor({ state: "visible" }),
  ]);
};

/**
 * Cancels the current user's attendance, waitlist entry or invitation request from the event
 * page, then waits until the attend action is back.
 * @param {import("@playwright/test").Page} page - Playwright page showing the event.
 * @param {string} eventId - Event whose attendance is canceled.
 */
export const cancelAttendance = async (page, eventId) => {
  await dismissProfileCompletionPrompt(page);

  const leaveButton = getLeaveButton(page);
  await expect(leaveButton).toBeVisible();

  // Confirm the cancellation and wait for the leave request and the enrollment refresh.
  await waitForActionResponses(page, async () => {
    await leaveButton.click();
    await confirmAlert(page, { message: LEAVE_CONFIRMATION_MESSAGE });
  }, [
    { method: "DELETE", urlIncludes: `/event/${eventId}/leave` },
    { method: "GET", urlIncludes: `/event/${eventId}/enrollment` },
  ]);

  // Verify the attend action returns after cancellation.
  await waitForAttendanceState(page);
  await expect(getAttendButton(page)).toBeVisible();
};

/**
 * Closes the optional profile completion prompt shown after a successful attendance action.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @returns {Promise<boolean>} Whether the prompt was dismissed.
 */
export const dismissProfileCompletionPrompt = (page) =>
  dismissAlertIfPresent(page, { button: "Maybe later" });

/** Selects the checkout action inside the ticket modal. */
export const getCheckoutButton = (page) => page.locator('[data-attendance-role="checkout-btn"]');

/** Selects an event detail card from its heading. */
export const getEventInfoSection = (page, heading) =>
  page.getByText(heading, { exact: true }).locator("..").locator("..");

/** Selects the event about section. */
export const getEventAboutSection = (page) =>
  page.getByText("About this event", { exact: true }).locator("..");

/** Selects the event logo in the page intro. */
export const getEventLogo = (page) => getIntroSection(page).locator("img").first();

/** Selects the refund action shown to paid attendees. */
export const getRefundButton = (page) => page.locator('[data-attendance-role="refund-btn"]');

/** Selects the ticket selection modal. */
export const getTicketModal = (page) => page.locator('[data-attendance-role="ticket-modal"]');
