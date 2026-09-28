import { expect, test } from "@playwright/test";

import {
  TEST_COHOSTED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
} from "../seed.js";
import { expectRegionScreenshot } from "./helpers.js";
import { getIntroSection, navigateToEvent } from "../utils.js";

test.describe("event page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    // Load the event page for the desktop snapshot.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Verify desktop event content is ready.
    await expect(page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] })).toBeVisible();
    await expect(page.getByText("About this event", { exact: true })).toBeVisible();

    // Capture the desktop event intro snapshot.
    await expectRegionScreenshot(page, getIntroSection(page), "event-page-desktop.png", { testInfo });
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the event page for the mobile snapshot.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Verify mobile event content is ready.
    await expect(page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] })).toBeVisible();
    await expect(page.getByText("About this event", { exact: true })).toBeVisible();

    // Capture the mobile event intro snapshot.
    await expectRegionScreenshot(page, getIntroSection(page), "event-page-mobile.png", {
      testInfo,
      useClippedPageScreenshot: true,
    });
  });

  test("matches desktop co-hosts snapshot", async ({ page }, testInfo) => {
    // Load the co-hosted event and capture its co-hosts box.
    const cohostsBox = await openCohostedEventBox(page);
    await expectRegionScreenshot(page, cohostsBox, "event-page-cohosts-desktop.png", { testInfo });
  });

  test("matches mobile co-hosts snapshot @mobile", async ({ page }, testInfo) => {
    // Load the co-hosted event and capture its stacked co-hosts box.
    const cohostsBox = await openCohostedEventBox(page);
    await expectRegionScreenshot(page, cohostsBox, "event-page-cohosts-mobile.png", {
      testInfo,
      useClippedPageScreenshot: true,
    });
  });
});

/** Opens the seeded co-hosted event and returns its ready co-hosts box. */
const openCohostedEventBox = async (page) => {
  await navigateToEvent(
    page,
    TEST_COMMUNITY_NAME_2,
    TEST_GROUP_SLUGS.community2.epsilon,
    TEST_COHOSTED_EVENT.slug,
  );
  await expect(page.getByRole("heading", { level: 1, name: TEST_COHOSTED_EVENT.name })).toBeVisible();

  const cohostsList = page.getByRole("list", { name: "Co-hosts" });
  await expect(cohostsList.getByRole("listitem")).toHaveCount(3);
  return cohostsList.locator("xpath=ancestor::div[2]");
};
