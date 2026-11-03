import { expect, test } from "../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToPath } from "../../utils.js";

test.describe("log in page ARIA snapshots", () => {
  test("matches the desktop log in form", async ({ page }) => {
    // Load the log in page and check its layout.
    const main = await openLogIn(page);

    // Capture the form and the sign up link.
    await expectAriaSnapshot(page, main, "log-in-main");
  });

  test("matches the mobile log in form @mobile", async ({ page }) => {
    // Load the log in page and check its layout.
    const main = await openLogIn(page);

    // Capture the form and the sign up link.
    await expectAriaSnapshot(page, main, "log-in-main");
  });
});

/** Opens the log in page, checks its layout and returns the main content. */
const openLogIn = async (page) => {
  const main = page.locator("#main-content");
  await navigateToPath(page, "/log-in");
  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  await expectPageLayout(page, { regions: [page.getByRole("form", { name: "Log In" })] });
  return main;
};
