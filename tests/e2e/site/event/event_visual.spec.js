import { expect, test } from "@playwright/test";

import {
  expectRegionScreenshot,
  getIntroSection,
  navigateToEvent,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
} from "../../utils.js";

test.describe("event page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    // Load the event page.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Verify visual readiness.
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();
    await expect(
      page.getByText("About this event", { exact: true }),
    ).toBeVisible();

    // Capture the event intro.
    await expectRegionScreenshot(
      page,
      getIntroSection(page),
      "event-page-desktop.png",
      { testInfo },
    );
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the event page.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Verify visual readiness.
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();
    await expect(
      page.getByText("About this event", { exact: true }),
    ).toBeVisible();

    // Capture the mobile event intro.
    await expectRegionScreenshot(
      page,
      getIntroSection(page),
      "event-page-mobile.png",
      { testInfo, useClippedPageScreenshot: true },
    );
  });
});
