import { expect } from "@playwright/test";

import { TEST_COMMUNITY_NAME, TEST_EVENT_IDS, TEST_GROUP_SLUGS } from "../../seed.js";
import { getIntroSection, navigateToEvent, navigateToPath, waitForActionResponse } from "../../utils.js";

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

/** Selects an event detail card from its heading. */
export const getEventInfoSection = (page, heading) =>
  page.getByText(heading, { exact: true }).locator("..").locator("..");

/** Selects the event about section. */
export const getEventAboutSection = (page) =>
  page.getByText("About this event", { exact: true }).locator("..");

/** Selects the event logo in the page intro. */
export const getEventLogo = (page) => getIntroSection(page).locator("img").first();

/** Declines a pending offer for the shared waitlist lab event. */
const clearSeededWaitlistOffer = async (memberPage) => {
  await navigateToPath(memberPage, "/dashboard/user?tab=invitations");
  const offerRow = memberPage.locator("#dashboard-content tr", {
    hasText: "Full Event With Waitlist",
  });
  const actionsButton = offerRow.getByLabel(/Open offer actions/);

  if (!(await actionsButton.isVisible())) {
    return;
  }

  await actionsButton.click();
  const declineButton = offerRow.getByRole("menuitem", {
    name: "Decline offer",
    exact: true,
  });
  await declineButton.click();
  await expect(memberPage.getByRole("button", { name: "Yes" })).toBeVisible();
  await waitForActionResponse(memberPage, () => memberPage.getByRole("button", { name: "Yes" }).click(), {
    method: "PUT",
    urlIncludes: "/dashboard/user/invitations/event-offers/",
    urlEndsWith: "/decline",
  });
};

/** Restores the shared waitlist lab event to its seeded full-event state. */
export const restoreSeededWaitlistEvent = async (memberPage, organizerPage) => {
  if (memberPage.isClosed() || organizerPage.isClosed()) {
    return;
  }

  // Release any offer left behind by an interrupted promotion flow.
  await clearSeededWaitlistOffer(memberPage);

  // Remove member2 from the shared waitlist event before depending on capacity.
  await navigateToEvent(
    memberPage,
    TEST_COMMUNITY_NAME,
    TEST_GROUP_SLUGS.community1.alpha,
    "alpha-waitlist-lab",
  );
  await waitForAttendanceState(memberPage);

  if (await getLeaveButton(memberPage).isVisible()) {
    await getLeaveButton(memberPage).click();
    await expect(memberPage.getByRole("button", { name: "Yes" })).toBeVisible();
    await waitForActionResponse(memberPage, () => memberPage.getByRole("button", { name: "Yes" }).click(), {
      method: "DELETE",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`,
    });
  }

  // Restore organizer attendance so the one-seat event is full again.
  await navigateToEvent(
    organizerPage,
    TEST_COMMUNITY_NAME,
    TEST_GROUP_SLUGS.community1.alpha,
    "alpha-waitlist-lab",
  );
  await waitForAttendanceState(organizerPage);

  if (await getAttendButton(organizerPage).isVisible()) {
    await expect(getAttendButton(organizerPage)).toContainText("Attend event");
    await waitForActionResponse(organizerPage, () => getAttendButton(organizerPage).click(), {
      method: "POST",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`,
    });
    await expect(getLeaveButton(organizerPage)).toContainText("Cancel attendance");
  }
};
