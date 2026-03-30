import { expect, test } from "@playwright/test";

import {
  expectPageScreenshot,
  navigateToEvent,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
} from "../../utils";

test.describe("event page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }) => {
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

  test("matches mobile snapshot @mobile", async ({ page }) => {
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
