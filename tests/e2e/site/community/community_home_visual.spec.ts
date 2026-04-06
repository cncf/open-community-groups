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
      mask: [
        page
          .getByText("Upcoming In-Person Events", { exact: true })
          .locator("xpath=ancestor::div[2]"),
        page
          .getByText("Upcoming Virtual Events", { exact: true })
          .locator("xpath=ancestor::div[2]"),
        page
          .getByText("Latest groups added", { exact: true })
          .locator("xpath=ancestor::div[2]"),
      ],
      maxDiffPixels: 100,
    });
  });
});
