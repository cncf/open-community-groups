import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getAllianceAboutSection,
  navigateToAllianceHome,
  TEST_ALLIANCE_DESCRIPTION,
  TEST_ALLIANCE_NAME,
} from "../../utils.js";

test.describe("alliance home page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    // Load the alliance page for the desktop snapshot.
    await navigateToAllianceHome(page, TEST_ALLIANCE_NAME);

    // Verify desktop alliance content is ready.
    await expect(page.getByText("About this alliance")).toBeVisible();
    await expect(
      page.getByText(TEST_ALLIANCE_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    // Capture the desktop about section snapshot.
    await expectRegionScreenshot(
      page,
      getAllianceAboutSection(page),
      "alliance-home-desktop.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the alliance page for the mobile snapshot.
    await navigateToAllianceHome(page, TEST_ALLIANCE_NAME);

    // Verify mobile alliance content is ready.
    await expect(page.getByText("About this alliance")).toBeVisible();
    await expect(
      page.getByText(TEST_ALLIANCE_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    // Capture the mobile about section snapshot.
    await expectRegionScreenshot(
      page,
      getAllianceAboutSection(page),
      "alliance-home-mobile.png",
      { testInfo, useClippedPageScreenshot: true },
    );
  });
});
