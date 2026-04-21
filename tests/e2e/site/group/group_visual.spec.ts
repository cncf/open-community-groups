import { expect, test } from "@playwright/test";

import {
  expectPageScreenshot,
  navigateToGroup,
  TEST_COMMUNITY_NAME,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
} from "../../utils";

const getDynamicGroupEventMasks = (page: Parameters<typeof expectPageScreenshot>[0]) => [
  page.getByText("Next event", { exact: true }).locator("xpath=ancestor::div[2]"),
  page.getByText("Upcoming Events", { exact: true }).locator("xpath=ancestor::div[2]"),
  page.getByText("Past Events", { exact: true }).locator("xpath=ancestor::div[2]"),
];

test.describe("group page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }) => {
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha }),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Join group" })).toBeVisible();
    await expect(page.getByText("Upcoming Events", { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "group-page-desktop.png", {
      mask: getDynamicGroupEventMasks(page),
    });
  });

  test("matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha }),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Join group" })).toBeVisible();
    await expect(page.getByText("Upcoming Events", { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "group-page-mobile.png", {
      mask: getDynamicGroupEventMasks(page),
    });
  });
});
