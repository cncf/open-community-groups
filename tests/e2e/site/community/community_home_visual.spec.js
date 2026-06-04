import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getCommunityAboutSection,
  navigateToCommunityHome,
  TEST_COMMUNITY_DESCRIPTION,
  TEST_COMMUNITY_NAME,
} from "../../utils.js";

test.describe("community home page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    // Load the community page for the desktop snapshot.
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    // Verify desktop community content is ready.
    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    // Capture the desktop about section snapshot.
    await expectRegionScreenshot(
      page,
      getCommunityAboutSection(page),
      "community-home-desktop.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the community page for the mobile snapshot.
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    // Verify mobile community content is ready.
    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    // Capture the mobile about section snapshot.
    await expectRegionScreenshot(
      page,
      getCommunityAboutSection(page),
      "community-home-mobile.png",
      { testInfo, useClippedPageScreenshot: true },
    );
  });
});
