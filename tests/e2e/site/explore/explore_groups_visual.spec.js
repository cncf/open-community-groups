import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getExploreControlsRow,
  getExploreSearchRow,
  navigateToPath,
  TEST_COMMUNITY_NAME,
  TEST_GROUP_NAMES,
} from "../../utils.js";

test.describe("site explore groups page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    // Load the groups explore page for the desktop snapshot.
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Verify desktop search and group content are ready.
    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
    await expect(
      page.getByText(TEST_GROUP_NAMES.alpha, { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_GROUP_NAMES.gamma, { exact: true }),
    ).toBeVisible();

    // Capture the desktop search row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search groups"),
      "explore-groups-desktop.png",
      { testInfo },
    );

    // Capture the desktop controls row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreControlsRow(page),
      "explore-groups-desktop-controls.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the groups explore page for the mobile snapshot.
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Verify mobile search and group content are ready.
    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
    await expect(
      page.getByText(TEST_GROUP_NAMES.alpha, { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_GROUP_NAMES.gamma, { exact: true }),
    ).toBeVisible();

    // Capture the mobile search row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search groups"),
      "explore-groups-mobile.png",
      { testInfo, useClippedPageScreenshot: true },
    );

    // Capture the mobile controls row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreControlsRow(page),
      "explore-groups-mobile-controls.png",
      { testInfo, useClippedPageScreenshot: true },
    );
  });
});
