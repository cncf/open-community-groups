import { expect, test } from "../../../fixtures.js";

import { TEST_OPEN_CHECK_IN_EVENT } from "../../../seed.js";
import { navigateToPath } from "../../../utils.js";
import { installFakeWakeLock } from "../../group/check-in/helpers.js";

const USER_CHECK_IN_PATH = "/dashboard/user?tab=check-in";

test.describe("user dashboard check-in", () => {
  test("attendee opens a personal event credential on mobile @mobile", async ({ pending2Page }) => {
    // Load the attendee check-in dashboard in the configured mobile project.
    await navigateToPath(pending2Page, "/dashboard/user?tab=check-in");

    // Verify the seeded event card stays within the dashboard wrapper.
    await expect(pending2Page.getByRole("heading", { name: "Check-In" })).toBeVisible();
    const eventCard = pending2Page.locator("[data-user-check-in-open]", {
      hasText: TEST_OPEN_CHECK_IN_EVENT.name,
    });
    await expect(eventCard).toBeVisible();
    const checkInRootBounds = await pending2Page.locator("[data-user-check-in-root]").boundingBox();
    const eventCardBounds = await eventCard.boundingBox();
    expect(checkInRootBounds).not.toBeNull();
    expect(eventCardBounds).not.toBeNull();
    expect(eventCardBounds.x).toBeGreaterThanOrEqual(checkInRootBounds.x);
    expect(eventCardBounds.x + eventCardBounds.width).toBeLessThanOrEqual(
      checkInRootBounds.x + checkInRootBounds.width,
    );

    // Open the seeded event credential.
    await eventCard.click();

    // Verify the modal shows the attendee identity and QR endpoint.
    const modal = pending2Page.locator("#user-check-in-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByRole("heading", { name: "Attendee check-in" })).toBeVisible();
    await expect(modal.getByRole("heading", { name: TEST_OPEN_CHECK_IN_EVENT.name })).toBeVisible();
    await expect(modal.locator("#user-check-in-date")).not.toBeEmpty();
    await expect(modal.locator("#user-check-in-name")).toHaveText("E2E Pending Two");
    await expect(modal.locator("#user-check-in-username")).toHaveText("@e2e-pending-2");
    const credential = modal.locator("[data-user-check-in-credential]");
    await expect(credential.locator("#user-check-in-photo")).toBeVisible();
    await expect(credential.locator("#user-check-in-name")).toHaveText("E2E Pending Two");
    const closeButton = modal
      .locator("[data-user-check-in-panel]")
      .getByRole("button", { name: "Close modal" });
    await expect(closeButton).toBeVisible();
    const closeIconBounds = await closeButton.locator(".icon-close").boundingBox();
    expect(closeIconBounds).not.toBeNull();
    expect(closeIconBounds.width).toBe(20);
    expect(closeIconBounds.height).toBe(20);
    const qrImage = modal.locator("#user-check-in-qr-image");
    await expect(qrImage).toHaveAttribute(
      "src",
      `/dashboard/user/check-in/${TEST_OPEN_CHECK_IN_EVENT.id}/qr-code`,
    );
    await expect(qrImage).toBeVisible();
    await expect(modal.getByText("Show this code to an organizer", { exact: true })).toBeVisible();
    const footerCloseButton = modal.locator("footer").getByRole("button", { name: "Close", exact: true });
    await expect(footerCloseButton).toBeVisible();

    // Verify the panel is a sheet on the bottom edge, once its entry animation ends.
    const panel = modal.locator("[data-user-check-in-panel]");
    const viewport = pending2Page.viewportSize();
    expect(viewport).not.toBeNull();
    await expect
      .poll(() => panel.boundingBox())
      .toEqual({ height: viewport.height - 64, width: viewport.width, x: 0, y: 64 });

    // Verify the complete credential starts within the scrollable mobile body.
    const bodyBounds = await modal.locator("[data-user-check-in-body]").boundingBox();
    const credentialBounds = await credential.boundingBox();
    expect(bodyBounds).not.toBeNull();
    expect(credentialBounds).not.toBeNull();
    expect(credentialBounds.y).toBeGreaterThanOrEqual(bodyBounds.y);

    // Close from the footer and verify focus returns to the event card.
    await footerCloseButton.click();
    await expect(modal).toBeHidden();
    await expect(eventCard).toBeFocused();
  });

  test("event card shows the tap cue and unclipped dates at 320px @mobile", async ({ pending2Page }) => {
    // Load the attendee card on the narrowest supported phone.
    await pending2Page.setViewportSize({ height: 568, width: 320 });
    await navigateToPath(pending2Page, USER_CHECK_IN_PATH);
    const eventCard = pending2Page.locator("[data-user-check-in-open]", {
      hasText: TEST_OPEN_CHECK_IN_EVENT.name,
    });

    // Verify the cue is visible and stays out of the card's accessible name.
    await expect(eventCard.getByText("Show QR code", { exact: true })).toBeVisible();
    await expect(pending2Page.getByRole("button", { name: /Show QR code/u })).toHaveCount(0);

    // Verify the location and date lines wrap instead of cutting off the time.
    const lines = eventCard.locator(".text-\\[0\\.825rem\\]");
    await expect(lines).toHaveCount(2);
    for (const line of await lines.all()) {
      expect(await line.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);
    }
  });

  for (const viewport of [
    { height: 568, width: 320 },
    { height: 667, width: 375 },
    { height: 232, width: 568 },
    { height: 264, width: 568 },
    { height: 320, width: 568 },
    { height: 360, width: 640 },
    { height: 375, width: 667 },
    { height: 360, width: 740 },
  ]) {
    test(`credential sheet shows the QR code at ${viewport.width}x${viewport.height} @mobile`, async ({
      pending2Page,
    }) => {
      // Open the credential on a small screen.
      await pending2Page.setViewportSize(viewport);
      await navigateToPath(pending2Page, USER_CHECK_IN_PATH);
      await pending2Page
        .locator("[data-user-check-in-open]", { hasText: TEST_OPEN_CHECK_IN_EVENT.name })
        .click();
      const modal = pending2Page.locator("#user-check-in-modal");
      const image = modal.locator("#user-check-in-qr-image");
      await expect(image).toBeVisible();

      // Wait for the sheet's entry animation, then verify the code keeps its floor.
      const portrait = viewport.height > viewport.width;
      const panel = modal.locator("[data-user-check-in-panel]");
      await expect.poll(async () => (await panel.boundingBox()).y).toBe(portrait ? 64 : 0);
      const imageBounds = await image.boundingBox();
      expect(imageBounds.width).toBeGreaterThanOrEqual(portrait ? 192 : Math.min(200, viewport.height - 64));
      expect(imageBounds.height).toBeCloseTo(imageBounds.width, 0);

      // Verify the page gains no sideways scroll.
      expect(
        await pending2Page.evaluate(
          () => document.documentElement.scrollWidth <= document.documentElement.clientWidth,
        ),
      ).toBe(true);

      // On a portrait phone the whole code shows above the pinned footer without scrolling.
      const footer = modal.locator("footer");
      if (portrait) {
        const footerBounds = await footer.boundingBox();
        expect(footerBounds.y + footerBounds.height).toBe(viewport.height);
        expect(imageBounds.y + imageBounds.height).toBeLessThanOrEqual(footerBounds.y);
        return;
      }

      // On a short screen the whole code shows under the head on open, with nothing scrolled.
      const head = modal.locator(".sheet-head");
      const headBounds = await head.boundingBox();
      expect(await panel.evaluate((element) => element.scrollTop)).toBe(0);
      expect(imageBounds.y).toBeGreaterThanOrEqual(headBounds.y + headBounds.height);
      expect(imageBounds.y + imageBounds.height).toBeLessThanOrEqual(viewport.height);

      // Verify the caption shows too, by scrolling when the code takes all the height under the head.
      const caption = modal.getByText("Show this code to an organizer", { exact: true });
      if (viewport.height < 320) await caption.scrollIntoViewIfNeeded();
      await expect(caption).toBeInViewport({ ratio: 1 });
      await panel.evaluate((element) => element.scrollTo(0, 0));

      // Verify the white area keeps a clear margin around the code.
      const area = await image.locator("xpath=..").boundingBox();
      expect(imageBounds.x - area.x).toBeGreaterThanOrEqual(12);
      expect(area.x + area.width - imageBounds.x - imageBounds.width).toBeGreaterThanOrEqual(12);

      // Verify the details sit beside the code, and the name and footer Close are reachable.
      const titleBounds = await modal.locator("#user-check-in-event-name").boundingBox();
      expect(titleBounds.x + titleBounds.width).toBeLessThanOrEqual(imageBounds.x);
      const name = modal.locator("#user-check-in-name");
      if (viewport.height < 320) await name.scrollIntoViewIfNeeded();
      await expect(name).toBeInViewport({ ratio: 1 });
      await footer.scrollIntoViewIfNeeded();
      await expect(footer.getByRole("button", { name: "Close" })).toBeInViewport({ ratio: 1 });
      await expect(head.getByRole("button", { name: "Close modal" })).toBeInViewport();
    });
  }

  test("credential sheet fits the QR code under the head in a narrow short window @mobile", async ({
    pending2Page,
  }) => {
    // Open the credential in a window too short for the code's floor and too narrow for two columns.
    await pending2Page.setViewportSize({ height: 232, width: 400 });
    await navigateToPath(pending2Page, USER_CHECK_IN_PATH);
    await pending2Page
      .locator("[data-user-check-in-open]", { hasText: TEST_OPEN_CHECK_IN_EVENT.name })
      .click();
    const modal = pending2Page.locator("#user-check-in-modal");
    const image = modal.locator("#user-check-in-qr-image");
    await expect(image).toBeVisible();

    // Scroll the code up to the head and verify all of it shows.
    const panel = modal.locator("[data-user-check-in-panel]");
    await expect.poll(async () => (await panel.boundingBox()).y).toBe(0);
    const headBounds = await modal.locator(".sheet-head").boundingBox();
    const headBottom = headBounds.y + headBounds.height;
    await panel.evaluate(
      (element, top) => element.scrollBy(0, top),
      (await image.boundingBox()).y - headBottom,
    );
    const imageBounds = await image.boundingBox();
    expect(imageBounds.y).toBeGreaterThanOrEqual(headBottom - 1);
    expect(imageBounds.y + imageBounds.height).toBeLessThanOrEqual(232);
  });

  test("credential shows the failure message and retries the QR code on desktop", async ({
    pending2Page,
  }) => {
    // Open the credential while the QR code request fails.
    await navigateToPath(pending2Page, USER_CHECK_IN_PATH);
    const qrRoute = /\/dashboard\/user\/check-in\/[^/]+\/qr-code/u;
    await pending2Page.route(qrRoute, (route) => route.abort());
    await pending2Page
      .locator("[data-user-check-in-open]", { hasText: TEST_OPEN_CHECK_IN_EVENT.name })
      .click();
    const modal = pending2Page.locator("#user-check-in-modal");
    const message = modal.getByRole("status");
    const retry = modal.getByRole("button", { name: "Try again" });
    await expect(message).toHaveText("The QR code could not be loaded. Try again.");

    // Verify the message and retry stay on top, with no broken-image tile left behind.
    await expect(message).toBeVisible();
    await expect(retry).toBeVisible();
    await expect(modal.locator("[data-ocg-broken-image-icon]")).toHaveCount(0);
    for (const target of [message, retry]) {
      expect(
        await target.evaluate((element) => {
          const { height, width, x, y } = element.getBoundingClientRect();
          return element.contains(document.elementFromPoint(x + width / 2, y + height / 2));
        }),
      ).toBe(true);
    }
    await expect(modal.getByText("Show this code to an organizer", { exact: true })).toBeHidden();

    // Retry once the request can succeed.
    await pending2Page.unroute(qrRoute);
    await retry.click();
    await expect(modal.locator("#user-check-in-qr-image")).toBeVisible();
    await expect(message).toBeHidden();
    await expect(retry).toBeHidden();
    await expect(modal.getByText("Show this code to an organizer", { exact: true })).toBeVisible();
  });

  test("credential sheet shows the failure message and retries the QR code @mobile", async ({
    pending2Page,
  }) => {
    // Open the credential while the QR code request fails.
    await navigateToPath(pending2Page, USER_CHECK_IN_PATH);
    const qrRoute = /\/dashboard\/user\/check-in\/[^/]+\/qr-code/u;
    await pending2Page.route(qrRoute, (route) => route.abort());
    await pending2Page
      .locator("[data-user-check-in-open]", { hasText: TEST_OPEN_CHECK_IN_EVENT.name })
      .click();
    const modal = pending2Page.locator("#user-check-in-modal");
    const message = modal.getByRole("status");
    await expect(message).toHaveText("The QR code could not be loaded. Try again.");

    // Verify no broken-image tile covers the message, and the caption waits for a code.
    await expect(modal.locator("[data-ocg-broken-image-icon]")).toHaveCount(0);
    await expect(modal.getByText("Show this code to an organizer", { exact: true })).toBeHidden();

    // Retry once the request can succeed.
    await pending2Page.unroute(qrRoute);
    await modal.getByRole("button", { name: "Try again" }).click();
    await expect(modal.locator("#user-check-in-qr-image")).toBeVisible();
    await expect(modal.getByText("Show this code to an organizer", { exact: true })).toBeVisible();
  });

  test("credential sheet closes from Escape and a downward drag @mobile", async ({ pending2Page }) => {
    // Open the credential and wait for the sheet gestures.
    await navigateToPath(pending2Page, USER_CHECK_IN_PATH);
    const eventCard = pending2Page.locator("[data-user-check-in-open]", {
      hasText: TEST_OPEN_CHECK_IN_EVENT.name,
    });
    const modal = pending2Page.locator("#user-check-in-modal");
    const panel = modal.locator("[data-user-check-in-panel]");
    await eventCard.click();
    await expect(panel).toHaveAttribute("data-sheet-drag", "");

    // Close with Escape and verify focus returns to the card.
    await pending2Page.keyboard.press("Escape");
    await expect(modal).toBeHidden();
    await expect(eventCard).toBeFocused();

    // Reopen and drag the title row past the close threshold.
    await eventCard.click();
    await expect(panel).toHaveAttribute("data-sheet-drag", "");
    const headBounds = await modal.locator(".sheet-grab").boundingBox();
    const startX = headBounds.x + 40;
    const startY = headBounds.y + headBounds.height / 2;
    await pending2Page.mouse.move(startX, startY);
    await pending2Page.mouse.down();
    await pending2Page.mouse.move(startX, startY + 200, { steps: 6 });
    await pending2Page.mouse.up();

    // Verify the drag runs the same close path.
    await expect(modal).toBeHidden();
    await expect(panel).not.toHaveAttribute("data-sheet-drag", "");
  });

  test("credential sheet keeps the screen awake while open @mobile", async ({ pending2Page }) => {
    // Open the credential with a counting wake lock.
    await installFakeWakeLock(pending2Page);
    await navigateToPath(pending2Page, USER_CHECK_IN_PATH);
    const wakeLock = () => pending2Page.evaluate(() => window.__OCG_E2E_WAKE_LOCK__);
    await pending2Page
      .locator("[data-user-check-in-open]", { hasText: TEST_OPEN_CHECK_IN_EVENT.name })
      .click();

    // Verify one lock is held while the code shows.
    await expect.poll(wakeLock).toEqual({ held: 1, requests: 1 });

    // Close the sheet and verify the lock is released.
    await pending2Page
      .locator("#user-check-in-modal footer")
      .getByRole("button", { name: "Close", exact: true })
      .click();
    await expect.poll(wakeLock).toEqual({ held: 0, requests: 1 });
  });
});
