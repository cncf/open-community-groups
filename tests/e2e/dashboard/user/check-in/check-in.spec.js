import { expect, test } from "../../../fixtures.js";

import { TEST_OPEN_CHECK_IN_EVENT, navigateToPath } from "../../../utils.js";

test.describe("user dashboard check-in", () => {
  test("attendee opens a personal event credential on mobile @mobile", async ({
    pending2Page,
  }) => {
    // Load the attendee check-in dashboard in the configured mobile project.
    await navigateToPath(pending2Page, "/dashboard/user?tab=check-in");

    // Verify the seeded event card stays within the dashboard wrapper.
    await expect(
      pending2Page.getByRole("heading", { name: "Check-In" }),
    ).toBeVisible();
    const eventCard = pending2Page.locator("[data-user-check-in-open]", {
      hasText: TEST_OPEN_CHECK_IN_EVENT.name,
    });
    await expect(eventCard).toBeVisible();
    const checkInRootBounds = await pending2Page
      .locator("[data-user-check-in-root]")
      .boundingBox();
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
    await expect(
      modal.getByRole("heading", { name: "Attendee check-in" }),
    ).toBeVisible();
    await expect(
      modal.getByRole("heading", { name: TEST_OPEN_CHECK_IN_EVENT.name }),
    ).toBeVisible();
    await expect(modal.locator("#user-check-in-date")).not.toBeEmpty();
    await expect(modal.locator("#user-check-in-name")).toHaveText(
      "E2E Pending Two",
    );
    await expect(modal.locator("#user-check-in-username")).toHaveText(
      "@e2e-pending-2",
    );
    const credential = modal.locator("[data-user-check-in-credential]");
    await expect(credential.locator("#user-check-in-photo")).toBeVisible();
    await expect(credential.locator("#user-check-in-name")).toHaveText(
      "E2E Pending Two",
    );
    const closeButton = modal
      .locator("[data-user-check-in-panel]")
      .getByRole("button", { name: "Close modal" });
    await expect(closeButton).toBeVisible();
    const closeIconBounds = await closeButton
      .locator(".icon-close")
      .boundingBox();
    expect(closeIconBounds).not.toBeNull();
    expect(closeIconBounds.width).toBe(20);
    expect(closeIconBounds.height).toBe(20);
    const qrImage = modal.locator("#user-check-in-qr-image");
    await expect(qrImage).toHaveAttribute(
      "src",
      `/dashboard/user/check-in/${TEST_OPEN_CHECK_IN_EVENT.id}/qr-code`,
    );
    await expect(qrImage).toBeVisible();
    await expect(
      modal.getByText("Show this code to an organizer", { exact: true }),
    ).toBeVisible();
    const footerCloseButton = modal
      .locator("footer")
      .getByRole("button", { name: "Close", exact: true });
    await expect(footerCloseButton).toBeVisible();

    // Verify the panel fills the mobile viewport within an even outer margin.
    const panelBounds = await modal
      .locator("[data-user-check-in-panel]")
      .boundingBox();
    expect(panelBounds).not.toBeNull();
    const viewport = pending2Page.viewportSize();
    expect(viewport).not.toBeNull();
    expect(panelBounds.x).toBe(12);
    expect(panelBounds.y).toBe(12);
    expect(panelBounds.width).toBe(viewport.width - 24);
    expect(panelBounds.height).toBe(viewport.height - 24);

    // Verify the complete credential starts within the scrollable mobile body.
    const bodyBounds = await modal
      .locator("[data-user-check-in-body]")
      .boundingBox();
    const credentialBounds = await credential.boundingBox();
    expect(bodyBounds).not.toBeNull();
    expect(credentialBounds).not.toBeNull();
    expect(credentialBounds.y).toBeGreaterThanOrEqual(bodyBounds.y);

    // Close from the footer and verify focus returns to the event card.
    await footerCloseButton.click();
    await expect(modal).toBeHidden();
    await expect(eventCard).toBeFocused();
  });
});
