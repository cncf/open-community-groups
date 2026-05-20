import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getExploreControlsRow,
  getExploreSearchRow,
  navigateToPath,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
} from "../../utils.js";

test.describe("site explore events page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    // Load the filtered events view.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Verify visual readiness.
    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true }),
    ).toBeVisible();

    // Capture the search row.
    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search events"),
      "explore-events-desktop.png",
      { testInfo },
    );
    // Capture the controls row.
    await expectRegionScreenshot(
      page,
      getExploreControlsRow(page),
      "explore-events-desktop-controls.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the filtered events view.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Verify visual readiness.
    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true }),
    ).toBeVisible();

    // Capture the mobile search row.
    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search events"),
      "explore-events-mobile.png",
      { testInfo, useClippedPageScreenshot: true },
    );
    // Capture the mobile controls row.
    await expectRegionScreenshot(
      page,
      getExploreControlsRow(page),
      "explore-events-mobile-controls.png",
      { testInfo, useClippedPageScreenshot: true },
    );
  });
});
