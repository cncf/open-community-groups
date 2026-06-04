import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getHomeJumbotronContent,
  navigateToSiteHome,
  TEST_SITE_TITLE,
} from "../../utils.js";

test.describe("site home page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    // Load the public home page for the desktop snapshot.
    await navigateToSiteHome(page);

    // Verify desktop home content is ready.
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    // Capture the desktop jumbotron snapshot.
    await expectRegionScreenshot(
      page,
      getHomeJumbotronContent(page),
      "site-home-desktop.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the public home page for the mobile snapshot.
    await navigateToSiteHome(page);

    // Verify mobile home content is ready.
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    // Capture the mobile jumbotron snapshot.
    await expectRegionScreenshot(
      page,
      getHomeJumbotronContent(page),
      "site-home-mobile.png",
      { testInfo, useClippedPageScreenshot: true },
    );
  });
});
