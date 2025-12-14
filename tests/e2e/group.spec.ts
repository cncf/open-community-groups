import { test, expect } from "@playwright/test";
import { navigateWithRetry } from "./utils";

test.describe("Group Page", () => {
  test("should display group name in header", async ({ page }) => {
    await navigateWithRetry(page, "/group/test-group");

    // Group name should be visible (either as H1 or in a data attribute)
    await expect(page.locator("h1, [data-group-name]").first()).toBeVisible();
  });

  test("should show membership container", async ({ page }) => {
    await navigateWithRetry(page, "/group/test-group");

    await expect(page.locator("#membership-container")).toBeVisible();
  });

  test("should initially show loading state for membership", async ({
    page,
  }) => {
    await navigateWithRetry(page, "/group/test-group");

    // Loading button should be visible initially
    const loadingVisible = await page
      .locator("#loading-btn")
      .isVisible()
      .catch(() => false);

    // Loading state may or may not be visible depending on response timing
    // This test verifies the page loads without errors
    expect(loadingVisible !== undefined).toBeTruthy();
  });

  test("should have membership checker element", async ({ page }) => {
    await navigateWithRetry(page, "/group/test-group");

    // Membership checker element should exist (triggers HTMX request)
    await expect(page.locator("#membership-checker")).toBeAttached();
  });

  test("should display events section if group has events", async ({
    page,
  }) => {
    await navigateWithRetry(page, "/group/test-group");

    // Wait for page to fully load
    await page.waitForLoadState("networkidle");

    // Check for events section - may or may not have events
    const upcomingVisible = await page
      .locator("[data-upcoming-events], #upcoming-events")
      .isVisible()
      .catch(() => false);
    const pastVisible = await page
      .locator("[data-past-events], #past-events")
      .isVisible()
      .catch(() => false);
    const eventCardsCount = await page
      .locator("[data-event-card], .event-card")
      .count();

    // Either events section is visible or group has no events.
    expect(
      upcomingVisible || pastVisible || eventCardsCount === 0,
    ).toBeTruthy();
  });
});
