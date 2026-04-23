import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getCommunityAboutSection,
  navigateToCommunityHome,
  TEST_COMMUNITY_DESCRIPTION,
  TEST_COMMUNITY_NAME,
} from "../../utils";

test.describe("community home page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    await expectRegionScreenshot(
      page,
      getCommunityAboutSection(page),
      "community-home-desktop.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    await expectRegionScreenshot(
      page,
      page.locator(".community-description"),
      "community-home-mobile.png",
      { maxDiffPixelRatio: 0.012, testInfo, useClippedPageScreenshot: true },
    );
  });
});
