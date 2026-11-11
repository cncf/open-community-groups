import { expect, test } from "../../fixtures.js";

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
import { enableDesktopVersion } from "../../snapshots.js";
import { getCommunityBanner, getSectionLink, navigateToSiteHome } from "../../utils.js";
import {
  expectLatestGroupsSection,
  expectNumericStats,
  expectPaidEventPriceBadges,
  expectUpcomingEventSections,
} from "../common/helpers.js";

const EXPLORE_LINK_VIEWPORTS = [
  { name: "desktop", width: 1280 },
  { name: "mobile", width: 375 },
];

const EXPLORE_IN_PERSON_EVENTS_PATH = "/explore?entity=events&kind[0]=in-person&kind[1]=hybrid";
const EXPLORE_LATEST_GROUPS_PATH = "/explore?entity=groups&sort_by=date";
const EXPLORE_VIRTUAL_EVENTS_PATH = "/explore?entity=events&kind[0]=virtual&kind[1]=hybrid";

const EXPLORE_SECTION_LINKS = [
  {
    heading: "upcoming in-person events",
    linkName: "Explore all events",
    href: EXPLORE_IN_PERSON_EVENTS_PATH,
  },
  {
    heading: "upcoming virtual events",
    linkName: "Explore all events",
    href: EXPLORE_VIRTUAL_EVENTS_PATH,
  },
  {
    heading: "Latest groups added",
    linkName: "Explore all groups",
    href: EXPLORE_LATEST_GROUPS_PATH,
  },
];

test.describe("site home page", () => {
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

    test("listing sections show seeded events, prices, and groups", async ({ page }) => {
      // Verify the shared public listing sections render seeded content.
      await expectUpcomingEventSections(page, {
        inPerson: [TEST_EVENT_NAMES.alpha[0]],
        virtual: [TEST_EVENT_NAMES.alpha[1]],
      });
      await expectPaidEventPriceBadges(page);
      await expectLatestGroupsSection(page);
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

        // Verify each section link opens the Explore view matching its preview.
        for (const { heading, linkName, href } of EXPLORE_SECTION_LINKS) {
          const sectionLink = getSectionLink(page, heading, linkName);
          await expect(sectionLink).toBeVisible();
          await expect(sectionLink).toHaveAttribute("href", href);
        }
      });
    }
  });

  test.describe("desktop viewport", () => {
    test.beforeEach(async ({ page }) => {
      // Load the public home page before each desktop assertion.
      await navigateToSiteHome(page);
    });

    test("stats strip displays numeric values at lg breakpoint", async ({ page }) => {
      // Verify the desktop stats strip shows a number for every stat.
      await expectNumericStats(page, "site", "desktop");
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

    test("stats strip displays numeric values below lg breakpoint", async ({ page }) => {
      // Verify the mobile stats strip shows a number for every stat.
      await expectNumericStats(page, "site", "mobile");
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

    test("hero carries the gradient and keeps the desktop Explore link", async ({ page }) => {
      // Find the hero around the introduction region.
      const introduction = page.getByRole("region", { name: "Site introduction" });
      const hero = introduction.locator("../..");

      // Verify the gradient moved onto the hero with the phone wrapper gone.
      expect(await hero.evaluate((element) => getComputedStyle(element).backgroundImage)).toContain(
        "linear-gradient",
      );

      // Verify the desktop link stays, with no search in its place.
      await expect(introduction.getByRole("link", { name: "Explore groups and events" })).toBeVisible();
      await expect(introduction.getByRole("search")).toHaveCount(0);
    });

    test("stats box lays out as a two by two grid", async ({ page }) => {
      // Measure the four cells.
      const cells = await page.locator(".stat-box > *").evaluateAll((elements) =>
        elements.map((element) => {
          const { left, top } = element.getBoundingClientRect();
          return { left, top };
        }),
      );

      // Verify two rows of two.
      expect(cells).toHaveLength(4);
      expect(cells[0].top).toBe(cells[1].top);
      expect(cells[2].top).toBe(cells[3].top);
      expect(cells[2].top).toBeGreaterThan(cells[0].top);
      expect(cells[0].left).toBe(cells[2].left);
    });

    test("few communities stack at full width with no dots", async ({ page }) => {
      // Find the two seeded banners.
      const banners = [TEST_COMMUNITY_TITLE, TEST_COMMUNITY_TITLE_2].map((title) =>
        page.getByRole("link").filter({ has: page.getByAltText(`${title} banner`) }),
      );
      const boxes = await Promise.all(banners.map((banner) => banner.boundingBox()));
      const [first, second] = boxes.toSorted((a, b) => a.y - b.y);

      // Verify both show at once, one above the other, inside the 12px gutter.
      expect(first.x).toBe(12);
      expect(first.width).toBeCloseTo(page.viewportSize().width - 24, 0);
      expect(second.x).toBe(first.x);
      expect(second.y).toBeGreaterThan(first.y + first.height);

      // Verify there is nothing to swipe.
      await expect(page.locator("[data-snap-dots]")).toHaveCount(0);
    });

    test("listing headings offer a sentence case See all", async ({ page }) => {
      // Find the pills in the upcoming and groups headings.
      const eventsLink = page.getByRole("link", { name: "See all upcoming in-person events" });
      const groupsLink = page.getByRole("link", { name: "See all latest groups added" });

      // Verify they sit in their headings and reach Explore.
      await expect(eventsLink).toBeVisible();
      await expect(eventsLink).toHaveAttribute("href", EXPLORE_IN_PERSON_EVENTS_PATH);
      await expect(groupsLink).toBeVisible();
      await expect(groupsLink).toHaveAttribute("href", EXPLORE_LATEST_GROUPS_PATH);

      // Verify the strip's uppercase does not reach the pill.
      expect(await eventsLink.evaluate((element) => getComputedStyle(element).textTransform)).toBe("none");
      await expect(eventsLink).toHaveText("See all");

      // Verify the block under each list is gone and Communities has no pill.
      await expect(page.getByRole("link", { name: "Explore all events" })).toHaveCount(0);
      await expect(page.getByRole("link", { name: "Explore all groups" })).toHaveCount(0);
      await expect(page.locator(".section-strip", { hasText: "Communities" }).getByRole("link")).toHaveCount(
        0,
      );

      // Verify the pill navigates.
      await groupsLink.tap();
      await expect(page).toHaveURL(/\/explore\?entity=groups/);
    });

    test("cards show only the group name on mobile", async ({ page }) => {
      // Find an event card and its pre-header.
      const eventCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.alpha[0] }).first();
      const header = eventCard.locator(".card-header");
      const community = header.getByText(TEST_COMMUNITY_TITLE);
      const group = header.getByText("Platform Ops Meetup");

      // Verify the community name and its separator are hidden on phones, leaving only the group.
      await expect(community).toBeHidden();
      await expect(header.getByText("·")).toBeHidden();
      await expect(group).toBeVisible();
    });
  });

  test.describe("desktop version on a phone @mobile", () => {
    test("keeps the desktop home page", async ({ page }) => {
      // Load the home page in the desktop version.
      await enableDesktopVersion(page);
      await navigateToSiteHome(page);
      const introduction = page.getByRole("region", { name: "Site introduction" });

      // Verify the desktop link shows.
      await expect(introduction.getByRole("link", { name: "Explore groups and events" })).toBeVisible();

      // Verify the phone section strip does not stick.
      await expect(page.locator(".section-strip").first()).not.toHaveCSS("position", "sticky");
    });
  });
});
