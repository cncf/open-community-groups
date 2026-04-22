import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getHomeJumbotronContent,
  navigateToSiteHome,
  TEST_SITE_TITLE,
} from "../../utils";

test.describe("site home page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    await navigateToSiteHome(page);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    await expectRegionScreenshot(
      page,
      getHomeJumbotronContent(page),
      "site-home-desktop.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    await navigateToSiteHome(page);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    await expectRegionScreenshot(
      page,
      getHomeJumbotronContent(page),
      "site-home-mobile.png",
      { testInfo },
    );
  });
});
