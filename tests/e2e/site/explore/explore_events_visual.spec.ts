import { expect, test } from "@playwright/test";

import {
  expectPageScreenshot,
  navigateToPath,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
} from "../../utils";

const getDynamicExploreEventMasks = (page: Parameters<typeof expectPageScreenshot>[0]) => [
  page.locator("main article"),
];

test.describe("site explore events page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "explore-events-desktop.png", {
      mask: getDynamicExploreEventMasks(page),
    });
  });

  test("matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "explore-events-mobile.png", {
      mask: getDynamicExploreEventMasks(page),
    });
  });
});
