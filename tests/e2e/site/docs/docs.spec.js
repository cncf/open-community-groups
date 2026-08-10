import { expect, test } from "@playwright/test";

import { navigateToPath } from "../../utils.js";

test.describe("site docs page", () => {
  test("loads the docs shell and documentation navigation", async ({ page }) => {
    // Load the docs page before checking the embedded docs shell.
    await navigateToPath(page, "/docs");

    // Find the docs root.
    const docsRoot = page.locator(".ocg-docs-root");

    // Verify loads the docs shell and documentation navigation.
    await expect(docsRoot).toHaveAttribute("data-ocg-docs", "/static/docs/index.html#/");
    await expect(docsRoot).toBeVisible();

    // Assert the expected content is visible.
    await expect(page.locator(".ocg-docs-root .sidebar-nav")).toBeVisible({
      timeout: 15000,
    });
    await expect(page.locator(".ocg-docs-root .content")).toBeVisible({
      timeout: 15000,
    });
  });

  test("sidebar navigation updates content, title, hash, and browser history", async ({ page }) => {
    // Load documentation before following a sidebar destination.
    await navigateToPath(page, "/docs");

    // Find the Quickstart link and verify its hash destination.
    const docsRoot = page.locator(".ocg-docs-root");
    const quickstartLink = docsRoot
      .locator(".sidebar-nav")
      .getByRole("link", { name: "Quickstart", exact: true })
      .first();
    await expect(quickstartLink).toHaveAttribute("href", "#/getting-started/quickstart");
    await quickstartLink.click();

    // Verify navigation updates the URL, title, and rendered document.
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);
    await expect(page).toHaveTitle("Quickstart");
    await expect(docsRoot.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible();

    // Return through browser history and verify the overview is restored.
    await page.goBack();
    await expect(page).toHaveURL(/\/docs#\/$/);
    await expect(page).toHaveTitle("Overview");
  });

  test("deep links open the requested document on initial load", async ({ page }) => {
    // Load documentation directly through a non-root hash destination.
    await navigateToPath(page, "/docs#/getting-started/quickstart");

    // Verify the requested document renders without extra navigation.
    const docsRoot = page.locator(".ocg-docs-root");
    await expect(page).toHaveTitle("Quickstart");
    await expect(docsRoot.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible({
      timeout: 15000,
    });

    // Verify the sidebar highlights the deep-linked destination.
    const quickstartItem = docsRoot
      .locator(".sidebar-nav li.active")
      .getByRole("link", { name: "Quickstart", exact: true });
    await expect(quickstartItem).toBeVisible();
  });

  test("documentation remains navigable on mobile @mobile", async ({ page }) => {
    // Load documentation using the mobile project viewport.
    await navigateToPath(page, "/docs");

    // Verify the mobile menu and overview content remain available.
    const docsRoot = page.locator(".ocg-docs-root");
    const menuButton = docsRoot.getByRole("button", { name: "Menu" });
    const overviewHeading = docsRoot.getByRole("heading", {
      name: "Open Community Groups Documentation",
      level: 1,
    });
    await expect(menuButton).toBeVisible();
    await expect(overviewHeading).toBeVisible({ timeout: 15000 });

    // Open the sidebar and verify mirrored shell state and destinations.
    await menuButton.click();
    await expect(page.locator("body")).toHaveClass(/\bclose\b/);
    await expect(docsRoot).toHaveClass(/\bclose\b/);
    const troubleshootingLink = docsRoot.getByRole("link", { name: "Troubleshooting", exact: true }).first();
    await expect(troubleshootingLink).toBeVisible();
    await expect(troubleshootingLink).toHaveAttribute("href", "#/support/troubleshooting");

    // Dismiss the sidebar through the exposed documentation content.
    const docsRootBox = await docsRoot.boundingBox();
    expect(docsRootBox).not.toBeNull();
    await docsRoot.click({
      position: {
        x: docsRootBox.width - 16,
        y: 16,
      },
    });
    await expect(page.locator("body")).not.toHaveClass(/\bclose\b/);
    await expect(docsRoot).not.toHaveClass(/\bclose\b/);

    // Reopen the sidebar and navigate to a documentation page.
    await menuButton.click();
    const quickstartLink = docsRoot
      .locator(".sidebar-nav")
      .getByRole("link", { name: "Quickstart", exact: true })
      .first();
    await quickstartLink.click();

    // Verify mobile navigation updates the route and rendered document.
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);
    await expect(page).toHaveTitle("Quickstart");
    await expect(docsRoot.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible();
  });
});
