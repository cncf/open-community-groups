import { test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot } from "../../../snapshots.js";
import { openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

test.describe("group dashboard artwork ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectArtworkViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectArtworkViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the artwork tab views and captures them. */
const expectArtworkViews = async ({ owned, page }) => {
  const artwork = page.getByRole("region", { name: "Badges Artwork" });

  await test.step("empty library", async () => {
    // Load the artwork of a temporary group without artwork and check the layout.
    await setupAriaGroup({ owned, page });
    await openGroupDashboardView(page, "tab=artwork", { regions: [artwork] });

    // Capture the title, the upload field and the empty library.
    await expectAriaSnapshot(page, artwork, "artwork-empty");
  });

  await test.step("artwork library", async () => {
    // Load the artwork of a temporary group with one saved image and check the layout.
    await setupAriaGroup({ owned, page, withArtwork: true });
    await openGroupDashboardView(page, "tab=artwork", { regions: [artwork] });

    // Capture the library with the saved image and its remove button.
    await expectAriaSnapshot(page, artwork, "artwork-library");
  });
};
