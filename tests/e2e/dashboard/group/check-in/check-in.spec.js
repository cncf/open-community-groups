import { randomUUID } from "node:crypto";

import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase, queryScalar } from "../../../database.js";
import {
  TEST_COMMUNITY_TITLE,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_OPEN_CHECK_IN_EVENT,
  TEST_USER_IDS,
} from "../../../seed.js";
import { navigateToPath, waitForActionResponse } from "../../../utils.js";
import { installFakeQrScanner } from "./helpers.js";

const CHECK_IN_CODE = "99999999-9999-9999-9999-999999999529";

const SCAN_PATHNAME = `/dashboard/group/events/${TEST_OPEN_CHECK_IN_EVENT.id}/check-ins/scan`;

const USER_CHECK_IN_PATH = "/dashboard/user?tab=check-in";

const scannerTest = test.extend({
  scannerAttendeeState: [
    async ({}, use) => {
      resetScannerAttendee();
      try {
        await use();
      } finally {
        resetScannerAttendee();
      }
    },
    { auto: true },
  ],
});

test.describe("group dashboard check-in", () => {
  scannerTest(
    "check-in manager scans an attendee credential and handles a duplicate",
    async ({ checkInManagerGroupPage, pending2Page }) => {
      // Verify the attendee still has a pending credential card before the scan.
      await navigateToPath(pending2Page, USER_CHECK_IN_PATH);
      const attendeeCard = pending2Page.locator("[data-user-check-in-open]", {
        hasText: TEST_OPEN_CHECK_IN_EVENT.name,
      });
      await expect(attendeeCard).toBeVisible();

      await verifyScannerCredentialFlow({ checkInManagerGroupPage });

      // Verify the checked-in attendee no longer sees the credential card.
      await navigateToPath(pending2Page, USER_CHECK_IN_PATH);
      await expect(pending2Page.getByRole("heading", { name: "Check-In" })).toBeVisible();
      await expect(attendeeCard).toHaveCount(0);
    },
  );

  scannerTest(
    "check-in manager scans an attendee credential and handles a duplicate @mobile",
    async ({ checkInManagerGroupPage }) => {
      await verifyScannerCredentialFlow({ checkInManagerGroupPage });
    },
  );

  scannerTest(
    "check-in manager sees an unrecognized credential rejection",
    async ({ checkInManagerGroupPage }) => {
      // Open the scanner for the seeded check-in event.
      const { modal } = await openScanner(checkInManagerGroupPage);

      // Submit a well-formed credential whose code belongs to no attendee.
      await submitScannedCredential(checkInManagerGroupPage, { checkInCode: randomUUID(), status: 422 });

      // Verify the server rejection is shown and nobody was checked in.
      await expect(
        modal.getByText("This check-in credential is not recognized.", { exact: true }),
      ).toBeVisible();
      await expect(modal.getByText("Checked in", { exact: true })).toHaveCount(0);
      expect(
        queryScalar(`
          select checked_in
          from event_attendee
          where event_id = '${TEST_OPEN_CHECK_IN_EVENT.id}'
          and user_id = '${TEST_USER_IDS.pending2}'
        `),
      ).toBe("f");
    },
  );

  test("organizer switches mobile check-in to another manageable group @mobile", async ({
    organizerGroupPage,
  }) => {
    // Load the mobile check-in surface and open the dashboard menu drawer.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=check-in");
    await organizerGroupPage.getByRole("button", { name: "Open dashboard menu" }).click();
    const drawer = organizerGroupPage.locator("#dashboard-menu-drawer");
    await expect(drawer).toBeVisible();
    const communityButton = drawer.locator("#community-selector-button");
    const groupButton = drawer.locator("#group-selector-button");
    await expect(communityButton).toBeVisible();
    await expect(communityButton).toContainText(TEST_COMMUNITY_TITLE);
    await expect(groupButton).toBeVisible();
    await expect(groupButton).toContainText(TEST_GROUP_NAMES.alpha);

    // Open each selector and verify focus follows the drawer selectors.
    await communityButton.click();
    const communitySearch = drawer.locator("#community-search-input");
    await expect(communitySearch).toBeFocused();
    await communitySearch.press("Escape");
    await expect(drawer).toBeVisible();
    await groupButton.click();
    const groupSearch = drawer.locator("#group-search-input");
    await expect(groupSearch).toBeFocused();

    // Switch to another manageable group without leaving the Check-In URL.
    const emptyGroup = drawer.locator(`#group-option-${TEST_GROUP_IDS.community1.empty}`);
    await expect(emptyGroup).toContainText(TEST_GROUP_NAMES.empty);
    await waitForActionResponse(organizerGroupPage, () => emptyGroup.click(), {
      method: "PUT",
      urlEndsWith: `/dashboard/group/${TEST_GROUP_IDS.community1.empty}/select`,
    });

    // Verify the refreshed scanner list belongs to the newly selected group.
    await expect(organizerGroupPage).toHaveURL(/\/dashboard\/group\?tab=check-in$/u);
    await expect(
      organizerGroupPage.getByRole("heading", { name: "No events available for check-in" }),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator("[data-group-check-in-open]", {
        hasText: TEST_OPEN_CHECK_IN_EVENT.name,
      }),
    ).toHaveCount(0);

    // Reopen the drawer and verify it reflects the newly selected group.
    await organizerGroupPage.getByRole("button", { name: "Open dashboard menu" }).click();
    await expect(organizerGroupPage.locator("#group-selector-button")).toContainText(TEST_GROUP_NAMES.empty);
  });

  test("organizer recovers mobile check-in after selecting a read-only group @mobile", async ({
    organizerGroupPage,
  }) => {
    // Load Check-In and select the organizer's read-only group from the drawer.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=check-in");
    await organizerGroupPage.getByRole("button", { name: "Open dashboard menu" }).click();
    const drawer = organizerGroupPage.locator("#dashboard-menu-drawer");
    await drawer.locator("#group-selector-button").click();
    const readOnlyGroup = drawer.locator(`#group-option-${TEST_GROUP_IDS.community1.gamma}`);
    await expect(readOnlyGroup).toContainText(TEST_GROUP_NAMES.gamma);
    await waitForActionResponse(organizerGroupPage, () => readOnlyGroup.click(), {
      method: "PUT",
      urlEndsWith: `/dashboard/group/${TEST_GROUP_IDS.community1.gamma}/select`,
    });

    // Verify the fallback keeps the Check-In URL and explains the permission problem.
    await expect(organizerGroupPage).toHaveURL(/\/dashboard\/group\?tab=check-in$/u);
    const fallbackWarning = organizerGroupPage.getByText(
      "You cannot manage check-ins for the selected group.",
      { exact: true },
    );
    await expect(fallbackWarning).toBeVisible();

    // Switch back to the manageable group from the drawer.
    await organizerGroupPage.getByRole("button", { name: "Open dashboard menu" }).click();
    await drawer.locator("#group-selector-button").click();
    await expect(drawer.locator("#group-search-input")).toBeFocused();
    const manageableGroup = drawer.locator(`#group-option-${TEST_GROUP_IDS.community1.alpha}`);
    await waitForActionResponse(organizerGroupPage, () => manageableGroup.click(), {
      method: "PUT",
      urlEndsWith: `/dashboard/group/${TEST_GROUP_IDS.community1.alpha}/select`,
    });

    // Verify the same URL reopens Check-In for the restored group.
    await expect(organizerGroupPage).toHaveURL(/\/dashboard\/group\?tab=check-in$/u);
    await expect(fallbackWarning).toHaveCount(0);
    await expect(organizerGroupPage.getByRole("heading", { name: "Check-In" })).toBeVisible();
    await expect(
      organizerGroupPage.locator("[data-group-check-in-open]", {
        hasText: TEST_OPEN_CHECK_IN_EVENT.name,
      }),
    ).toBeVisible();
  });
});

/** Installs the fake camera, then opens the scanner modal for the seeded check-in event. */
const openScanner = async (page) => {
  // Replace the browser scanner with a deterministic camera implementation.
  await installFakeQrScanner(page);

  // Open the scanner for the seeded check-in event.
  await navigateToPath(page, "/dashboard/group?tab=check-in");

  await expect(page.getByRole("heading", { name: "Check-In" })).toBeVisible();
  const eventCard = page.locator("[data-group-check-in-open]", {
    hasText: TEST_OPEN_CHECK_IN_EVENT.name,
  });
  await expect(eventCard).toBeVisible();
  await eventCard.click();

  const modal = page.locator("#group-check-in-scanner-modal");
  await expect(modal).toBeVisible();
  await expect(modal.getByText("Hold an attendee QR code inside the frame.")).toBeVisible();

  return { eventCard, modal };
};

/** Resets the scanner event_attendee row to a confirmed state. */
const resetScannerAttendee = () => {
  queryE2eDatabase(`
    update event_attendee
    set
      check_in_code = '${CHECK_IN_CODE}',
      checked_in = false,
      checked_in_at = null,
      status = 'confirmed'
    where event_id = '${TEST_OPEN_CHECK_IN_EVENT.id}'
    and user_id = '${TEST_USER_IDS.pending2}'
  `);
};

/** Decodes a credential through the simulated camera and waits for the scan response. */
const submitScannedCredential = (page, { checkInCode = CHECK_IN_CODE, status = 200 } = {}) =>
  waitForActionResponse(
    page,
    () =>
      page.evaluate(
        ({ checkInCode, eventId }) =>
          window.__OCG_E2E_QR_SCANNER__.last.onDecode({
            data: `ocg-check-in:v1:${eventId}:${checkInCode}`,
          }),
        { checkInCode, eventId: TEST_OPEN_CHECK_IN_EVENT.id },
      ),
    { method: "POST", pathname: SCAN_PATHNAME, status },
  );

/** Verifies scanner check-in success and duplicate credential handling. */
const verifyScannerCredentialFlow = async ({ checkInManagerGroupPage }) => {
  // Open the scanner with the simulated camera.
  const { eventCard, modal } = await openScanner(checkInManagerGroupPage);
  const muteToggle = modal.getByRole("checkbox", { name: "Mute sounds" });
  await expect(muteToggle).not.toBeChecked();
  await expect(modal.getByRole("link", { name: "Manual check-in" })).toHaveCount(0);

  // Submit the attendee credential through the simulated camera.
  await submitScannedCredential(checkInManagerGroupPage);

  // Verify the successful response is reflected in the scanner feedback.
  await expect(modal.getByText("Checked in", { exact: true })).toBeVisible();
  await expect(modal.getByText(/E2E Pending Two/u)).toBeVisible();

  // Reopen the scanner and submit the same credential again.
  await modal.getByRole("button", { name: "Close", exact: true }).click();
  await expect(modal).toBeHidden();
  await eventCard.click();
  await expect(modal).toBeVisible();
  await submitScannedCredential(checkInManagerGroupPage);

  // Verify duplicate scans produce the durable already-checked-in outcome.
  await expect(modal.getByText("Already checked in", { exact: true })).toBeVisible();
  await expect(modal.getByText(/E2E Pending Two/u)).toBeVisible();
};
