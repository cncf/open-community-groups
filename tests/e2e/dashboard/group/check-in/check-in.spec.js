import { expect, test } from "../../../fixtures.js";

import { queryE2eDatabase } from "../../../database.js";
import {
  TEST_COMMUNITY_TITLE,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_OPEN_CHECK_IN_EVENT,
  TEST_USER_IDS,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";

const CHECK_IN_CODE = "99999999-9999-9999-9999-999999999529";

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
  scannerTest("check-in manager scans an attendee credential", async ({ checkInManagerGroupPage }) => {
    // Replace the browser scanner with a deterministic camera implementation.
    await checkInManagerGroupPage.addInitScript(() => {
      class FakeQrScanner {
        static last;

        static async hasCamera() {
          return true;
        }

        static async listCameras() {
          return [{ id: "test-camera", label: "Test camera" }];
        }

        constructor(_video, onDecode) {
          this.onDecode = onDecode;
          FakeQrScanner.last = this;
        }

        destroy() {}
        async hasFlash() {
          return false;
        }
        isFlashOn() {
          return false;
        }
        async setCamera() {}
        async start() {}
        async toggleFlash() {}
      }

      window.__OCG_E2E_QR_SCANNER__ = FakeQrScanner;
    });

    // Open the scanner for the seeded check-in event.
    await navigateToPath(checkInManagerGroupPage, "/dashboard/group?tab=check-in");

    await expect(checkInManagerGroupPage.getByRole("heading", { name: "Check-In" })).toBeVisible();
    const eventCard = checkInManagerGroupPage.locator("[data-group-check-in-open]", {
      hasText: TEST_OPEN_CHECK_IN_EVENT.name,
    });
    await expect(eventCard).toBeVisible();
    await eventCard.click();

    const modal = checkInManagerGroupPage.locator("#group-check-in-scanner-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByText("Hold an attendee QR code inside the frame.")).toBeVisible();
    const muteToggle = modal.getByRole("checkbox", { name: "Mute sounds" });
    await muteToggle.check();
    await expect(muteToggle).toBeChecked();
    await expect(modal.getByRole("link", { name: "Manual check-in" })).toHaveAttribute(
      "href",
      "/dashboard/group?tab=events",
    );
    await expect(modal.getByRole("link", { name: "Manual check-in" })).toHaveAttribute(
      "data-attendees-url",
      `/dashboard/group/events/${TEST_OPEN_CHECK_IN_EVENT.id}/attendees`,
    );

    // Submit the attendee credential through the simulated camera.
    const responsePromise = checkInManagerGroupPage.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes(`/events/${TEST_OPEN_CHECK_IN_EVENT.id}/check-ins/scan`),
    );
    await checkInManagerGroupPage.evaluate(
      ({ checkInCode, eventId }) =>
        window.__OCG_E2E_QR_SCANNER__.last.onDecode({
          data: `ocg-check-in:v1:${eventId}:${checkInCode}`,
        }),
      { checkInCode: CHECK_IN_CODE, eventId: TEST_OPEN_CHECK_IN_EVENT.id },
    );
    expect((await responsePromise).ok()).toBe(true);

    // Verify the successful response is reflected in the scanner feedback.
    await expect(modal.getByText("Checked in", { exact: true })).toBeVisible();
    await expect(modal.getByText(/E2E Pending Two/u)).toBeVisible();
  });

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
    await expect(organizerGroupPage.locator("#group-selector-button")).toContainText(
      TEST_GROUP_NAMES.empty,
    );
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

  scannerTest(
    "check-in manager can manually check in the selected event on mobile @mobile",
    async ({ checkInManagerGroupPage }) => {
      // Open the selected event's scanner on the mobile check-in surface.
      await navigateToPath(checkInManagerGroupPage, "/dashboard/group?tab=check-in");
      await checkInManagerGroupPage
        .locator("[data-group-check-in-open]", {
          hasText: TEST_OPEN_CHECK_IN_EVENT.name,
        })
        .click();
      const modal = checkInManagerGroupPage.locator("#group-check-in-scanner-modal");

      // Load the selected attendee table without leaving the mobile surface.
      const attendeesResponse = checkInManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/events/${TEST_OPEN_CHECK_IN_EVENT.id}/attendees`),
      );
      await modal.getByRole("link", { name: "Manual check-in" }).click();
      expect((await attendeesResponse).ok()).toBe(true);
      const manualPanel = checkInManagerGroupPage.locator("[data-group-check-in-manual-panel]");
      await expect(manualPanel).toBeVisible();
      await expect(manualPanel.getByRole("table", { name: "Attendees list" })).toBeVisible();

      // Use the existing manual toggle, then return to the same event card.
      const attendeeRow = manualPanel.locator("tr", {
        hasText: "E2E Pending Two",
      });
      const toggle = attendeeRow.getByRole("checkbox", {
        name: "Check in attendee",
      });
      await waitForActionResponse(checkInManagerGroupPage, () => attendeeRow.locator("label").click(), {
        method: "POST",
        urlIncludes: `/dashboard/group/events/${TEST_OPEN_CHECK_IN_EVENT.id}/attendees/${TEST_USER_IDS.pending2}/check-in`,
      });
      await expect(toggle).toBeChecked();
      await manualPanel.getByRole("button", { name: "Back to check-in events" }).click();
      await expect(
        checkInManagerGroupPage.locator("[data-group-check-in-open]", {
          hasText: TEST_OPEN_CHECK_IN_EVENT.name,
        }),
      ).toBeFocused();
    },
  );
});
