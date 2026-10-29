import { expect, test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// The forms are captured empty, as the user without data, since profile tests edit seeded profiles.
test.describe("user dashboard profile ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member1Page }) => {
    await expectProfileViews({ emptyUserPage, member1Page });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ emptyUserPage, member1Page }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member1Page);
    await expectProfileViews({ emptyUserPage, member1Page });
  });
});

/** Checks the layout of the profile tab and captures its forms. */
const expectProfileViews = async ({ emptyUserPage, member1Page }) => {
  await test.step("details and password forms", async () => {
    // Load the profile tab and check its layout with both forms.
    const detailsForm = emptyUserPage.locator("#user-details-form");
    const passwordForm = emptyUserPage.locator("#password-form");
    await openUserDashboardView(emptyUserPage, "tab=account", { regions: [detailsForm, passwordForm] });

    // Capture the details form labels, hints and controls.
    await expectAriaSnapshot(emptyUserPage, detailsForm, "profile-details-form");

    // Capture the password form.
    await expectAriaSnapshot(emptyUserPage, passwordForm, "profile-password-form");
  });

  await test.step("filled details form", async () => {
    // Load the profile of a user with every field set and check its layout.
    const detailsForm = member1Page.locator("#user-details-form");
    await openUserDashboardView(member1Page, "tab=account", { regions: [detailsForm] });
    await expect(detailsForm.getByRole("textbox", { name: "Name *" })).not.toHaveValue("");
  });
};
