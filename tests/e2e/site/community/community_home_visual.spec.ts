import { expect, test } from "@playwright/test";

import {
  expectPageScreenshot,
  getSectionByHeading,
  navigateToCommunityHome,
  TEST_COMMUNITY_DESCRIPTION,
  TEST_COMMUNITY_NAME,
} from "../../utils";

const getDynamicCommunitySectionMasks = (page: Parameters<typeof expectPageScreenshot>[0]) => [
  getSectionByHeading(page, "Upcoming In-Person Events"),
  getSectionByHeading(page, "Upcoming Virtual Events"),
  getSectionByHeading(page, "Latest groups added"),
];

test.describe("community home page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }) => {
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    await expectPageScreenshot(page, "community-home-desktop.png", {
      mask: getDynamicCommunitySectionMasks(page),
    });
  });

  test("matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    await expectPageScreenshot(page, "community-home-mobile.png", {
      mask: getDynamicCommunitySectionMasks(page),
      maxDiffPixelRatio: 0.012,
    });
  });
});
