import { expect, test } from "../../../fixtures.js";

import { TEST_OPEN_CHECK_IN_EVENT, navigateToPath } from "../../../utils.js";

test.describe("user dashboard check-in", () => {
  test("attendee opens a personal event credential on mobile", async ({ pending2Page }) => {
    // Load the attendee check-in dashboard at a mobile viewport.
    await pending2Page.setViewportSize({ width: 390, height: 844 });
    await navigateToPath(pending2Page, "/dashboard/user?tab=check-in");

    // Open the seeded event credential.
    await expect(pending2Page.getByRole("heading", { name: "Check-In" })).toBeVisible();
    const eventCard = pending2Page.locator("[data-user-check-in-open]", {
      hasText: TEST_OPEN_CHECK_IN_EVENT.name,
    });
    await expect(eventCard).toBeVisible();
    await eventCard.click();

    // Verify the modal shows the attendee identity and QR endpoint.
    const modal = pending2Page.locator("#user-check-in-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByRole("heading", { name: TEST_OPEN_CHECK_IN_EVENT.name })).toBeVisible();
    await expect(modal.locator("#user-check-in-name")).toHaveText("E2E Pending Two");
    await expect(modal.locator("#user-check-in-username")).toHaveText("@e2e-pending-2");
    await expect(modal.locator("#user-check-in-qr-image")).toHaveAttribute(
      "src",
      `/dashboard/user/check-in/${TEST_OPEN_CHECK_IN_EVENT.id}/qr-code`,
    );
  });
});
