import { expect } from "@playwright/test";

/**
 * Waits for the docs to render and opens the Contents sheet.
 * @param {import("@playwright/test").Page} page - Page showing the docs.
 * @returns {Promise<{
 *   contentsButton: import("@playwright/test").Locator,
 *   sheet: import("@playwright/test").Locator,
 * }>} Toggle and sheet.
 */
export const openContents = async (page) => {
  const docsRoot = page.locator(".ocg-docs-root");
  const contentsButton = docsRoot.getByRole("button", { name: "Contents", exact: true });
  const sheet = docsRoot.locator(".sidebar");
  await expect(docsRoot.getByRole("heading", { level: 1 }).first()).toBeVisible({ timeout: 15000 });
  await contentsButton.click();
  await expect(sheet).toBeVisible();

  // Wait for the slide to finish, so callers can measure the sheet.
  await expect(sheet).toHaveCSS("transform", "none");
  return { contentsButton, sheet };
};
