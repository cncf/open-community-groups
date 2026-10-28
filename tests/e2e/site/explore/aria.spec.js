import { expect, test } from "../../fixtures.js";

import { TEST_COHOSTED_EVENT, TEST_COMMUNITY_NAME, TEST_COMMUNITY_NAME_2 } from "../../seed.js";
import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToPath } from "../../utils.js";

// Result lists are left out: other tests add events and groups to the seeded communities. The
// filters are left out too: their date range follows the current day.
test.describe("site explore page ARIA snapshots", () => {
  test("matches the desktop events results header", async ({ page }) => {
    // Load the events results and check the layout.
    const resultsHeader = await openExplore(page, "events");

    // Capture the search and results controls; the result count varies.
    await expectAriaSnapshot(page, resultsHeader, "explore-events-header-desktop");
  });

  test("matches the mobile events results header @mobile", async ({ page }) => {
    // Load the events results and check the layout.
    const resultsHeader = await openExplore(page, "events");

    // Capture the search and results controls; the result count varies.
    await expectAriaSnapshot(page, resultsHeader, "explore-events-header-mobile");
  });

  test("matches the desktop groups results header", async ({ page }) => {
    // Load the groups results and check the layout.
    const resultsHeader = await openExplore(page, "groups");

    // Capture the search and results controls; the result count varies.
    await expectAriaSnapshot(page, resultsHeader, "explore-groups-header-desktop");
  });

  test("matches the mobile groups results header @mobile", async ({ page }) => {
    // Load the groups results and check the layout.
    const resultsHeader = await openExplore(page, "groups");

    // Capture the search and results controls; the result count varies.
    await expectAriaSnapshot(page, resultsHeader, "explore-groups-header-mobile");
  });

  test("matches the desktop co-hosted event card", async ({ page }) => {
    // Load the owner community results and find the co-hosted card.
    const eventCard = await openCohostedEventCard(page);

    // Capture the card with its full co-host credit; its dates follow the seed day.
    await expectAriaSnapshot(page, eventCard, "explore-cohosted-card-desktop");
  });

  test("matches the mobile co-hosted event card @mobile", async ({ page }) => {
    // Load the owner community results and find the co-hosted card.
    const eventCard = await openCohostedEventCard(page);

    // Capture the card with its co-host credit; its dates follow the seed day.
    await expectAriaSnapshot(page, eventCard, "explore-cohosted-card-mobile");
  });
});

/** Opens the owner community event results and returns the co-hosted event card. */
const openCohostedEventCard = async (page) => {
  await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME_2}`);
  const eventCard = page.getByRole("link").filter({ hasText: TEST_COHOSTED_EVENT.name }).first();
  await expect(eventCard).toBeVisible();
  await expectPageLayout(page, { regions: [eventCard] });
  return eventCard;
};

/**
 * Opens the seeded community results for an entity, checks the layout and returns the results
 * header.
 */
const openExplore = async (page, entity) => {
  const resultsHeader = page.locator("#explore-results-header");
  await navigateToPath(page, `/explore?entity=${entity}&community[0]=${TEST_COMMUNITY_NAME}`);
  await expect(page.getByPlaceholder(`Search ${entity}`)).toBeVisible();
  await expectPageLayout(page, { regions: [resultsHeader] });
  return resultsHeader;
};
