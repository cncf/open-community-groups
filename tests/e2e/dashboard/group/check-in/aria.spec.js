import { expect, test, testAtBothWidths } from "../../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openGroupDashboardView, setupAriaEvent, setupAriaGroup } from "../aria-helpers.js";
import { installFakeQrScanner } from "./helpers.js";

// Check-In is the only group dashboard tab with a mobile layout, so its @mobile test uses it.
test.describe("group dashboard check-in ARIA snapshots", () => {
  testAtBothWidths("matches the views", async ({ isMobile, organizerGroupPage, owned }) => {
    await expectCheckInViews({ owned, page: organizerGroupPage, viewport: isMobile ? "mobile" : "desktop" });
  });
});

/** Checks the layout of the check-in tab views and captures them. */
const expectCheckInViews = async ({ owned, page, viewport }) => {
  // The menu is a closed drawer in the mobile layout.
  const menu = viewport === "desktop";
  const checkIn = page.getByRole("region", { name: "Check-In" });
  const { groupId } = await setupAriaGroup({ owned, page });

  await test.step("empty state", async () => {
    // Load the check-in of a temporary group without events and check the layout.
    await openGroupDashboardView(page, "tab=check-in", { menu, regions: [checkIn] });

    // Capture the title, the instructions and the empty state.
    await expectAriaSnapshot(page, checkIn, `check-in-empty-${viewport}`);
  });

  // Give the group an owned published event, open for check-in until it ends.
  setupAriaEvent({ groupId, owned });

  await test.step("event cards", async () => {
    // Load the owned event card and check the layout.
    await openGroupDashboardView(page, "tab=check-in", { menu, regions: [checkIn] });

    // Capture the card with the event details and the scan button.
    await expectAriaSnapshot(page, checkIn, `check-in-events-${viewport}`);
  });

  await test.step("scanner dialog", async () => {
    // Open the scanner of the owned event with a fake camera and check the layout.
    const dialog = page.locator("#group-check-in-scanner-modal");
    await installFakeQrScanner(page);
    await openGroupDashboardView(page, "tab=check-in", { menu, regions: [checkIn] });
    await page.getByRole("button", { name: "Scan Attendee Codes for E2E ARIA event" }).click();
    await expect(dialog.getByText("Hold an attendee QR code inside the frame.")).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the scanner header, the camera controls and the status.
    // Below 640px a single camera hides the select, so the mobile tree has its own file.
    await expectAriaSnapshot(
      page,
      dialog,
      viewport === "mobile" ? "check-in-scanner-dialog-mobile" : "check-in-scanner-dialog",
    );
  });
};
