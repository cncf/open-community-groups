import { expect, test } from "../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToPath } from "../../utils.js";

test.describe("public badge verification page ARIA snapshots", () => {
  test("matches the desktop verification form", async ({ page }) => {
    // Load the verification page and check its layout.
    const form = await openVerification(page);

    // Capture the verification form.
    await expectAriaSnapshot(page, form, "badge-verification-form");
  });

  test("matches the mobile verification form @mobile", async ({ page }) => {
    // Load the verification page and check its layout.
    const form = await openVerification(page);

    // Capture the verification form.
    await expectAriaSnapshot(page, form, "badge-verification-form");
  });
});

/** Opens the badge verification page, checks its layout and returns the form region. */
const openVerification = async (page) => {
  const form = page.getByRole("region", { name: "Verify an OCG badge" });
  await navigateToPath(page, "/badges/verify");
  await expect(page.getByRole("heading", { name: "Verify an OCG badge" })).toBeVisible();
  await expectPageLayout(page, { regions: [form] });
  return form;
};
