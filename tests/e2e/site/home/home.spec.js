import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_COMMUNITY_TITLE,
  TEST_COMMUNITY_TITLE_2,
  TEST_EVENT_NAMES,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_SITE_TITLE,
} from "../../seed.js";
import {
  getCommunityBanner,
  getSectionLink,
  getStatsContainer,
  getStatValue,
  navigateToSiteHome,
} from "../../utils.js";

// Site home explore links are currently hardcoded to cncf in shared templates.
const SITE_HOME_EXPLORE_COMMUNITY_NAME = "cncf";

const EXPLORE_LINK_VIEWPORTS = [
  { name: "desktop", width: 1280 },
  { name: "mobile", width: 375 },
];

test.describe("site home page", () => {
  test.describe.configure({ timeout: 75_000 });

  test.describe("default viewport", () => {
    test.beforeEach(async ({ page }) => {
      // Load the public home page before each default viewport assertion.
      await navigateToSiteHome(page);
    });

    test("jumbotron renders with title, description, and CTA link", async ({ page }) => {
      // Verify the jumbotron exposes the primary explore CTA.
      await expect(page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE })).toBeVisible();

      // Verify the jumbotron description and CTA destination.
      await expect(page.locator(".jumbotron-description")).toBeVisible();

      // Find the Explore groups and events control.
      const ctaLink = page.getByRole("link", {
        name: "Explore groups and events",
      });
      await expect(ctaLink).toBeVisible();
      await expect(ctaLink).toHaveAttribute("href", /\/explore/);
    });

    test("communities section lists community cards with correct links", async ({ page }) => {
      // Verify community cards link to their public community pages.
      await expect(page.getByText("Communities")).toBeVisible();

      // Target the first community card link.
      const community1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE} banner`) });
      await expect(community1Link).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME}`);

      // Target the second community card link.
      const community2Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE_2} banner`) });
      await expect(community2Link).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME_2}`);
    });

    test("upcoming in-person events section renders with title", async ({ page }) => {
      // Verify the in-person events section heading is present.
      await expect(page.getByText("upcoming in-person events")).toBeVisible();
    });

    test("upcoming virtual events section renders with title", async ({ page }) => {
      // Verify the virtual events section heading is present.
      await expect(page.getByText("upcoming virtual events")).toBeVisible();
    });

    test("upcoming in-person events shows seeded event cards", async ({ page }) => {
      // Verify the in-person events section shows a published event.
      await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    });

    test("upcoming virtual events shows seeded event cards", async ({ page }) => {
      // Verify the virtual events section shows a published event.
      await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();
    });

    test("paid seeded event cards show price badges", async ({ page }) => {
      // Target paid in-person and hybrid event cards.
      const inPersonCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.gamma[0] }).first();
      const hybridCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.beta[2] }).first();

      // Verify paid event cards show their starting prices.
      await expect(inPersonCard).toContainText(/From (?:US)?\$20\.00/);
      await expect(hybridCard).toContainText(/From (?:US)?\$15\.00/);
    });

    test("latest groups section renders heading and explore link", async ({ page }) => {
      // Verify the latest groups section exposes its explore link.
      await expect(page.getByText("Latest groups added")).toBeVisible();

      // Target the latest groups explore link.
      const exploreGroupsLinks = page.getByRole("link", {
        name: "Explore all groups",
      });
      await expect(exploreGroupsLinks.first()).toBeVisible();
    });

    test("event and group cards expose complete seeded metadata", async ({ page }) => {
      // Find the in-person event card and verify its group, venue, and date.
      const inPersonEventCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.alpha[0] }).first();
      await expect(inPersonEventCard).toContainText(`${TEST_COMMUNITY_TITLE} · Platform Ops Meetup`);
      await expect(inPersonEventCard).toContainText("Tech Conference Center, New York");
      await expect(inPersonEventCard).toContainText(/\w{3} \d{1,2}, \d{4}/);

      // Find the virtual event card and verify its location label.
      const virtualEventCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.alpha[1] }).first();
      await expect(virtualEventCard).toContainText("Virtual");

      // Find the hybrid event card and verify its fallback metadata.
      const hybridEventCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.alpha[2] }).first();
      await expect(hybridEventCard).toContainText("No location provided");
      await expect(hybridEventCard).toContainText("hybrid");

      // Find the group card and verify its community, region, location, and URL.
      const groupCard = page.getByRole("link").filter({ hasText: TEST_GROUP_NAME }).last();
      await expect(groupCard).toContainText(`${TEST_COMMUNITY_TITLE} · North America`);
      await expect(groupCard).toContainText("No location provided");
      await expect(groupCard).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`);
    });
  });

  test.describe("explore links", () => {
    for (const viewport of EXPLORE_LINK_VIEWPORTS) {
      test(`explore events and groups links route correctly on ${viewport.name}`, async ({ page }) => {
        // Load the public home page at the requested viewport.
        await page.setViewportSize({ width: viewport.width, height: 900 });
        await navigateToSiteHome(page);

        // Verify the events link points to the filtered explore page.
        const linkLayout = viewport.name === "desktop" ? "desktop" : "mobile";
        const eventsLink = getSectionLink(
          page,
          "upcoming in-person events",
          "Explore all events",
          linkLayout,
        );
        await expect(eventsLink).toBeVisible();
        await expect(eventsLink).toHaveAttribute(
          "href",
          `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=events`,
        );

        // Verify the groups link points to the filtered explore page.
        const groupsLink = getSectionLink(page, "Latest groups added", "Explore all groups", linkLayout);
        await expect(groupsLink).toBeVisible();
        await expect(groupsLink).toHaveAttribute(
          "href",
          `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=groups`,
        );
      });
    }
  });

  test.describe("desktop viewport", () => {
    test.beforeEach(async ({ page }) => {
      // Load the public home page before each desktop assertion.
      await navigateToSiteHome(page);
    });

    test("stats strip displays non-empty numeric values", async ({ page }) => {
      // Target the desktop site stats strip.
      const desktopStats = getStatsContainer(page, "site", "desktop");
      const statLabels = ["Groups", "Members", "Events", "Attendees"];

      // Assert each expected case.
      for (const label of statLabels) {
        // Verify the current desktop stat has a numeric value.
        const valueElement = getStatValue(desktopStats, label);
        await expect(valueElement).toBeVisible();
        await expect(valueElement).toHaveText(/^\d[\d,]*$/);
      }
    });

    test("stats strip shows desktop layout at lg breakpoint", async ({ page }) => {
      // Verify the desktop stats strip is visible at the large breakpoint.
      const desktopStats = getStatsContainer(page, "site", "desktop");
      await expect(desktopStats).toBeVisible();
    });

    test("community cards render on desktop with correct links", async ({ page }) => {
      // Target the first desktop community card.
      const community1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE} banner`) })
        .first();

      // Verify desktop community cards link to public community pages.
      await expect(community1Link).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME}`);

      // Set up community2 link.
      const community2Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE_2} banner`) })
        .first();
      await expect(community2Link).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME_2}`);
    });

    test("community banners use display name in alt text", async ({ page }) => {
      // Verify community banners use display names in alt text.
      await expect(getCommunityBanner(page, TEST_COMMUNITY_TITLE)).toBeVisible();

      // Verify the second community banner also uses its display name.
      await expect(getCommunityBanner(page, TEST_COMMUNITY_TITLE_2)).toBeVisible();
    });
  });

  test.describe("mobile viewport @mobile", () => {
    test.beforeEach(async ({ page }) => {
      // Load the public home page before each mobile assertion.
      await navigateToSiteHome(page);
    });

    test("stats strip shows mobile layout below lg breakpoint", async ({ page }) => {
      // Verify the mobile stats strip is visible below the large breakpoint.
      const mobileStats = getStatsContainer(page, "site", "mobile");
      await expect(mobileStats).toBeVisible();
    });

    test("community cards render on mobile with correct links", async ({ page }) => {
      // Target the mobile banner for the first community card.
      const mobileBanner = getCommunityBanner(page, TEST_COMMUNITY_TITLE);

      // Verify the mobile community card links to its public page.
      await expect(mobileBanner).toBeVisible();

      // Target the mobile community card link.
      const community1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE} banner`) })
        .first();
      await expect(community1Link).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME}`);
    });
  });
});
