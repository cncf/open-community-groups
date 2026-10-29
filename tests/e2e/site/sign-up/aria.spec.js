import { expect, test } from "../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToPath } from "../../utils.js";

test.describe("sign up page ARIA snapshots", () => {
  test("matches the desktop sign up form", async ({ page }) => {
    // Load the sign up page and check its layout.
    const main = await openSignUp(page);

    // Capture the form and the log in link.
    await expectAriaSnapshot(page, main, "sign-up-main");
  });

  test("matches the mobile sign up form @mobile", async ({ page }) => {
    // Load the sign up page and check its layout.
    const main = await openSignUp(page);

    // Capture the form and the log in link.
    await expectAriaSnapshot(page, main, "sign-up-main");
  });
});

/** Opens the sign up page, checks its layout and returns the main content. */
const openSignUp = async (page) => {
  const main = page.locator("#main-content");
  await navigateToPath(page, "/sign-up");
  await expect(page.getByRole("heading", { name: "Sign Up" })).toBeVisible();
  await expectPageLayout(page, { regions: [main] });
  return main;
};
