import { expect, test } from "../../fixtures.js";

import {
  TEST_COHOSTED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
} from "../../seed.js";
import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { getIntroSection, navigateToEvent } from "../../utils.js";

// Dates, the agenda and the people lists are left out: dates follow the seed day, and other
// tests change the seeded event's sessions, attendees and team.
test.describe("event page ARIA snapshots", () => {
  test("matches the desktop regions", async ({ page }) => {
    // Load the event page and check its layout.
    const { breadcrumb, summary } = await openEvent(page);

    // Capture the breadcrumb links.
    await expectAriaSnapshot(page, breadcrumb, "event-breadcrumb-desktop");

    // Capture the summary; its remaining capacity varies.
    await expectAriaSnapshot(page, summary, "event-summary-desktop");
  });

  test("matches the mobile regions @mobile", async ({ page }) => {
    // Load the event page and check its layout.
    const { breadcrumb, summary } = await openEvent(page);

    // Capture the breadcrumb, which collapses into a select on mobile.
    await expectAriaSnapshot(page, breadcrumb, "event-breadcrumb-mobile");

    // Capture the summary; its remaining capacity varies.
    await expectAriaSnapshot(page, summary, "event-summary-mobile");
  });

  test("matches the desktop co-hosts list", async ({ page }) => {
    // Load the co-hosted event and check its layout.
    const cohosts = await openCohostedEvent(page);

    // Capture the co-host links.
    await expectAriaSnapshot(page, cohosts, "event-cohosts");
  });

  test("matches the mobile co-hosts list @mobile", async ({ page }) => {
    // Load the co-hosted event and check its layout.
    const cohosts = await openCohostedEvent(page);

    // Capture the co-host links.
    await expectAriaSnapshot(page, cohosts, "event-cohosts");
  });
});

/** Opens the seeded co-hosted event, checks its layout and returns the co-hosts list. */
const openCohostedEvent = async (page) => {
  const cohosts = page.getByRole("list", { name: "Co-hosts" });
  await navigateToEvent(
    page,
    TEST_COMMUNITY_NAME_2,
    TEST_GROUP_SLUGS.community2.epsilon,
    TEST_COHOSTED_EVENT.slug,
  );
  await expect(page.getByRole("heading", { level: 1, name: TEST_COHOSTED_EVENT.name })).toBeVisible();
  await expectPageLayout(page, { regions: [cohosts] });
  return cohosts;
};

/** Opens the seeded event page, checks its layout and returns its key regions. */
const openEvent = async (page) => {
  const breadcrumb = page.getByRole("navigation", { name: "Breadcrumb" });
  const summary = getIntroSection(page);
  await navigateToEvent(
    page,
    TEST_COMMUNITY_NAME,
    TEST_GROUP_SLUGS.community1.alpha,
    TEST_EVENT_SLUGS.alpha[0],
  );
  await expect(page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] })).toBeVisible();
  await expectPageLayout(page, { regions: [breadcrumb, summary] });
  return { breadcrumb, summary };
};
