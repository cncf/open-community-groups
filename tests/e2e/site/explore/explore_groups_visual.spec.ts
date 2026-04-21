import { expect, test } from "@playwright/test";

import {
  expectPageScreenshot,
  navigateToPath,
  TEST_COMMUNITY_NAME,
  TEST_GROUP_NAMES,
} from "../../utils";

const getDynamicExploreGroupMasks = (page: Parameters<typeof expectPageScreenshot>[0]) => [
  page.locator("main article"),
];

test.describe("site explore groups page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "explore-groups-desktop.png", {
      mask: getDynamicExploreGroupMasks(page),
    });
  });

  test("matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "explore-groups-mobile.png", {
      mask: getDynamicExploreGroupMasks(page),
    });
  });
});
