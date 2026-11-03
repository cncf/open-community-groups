import { expect, test } from "../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToPath } from "../../utils.js";

// Docsify builds the sidebar from docs/_sidebar.md and the docs/index.md h2 headings, so the
// snapshot is a partial template (contain mode, no `/children: deep-equal`): the heading link,
// the root "Overview" entry and one heading link, not the guide list or heading names.
// The rendered document is left out for the same reason.
test.describe("site docs page ARIA snapshots", () => {
  test("matches the desktop documentation navigation", async ({ page }) => {
    // Load the docs page and check its layout.
    const sidebar = await openDocs(page);

    // Capture the documentation navigation.
    await expectAriaSnapshot(page, sidebar, "docs-sidebar");
  });

  test("matches the mobile documentation navigation @mobile", async ({ page }) => {
    // Load the docs page and check its layout.
    const sidebar = await openDocs(page);

    // Capture the documentation navigation.
    await expectAriaSnapshot(page, sidebar, "docs-sidebar");
  });
});

/** Opens the docs page, checks its layout and returns the documentation sidebar. */
const openDocs = async (page) => {
  const sidebar = page.getByRole("complementary");
  await navigateToPath(page, "/docs");
  await expect(page.locator(".ocg-docs-root .content")).toBeVisible({ timeout: 15_000 });
  await expectPageLayout(page, { regions: [page.locator(".ocg-docs-root .content")] });
  return sidebar;
};
