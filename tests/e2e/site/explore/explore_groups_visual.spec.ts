import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getExploreControlsRow,
  getExploreSearchRow,
  navigateToPath,
  TEST_COMMUNITY_NAME,
  TEST_GROUP_NAMES,
} from "../../utils";

test.describe("site explore groups page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();

    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search groups"),
      "explore-groups-desktop.png",
      { testInfo },
    );
    await expectRegionScreenshot(
      page,
      getExploreControlsRow(page),
      "explore-groups-desktop-controls.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();

    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search groups"),
      "explore-groups-mobile.png",
      { testInfo },
    );
    await expectRegionScreenshot(
      page,
      getExploreControlsRow(page),
      "explore-groups-mobile-controls.png",
      { testInfo },
    );
  });
});
