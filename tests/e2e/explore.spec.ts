import { test, expect } from "@playwright/test";
import { navigateWithRetry } from "./utils";

test.describe("Explore Page", () => {
  test("should load explore page successfully", async ({ page }) => {
    await navigateWithRetry(page, "/explore");
    const exploreContent = page.locator("#explore-content");

    await expect(exploreContent).toBeVisible();
  });

  test("should have entity selection tabs", async ({ page }) => {
    await navigateWithRetry(page, "/explore");
    const entitySection = page.locator("#entity-section");

    await expect(entitySection).toBeVisible();
  });

  test("should have search input", async ({ page }) => {
    await navigateWithRetry(page, "/explore");
    const searchInput = page.locator('#ts_query, input[name="ts_query"]');

    await expect(searchInput).toBeVisible();
  });

  test("should display results section", async ({ page }) => {
    await navigateWithRetry(page, "/explore");
    const exploreContent = page.locator("#explore-content");
    const groupResults = page.locator(
      '[data-testid="group-result"], .group-card',
    );
    const eventResults = page.locator(
      '[data-testid="event-result"], .event-card',
    );

    // Wait for initial content to load
    await page.waitForLoadState("networkidle");

    // Should have either group or event results visible
    const hasGroups = (await groupResults.count()) > 0;
    const hasEvents = (await eventResults.count()) > 0;
    const contentVisible = await exploreContent.isVisible();

    // At least one type of result should be displayable (or content section is visible)
    expect(hasGroups || hasEvents || contentVisible).toBeTruthy();
  });

  test("should preserve search query in URL", async ({ page }) => {
    const searchQuery = "kubernetes";

    await navigateWithRetry(
      page,
      `/explore?ts_query=${encodeURIComponent(searchQuery)}`,
    );

    expect(page.url()).toContain("ts_query");
    expect(page.url()).toContain(searchQuery);
  });

  test("should be responsive and show filter toggle on mobile", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 375, height: 667 });

    await navigateWithRetry(page, "/explore");
    const filterToggle = page.locator("[data-filter-toggle]");
    const filterDrawer = page.locator("#filter-drawer, [data-filter-drawer]");

    // On mobile, filter toggle should be visible or filter drawer directly visible
    const isToggleVisible = await filterToggle.isVisible().catch(() => false);
    const filtersVisible = await filterDrawer.isVisible().catch(() => false);

    // Either toggle is visible (mobile) or filters are directly visible (desktop)
    expect(isToggleVisible || filtersVisible).toBeTruthy();
  });
});
