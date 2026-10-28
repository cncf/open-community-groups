import { expect, test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// The first member's purchase rows are only laid out, not captured: payment tests change their
// statuses and documents, and the invoice and credit note links redirect to Stripe.
test.describe("user dashboard purchases ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member1Page }) => {
    await expectPurchasesViews({ emptyUserPage, member1Page });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ emptyUserPage, member1Page }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member1Page);
    await expectPurchasesViews({ emptyUserPage, member1Page });
  });
});

/** Checks the layout of the purchases tab views and captures them. */
const expectPurchasesViews = async ({ emptyUserPage, member1Page }) => {
  await test.step("empty state", async () => {
    // Load the purchases of a user without paid tickets and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=purchases");

    // Capture the title, the column headers and the empty state.
    await expectAriaSnapshot(emptyUserPage, content, "purchases-empty");
  });

  await test.step("purchase rows", async () => {
    // Load the first member's purchases and check the table fits the content width.
    const table = member1Page.locator("#dashboard-content").getByRole("table");
    await openUserDashboardView(member1Page, "tab=purchases", { regions: [table] });
    await expect(table.getByRole("rowheader").first()).toBeVisible();
  });
};
