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
import { installFakeQrScanner, installFakeWakeLock } from "./helpers.js";

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

    // Verify the context button follows the selection.
    const groupContext = organizerGroupPage.locator("[data-group-context]");
    await expect(groupContext).toHaveAttribute("data-group-context", TEST_GROUP_NAMES.empty);
    await expect(groupContext).toHaveAttribute("data-community-context", TEST_COMMUNITY_TITLE);

    // Reopen the drawer from the context button and verify it reflects the newly selected group.
    await groupContext.click();
    await expect(groupContext).toHaveAttribute("aria-expanded", "true");
    await expect(organizerGroupPage.locator("#group-selector-button")).toContainText(TEST_GROUP_NAMES.empty);
  });

  test("group selectors reach 44px in the drawer @mobile", async ({ organizerGroupPage }) => {
    // Open the group selector in the drawer.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=check-in");
    await organizerGroupPage.getByRole("button", { name: "Open dashboard menu" }).click();
    const drawer = organizerGroupPage.locator("#dashboard-menu-drawer");
    const groupButton = drawer.locator("#group-selector-button");
    await groupButton.click();
    const option = drawer.locator(`#group-option-${TEST_GROUP_IDS.community1.empty}`);
    await expect(option).toBeVisible();

    // Verify the trigger and option sizes, and that the list opens below the trigger.
    const buttonBounds = await groupButton.boundingBox();
    expect(buttonBounds.height).toBeGreaterThanOrEqual(44);
    expect((await option.boundingBox()).height).toBeGreaterThanOrEqual(44);
    const searchBounds = await drawer.locator("#group-search-input").boundingBox();
    expect(searchBounds.y).toBeGreaterThanOrEqual(buttonBounds.y + buttonBounds.height);
  });

  test("group line names the selected group above the list @mobile", async ({ organizerGroupPage }) => {
    // Load Check-In for the selected group.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=check-in");
    const line = organizerGroupPage.locator("[data-group-context]");
    await expect(line).toBeVisible();

    // Verify the text comes from the pseudo-element, so no text node reaches desktop locators.
    await expect(line).toHaveText("");
    expect(await line.evaluate((element) => getComputedStyle(element, "::before").content)).toBe(
      `"Group Dashboard · ${TEST_GROUP_NAMES.alpha}"`,
    );

    // Verify the line sits above the title.
    const lineBounds = await line.boundingBox();
    const titleBounds = await organizerGroupPage.getByRole("heading", { name: "Check-In" }).boundingBox();
    expect(lineBounds.y + lineBounds.height).toBeLessThanOrEqual(titleBounds.y);

    // Verify a long name wraps, so groups with a shared prefix stay apart.
    await line.evaluate((element) => {
      element.dataset.groupContext = `Group Dashboard · ${"Cloud Native Community ".repeat(4)}Chapter`;
    });
    expect(await line.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);
    expect((await line.boundingBox()).height).toBeGreaterThan(lineBounds.height);
  });

  test("event card keeps the scan button on its own line at 320px @mobile", async ({
    checkInManagerGroupPage,
  }) => {
    // Load the event card on the narrowest supported phone.
    await checkInManagerGroupPage.setViewportSize({ height: 568, width: 320 });
    await navigateToPath(checkInManagerGroupPage, "/dashboard/group?tab=check-in");
    const scanButton = checkInManagerGroupPage.locator("[data-group-check-in-open]", {
      hasText: TEST_OPEN_CHECK_IN_EVENT.name,
    });
    const card = checkInManagerGroupPage.locator("[data-group-check-in-card]").filter({ has: scanButton });
    await expect(scanButton).toBeVisible();

    // Verify the button spans the card at the 44px target, below the date box.
    const cardBounds = await card.boundingBox();
    const buttonBounds = await scanButton.boundingBox();
    const dateBounds = await card.locator(".icon-date").boundingBox();
    expect(buttonBounds.height).toBe(44);
    expect(Math.abs(buttonBounds.x - cardBounds.x - 13)).toBeLessThanOrEqual(1);
    expect(
      Math.abs(cardBounds.x + cardBounds.width - buttonBounds.x - buttonBounds.width - 13),
    ).toBeLessThanOrEqual(1);
    expect(buttonBounds.y).toBeGreaterThanOrEqual(dateBounds.y + dateBounds.height);

    // Verify the location and date lines wrap instead of cutting off the time.
    const lines = card.locator(".text-\\[0\\.825rem\\]");
    await expect(lines).toHaveCount(2);
    for (const line of await lines.all()) {
      expect(await line.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);
    }
  });

  scannerTest(
    "scanner fills a phone and hides a single camera @mobile",
    async ({ checkInManagerGroupPage }) => {
      // Open the scanner on a phone with one camera.
      const { modal } = await openScanner(checkInManagerGroupPage);
      const viewport = checkInManagerGroupPage.viewportSize();

      // Verify the card covers the screen and the footer Close stays.
      expect(await modal.locator(".modal-card").boundingBox()).toEqual({
        height: viewport.height,
        width: viewport.width,
        x: 0,
        y: 0,
      });
      await expect(modal.locator("footer").getByRole("button", { name: "Close", exact: true })).toBeVisible();

      // Verify the header close and the mute switch reach the 44px target.
      const closeBounds = await modal.getByRole("button", { name: "Close modal" }).boundingBox();
      expect(closeBounds.width).toBe(44);
      expect(closeBounds.height).toBe(44);
      const muteLabel = modal.locator("label:has([data-group-check-in-mute])");
      expect((await muteLabel.boundingBox()).height).toBeGreaterThanOrEqual(44);

      // Verify the only camera offers no choice, and the frame stays centred on the video.
      await expect(modal.getByLabel("Camera")).toBeHidden();
      const video = await modal.locator("[data-group-check-in-video]").boundingBox();
      const frame = await modal.locator(".border-white\\/70").boundingBox();
      expect(Math.abs(frame.x + frame.width / 2 - (video.x + video.width / 2))).toBeLessThanOrEqual(1);
      expect(Math.abs(frame.y + frame.height / 2 - (video.y + video.height / 2))).toBeLessThanOrEqual(1);
    },
  );

  scannerTest("scanner offers the select with two cameras @mobile", async ({ checkInManagerGroupPage }) => {
    // Open the scanner on a phone with two cameras.
    const { modal } = await openScanner(checkInManagerGroupPage, {
      cameras: [
        { id: "back", label: "Back camera" },
        { id: "front", label: "Front camera" },
      ],
    });

    // Verify the select sits on its own row with a 44px target.
    const select = modal.getByLabel("Camera");
    await expect(select).toBeEnabled();
    await expect(select).toBeVisible();
    expect((await select.boundingBox()).height).toBeGreaterThanOrEqual(44);
  });

  scannerTest("scanner stays a modal at 640px and wider @mobile", async ({ checkInManagerGroupPage }) => {
    // Open the scanner at a landscape width above the full-screen range.
    await checkInManagerGroupPage.setViewportSize({ height: 360, width: 700 });
    const { modal } = await openScanner(checkInManagerGroupPage);

    // Verify the card keeps its modal width and leaves a margin.
    const card = await modal.locator(".modal-card").boundingBox();
    expect(card.width).toBeLessThan(700);
    expect(card.x).toBeGreaterThan(0);

    // Verify the camera select stays available, as on desktop.
    await expect(modal.getByLabel("Camera")).toBeVisible();
  });

  for (const viewport of [
    { height: 320, width: 568 },
    { height: 360, width: 640 },
    { height: 375, width: 667 },
    { height: 360, width: 740 },
  ]) {
    scannerTest(
      `scanner shows the whole camera view on open at ${viewport.width}x${viewport.height} @mobile`,
      async ({ checkInManagerGroupPage }) => {
        // Open the scanner on a short landscape screen with two cameras.
        await checkInManagerGroupPage.setViewportSize(viewport);
        const { modal } = await openScanner(checkInManagerGroupPage, {
          cameras: [
            { id: "back", label: "Back camera" },
            { id: "front", label: "Front camera" },
          ],
        });
        const card = modal.locator(".modal-card");
        const video = modal.locator("[data-group-check-in-video]");
        const closeButton = modal.getByRole("button", { name: "Close modal" });

        // Verify the whole camera view shows under the head, with nothing scrolled.
        expect(await card.evaluate((element) => element.scrollTop)).toBe(0);
        const closeBounds = await closeButton.boundingBox();
        const cardBounds = await card.boundingBox();
        const videoBounds = await video.boundingBox();
        expect(videoBounds.y).toBeGreaterThanOrEqual(closeBounds.y + closeBounds.height);
        expect(videoBounds.y + videoBounds.height).toBeLessThanOrEqual(cardBounds.y + cardBounds.height);
        expect(cardBounds.y + cardBounds.height).toBeLessThanOrEqual(viewport.height);
        expect(videoBounds.height).toBeGreaterThanOrEqual(240);

        // Verify the frame stays a centred square inside the video.
        const frame = await modal.locator(".border-white\\/70").boundingBox();
        expect(frame.width).toBeCloseTo(frame.height, 0);
        expect(
          Math.abs(frame.x + frame.width / 2 - (videoBounds.x + videoBounds.width / 2)),
        ).toBeLessThanOrEqual(1);
        expect(
          Math.abs(frame.y + frame.height / 2 - (videoBounds.y + videoBounds.height / 2)),
        ).toBeLessThanOrEqual(1);

        // Verify the event line and status show beside the video, with no sideways scroll.
        const eventName = modal.locator("#group-check-in-event-name");
        await expect(eventName).toBeInViewport({ ratio: 1 });
        await expect(modal.locator("#group-check-in-event-date")).toBeInViewport({ ratio: 1 });
        await expect(modal.getByText("Hold an attendee QR code inside the frame.")).toBeInViewport({
          ratio: 1,
        });
        expect((await eventName.boundingBox()).x).toBeGreaterThanOrEqual(videoBounds.x + videoBounds.width);
        expect(await card.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);

        // Verify each control is reachable while the video and the head stay in place.
        for (const control of [
          modal.getByLabel("Camera"),
          modal.locator("label:has([data-group-check-in-mute])"),
          modal.locator("footer").getByRole("button", { name: "Close", exact: true }),
        ]) {
          await control.scrollIntoViewIfNeeded();
          await expect(control).toBeInViewport({ ratio: 1 });
          expect((await control.boundingBox()).y).toBeGreaterThanOrEqual(closeBounds.y + closeBounds.height);
          expect(await video.boundingBox()).toEqual(videoBounds);
          await expect(closeButton).toBeInViewport({ ratio: 1 });
        }
      },
    );
  }

  for (const viewport of [
    { height: 480, width: 500 },
    { height: 590, width: 600 },
    { height: 320, width: 568 },
    { height: 360, width: 740 },
  ]) {
    scannerTest(
      `scanner frame keeps the camera failure message at ${viewport.width}x${viewport.height} @mobile`,
      async ({ checkInManagerGroupPage }) => {
        // Open the scanner on a landscape screen with a camera that cannot start.
        await checkInManagerGroupPage.setViewportSize(viewport);
        const { modal } = await openScanner(checkInManagerGroupPage, {
          startError: "NotAllowedError",
          status: "Camera unavailable.",
        });

        // Verify the frame stays a square inside the camera view.
        const video = await modal.locator("[data-group-check-in-video]").boundingBox();
        const frame = await modal.locator(".border-white\\/70").boundingBox();
        expect(frame.width).toBeCloseTo(frame.height, 0);
        expect(frame.x).toBeGreaterThanOrEqual(video.x);
        expect(frame.y).toBeGreaterThanOrEqual(video.y);
        expect(frame.x + frame.width).toBeLessThanOrEqual(video.x + video.width);
        expect(frame.y + frame.height).toBeLessThanOrEqual(video.y + video.height);

        // Verify the whole failure message shows inside the frame.
        const unavailable = modal.locator("[data-group-check-in-camera-unavailable] > div");
        await expect(unavailable).toContainText("Camera permission was denied.");
        const message = await unavailable.boundingBox();
        expect(message.x).toBeGreaterThanOrEqual(frame.x);
        expect(message.y).toBeGreaterThanOrEqual(frame.y);
        expect(message.x + message.width).toBeLessThanOrEqual(frame.x + frame.width);
        expect(message.y + message.height).toBeLessThanOrEqual(frame.y + frame.height);
      },
    );
  }

  scannerTest(
    "scanner returns to the phone layout when turned to portrait @mobile",
    async ({ checkInManagerGroupPage }) => {
      // Open the scanner in landscape, then turn the phone.
      await checkInManagerGroupPage.setViewportSize({ height: 320, width: 568 });
      const { modal } = await openScanner(checkInManagerGroupPage);
      await checkInManagerGroupPage.setViewportSize({ height: 568, width: 320 });

      // Verify the card fills the screen and the video spans it, below the event line.
      expect(await modal.locator(".modal-card").boundingBox()).toEqual({
        height: 568,
        width: 320,
        x: 0,
        y: 0,
      });
      const video = await modal.locator("[data-group-check-in-video]").boundingBox();
      const eventName = await modal.locator("#group-check-in-event-name").boundingBox();
      expect(video.width).toBe(320);
      expect(video.y).toBeGreaterThanOrEqual(eventName.y + eventName.height);
    },
  );

  scannerTest("scanner keeps the screen awake while open @mobile", async ({ checkInManagerGroupPage }) => {
    // Open the scanner with a counting wake lock.
    await installFakeWakeLock(checkInManagerGroupPage);
    const { modal } = await openScanner(checkInManagerGroupPage);
    const wakeLock = () => checkInManagerGroupPage.evaluate(() => window.__OCG_E2E_WAKE_LOCK__);

    // Verify one lock is held while scanning.
    await expect.poll(wakeLock).toEqual({ held: 1, requests: 1 });

    // Close the scanner and verify the lock is released.
    await modal.getByRole("button", { name: "Close", exact: true }).click();
    await expect.poll(wakeLock).toEqual({ held: 0, requests: 1 });
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
    expect((await fallbackWarning.boundingBox()).x).toBe(12);

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
const openScanner = async (
  page,
  { status = "Hold an attendee QR code inside the frame.", ...options } = {},
) => {
  // Replace the browser scanner with a deterministic camera implementation.
  await installFakeQrScanner(page, options);

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
  await expect(modal.getByText(status)).toBeVisible();

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
