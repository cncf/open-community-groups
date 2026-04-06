import { expect, test } from "@playwright/test";

import {
  expectPageScreenshot,
  navigateToCommunityHome,
  TEST_COMMUNITY_DESCRIPTION,
  TEST_COMMUNITY_NAME,
} from "../../utils";

test.describe("community home page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }) => {
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    await expectPageScreenshot(page, "community-home-desktop.png");
  });

  test("matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    await expectPageScreenshot(page, "community-home-mobile.png", {
      mask: [page.locator(`a[href^="/${TEST_COMMUNITY_NAME}/group/"]`)],
      maxDiffPixels: 100,
    });
  });
});
