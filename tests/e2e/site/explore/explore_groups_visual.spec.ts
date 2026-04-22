import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getExploreChromeRow,
  navigateToPath,
  TEST_COMMUNITY_NAME,
  TEST_GROUP_NAMES,
} from "../../utils";

test.describe("site explore groups page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();

    await expectRegionScreenshot(page, getExploreChromeRow(page, 0), "explore-groups-desktop.png");
    await expectRegionScreenshot(
      page,
      getExploreChromeRow(page, 1),
      "explore-groups-desktop-controls.png",
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();

    await expectRegionScreenshot(page, getExploreChromeRow(page, 0), "explore-groups-mobile.png");
    await expectRegionScreenshot(
      page,
      getExploreChromeRow(page, 1),
      "explore-groups-mobile-controls.png",
    );
  });
});
