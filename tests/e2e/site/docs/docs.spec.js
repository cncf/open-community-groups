import { expect, test } from "@playwright/test";

import { navigateToPath } from "../../utils.js";

test.describe("site docs page", () => {
  test("loads the docs shell and documentation navigation", async ({
    page,
  }) => {
    // Load the docs page before checking the embedded docs shell.
    await navigateToPath(page, "/docs");

    // Find the docs root.
    const docsRoot = page.locator(".ocg-docs-root");

    // Verify loads the docs shell and documentation navigation.
    await expect(docsRoot).toHaveAttribute(
      "data-ocg-docs",
      "/static/docs/index.html#/",
    );
    await expect(docsRoot).toBeVisible();

    // Assert the expected content is visible.
    await expect(page.locator(".ocg-docs-root .sidebar-nav")).toBeVisible({
      timeout: 15000,
    });
    await expect(page.locator(".ocg-docs-root .content")).toBeVisible({
      timeout: 15000,
    });
  });
});
