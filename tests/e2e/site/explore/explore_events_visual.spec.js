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
    // Load the events explore page for the desktop snapshot.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Verify desktop search and event content are ready.
    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true }),
    ).toBeVisible();

    // Capture the desktop search row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search events"),
      "explore-events-desktop.png",
      { testInfo },
    );

    // Capture the desktop controls row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreControlsRow(page),
      "explore-events-desktop-controls.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the events explore page for the mobile snapshot.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Verify mobile search and event content are ready.
    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true }),
    ).toBeVisible();

    // Capture the mobile search row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search events"),
      "explore-events-mobile.png",
      { testInfo, useClippedPageScreenshot: true },
    );

    // Capture the mobile controls row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreControlsRow(page),
      "explore-events-mobile-controls.png",
      { testInfo, useClippedPageScreenshot: true },
    );
  });
});
