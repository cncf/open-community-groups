import type { Page } from "@playwright/test";
import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_DESCRIPTION,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  TEST_SITE_TITLE,
  navigateToCommunityHome,
  navigateToEvent,
  navigateToGroup,
  navigateToSiteHome,
} from "../utils";

/** Waits for a page to settle before taking a visual snapshot. */
const expectPageScreenshot = async (page: Page, screenshotName: string) => {
  await page.waitForLoadState("networkidle");
  await page.evaluate(async () => {
    await document.fonts.ready;
  });

  await expect(page).toHaveScreenshot(screenshotName, {
    animations: "disabled",
    caret: "hide",
    fullPage: true,
  });
};

test.describe("visual regression", () => {
  test("site home matches desktop snapshot", async ({ page }) => {
    await navigateToSiteHome(page);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    await expectPageScreenshot(page, "site-home-desktop.png");
  });

  test("site home matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToSiteHome(page);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    ).toBeVisible();

    await expectPageScreenshot(page, "site-home-mobile.png");
  });

  test("community home matches desktop snapshot", async ({ page }) => {
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    await expectPageScreenshot(page, "community-home-desktop.png");
  });

  test("community home matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    await expect(page.getByText("About this community")).toBeVisible();
    await expect(
      page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
    ).toBeVisible();

    await expectPageScreenshot(page, "community-home-mobile.png");
  });

  test("group page matches desktop snapshot", async ({ page }) => {
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha }),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Join group" })).toBeVisible();
    await expect(page.getByText("Upcoming Events", { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "group-page-desktop.png");
  });

  test("group page matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha }),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Join group" })).toBeVisible();
    await expect(page.getByText("Upcoming Events", { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "group-page-mobile.png");
  });

  test("event page matches desktop snapshot", async ({ page }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();
    await expect(page.getByText("About this event", { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "event-page-desktop.png");
  });

  test("event page matches mobile snapshot @mobile", async ({ page }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();
    await expect(page.getByText("About this event", { exact: true })).toBeVisible();

    await expectPageScreenshot(page, "event-page-mobile.png");
  });
});
