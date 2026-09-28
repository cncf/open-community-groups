import { expect, test } from "@playwright/test";

import {
  TEST_COHOSTED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_EVENT_NAMES,
} from "../seed.js";
import { expectRegionScreenshot, getExploreControlsRow, getExploreSearchRow } from "./helpers.js";
import { navigateToPath } from "../utils.js";

test.describe("site explore events page visual regression @visual", () => {
  test("matches desktop snapshot", async ({ page }, testInfo) => {
    // Load the events explore page for the desktop snapshot.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);

    // Verify desktop search and event content are ready.
    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();

    // Capture the desktop search row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search events"),
      "explore-events-desktop.png",
      { testInfo },
    );

    // Capture the desktop controls row snapshot.
    await expectRegionScreenshot(page, getExploreControlsRow(page), "explore-events-desktop-controls.png", {
      testInfo,
    });
  });

  test("matches mobile snapshot @mobile", async ({ page }, testInfo) => {
    // Load the events explore page for the mobile snapshot.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);

    // Verify mobile search and event content are ready.
    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();

    // Capture the mobile search row snapshot.
    await expectRegionScreenshot(
      page,
      getExploreSearchRow(page, "Search events"),
      "explore-events-mobile.png",
      { testInfo, useClippedPageScreenshot: true },
    );

    // Capture the mobile controls row snapshot.
    await expectRegionScreenshot(page, getExploreControlsRow(page), "explore-events-mobile-controls.png", {
      testInfo,
      useClippedPageScreenshot: true,
    });
  });

  test("matches desktop co-hosted card snapshot", async ({ page }, testInfo) => {
    // Load the co-hosted card with its full co-host credit.
    const eventCard = await openCohostedEventCard(page, "full");

    // Capture the card with its relative date footer masked.
    await expectRegionScreenshot(page, eventCard, "explore-events-cohosted-card-desktop.png", {
      mask: [getEventCardFooter(eventCard)],
      testInfo,
    });
  });

  test("matches mobile co-hosted card snapshot @mobile", async ({ page }, testInfo) => {
    // Load the co-hosted card with its summarized co-host credit.
    const eventCard = await openCohostedEventCard(page, "summary");

    // Capture the card with its relative date footer masked.
    await expectRegionScreenshot(page, eventCard, "explore-events-cohosted-card-mobile.png", {
      mask: [getEventCardFooter(eventCard)],
      testInfo,
      useClippedPageScreenshot: true,
    });
  });
});

/** Selects the event card footer whose date follows the seed load time. */
const getEventCardFooter = (eventCard) => eventCard.locator("article > div.mt-auto");

/** Opens the owner community results and returns the settled co-hosted event card. */
const openCohostedEventCard = async (page, expectedFit) => {
  await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME_2}`);

  const eventCard = page.getByRole("link").filter({ hasText: TEST_COHOSTED_EVENT.name }).first();
  await expect(eventCard.locator("[data-cohosts-line]")).toHaveAttribute("data-cohosts-fit", expectedFit);
  return eventCard;
};
