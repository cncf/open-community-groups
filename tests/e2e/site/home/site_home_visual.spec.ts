import { expect, test } from "@playwright/test";

import {
  expectPageScreenshot,
  getSectionByHeading,
  navigateToSiteHome,
  TEST_SITE_TITLE,
} from "../../utils";

const getDynamicHomeSectionMasks = (page: Parameters<typeof expectPageScreenshot>[0]) => [
  getSectionByHeading(page, "Upcoming In-Person Events"),
  getSectionByHeading(page, "Upcoming Virtual Events"),
  getSectionByHeading(page, "Latest groups added"),
];

test.describe("site home page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }) => {
    await navigateToSiteHome(page);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    await expectPageScreenshot(page, "site-home-desktop.png", {
      mask: getDynamicHomeSectionMasks(page),
    });
  });

  test("matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToSiteHome(page);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    await expectPageScreenshot(page, "site-home-mobile.png", {
      mask: getDynamicHomeSectionMasks(page),
    });
  });
});
