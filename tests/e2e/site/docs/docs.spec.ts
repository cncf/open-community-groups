import { expect, test } from "@playwright/test";

import { navigateToPath } from "../../utils";

test.describe("site docs page", () => {
  test("loads the docs shell and documentation navigation", async ({ page }) => {
    await navigateToPath(page, "/docs");

    const docsRoot = page.locator(".ocg-docs-root");
    await expect(docsRoot).toHaveAttribute("data-ocg-docs", "/static/docs/index.html#/");
    await expect(docsRoot).toBeVisible();

    await expect(page.locator(".ocg-docs-root .sidebar-nav")).toBeVisible({
      timeout: 15000,
    });
    await expect(page.locator(".ocg-docs-root .content")).toBeVisible({
      timeout: 15000,
    });
  });
});
