import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  navigateToSiteHome,
  TEST_SITE_TITLE,
} from "../../utils";

test.describe("site home page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }) => {
    await navigateToSiteHome(page);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    await expectRegionScreenshot(
      page,
      page.locator("div.relative.container").first(),
      "site-home-desktop.png",
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToSiteHome(page);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    await expectRegionScreenshot(
      page,
      page.locator("div.relative.container").first(),
      "site-home-mobile.png",
    );
  });
});
