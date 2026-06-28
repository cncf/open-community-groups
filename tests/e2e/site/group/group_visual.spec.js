import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getIntroSection,
  navigateToGroup,
  TEST_ALLIANCE_NAME,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
} from "../../utils.js";

test.describe("group page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    // Load the group page for the desktop snapshot.
    await navigateToGroup(
      page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
    );

    // Verify desktop group content is ready.
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Join group" }),
    ).toBeVisible();
    await expect(
      page.getByText("Upcoming Events", { exact: true }),
    ).toBeVisible();

    // Capture the desktop intro section snapshot.
    await expectRegionScreenshot(
      page,
      getIntroSection(page),
      "group-page-desktop.png",
      { testInfo, useClippedPageScreenshot: true },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the group page for the mobile snapshot.
    await navigateToGroup(
      page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
    );

    // Verify mobile group content is ready.
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Join group" }),
    ).toBeVisible();
    await expect(
      page.getByText("Upcoming Events", { exact: true }),
    ).toBeVisible();

    // Capture the mobile intro section snapshot.
    await expectRegionScreenshot(
      page,
      getIntroSection(page),
      "group-page-mobile.png",
      {
        testInfo,
        useClippedPageScreenshot: true,
        maxDiffPixelRatio: process.env.CI === "true" ? 0.12 : undefined,
      },
    );
  });
});
