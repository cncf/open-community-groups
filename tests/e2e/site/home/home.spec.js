import { readFileSync } from "node:fs";

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
import { getCommunityBanner, getPageOverflow, getSectionLink, navigateToSiteHome } from "../../utils.js";
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

// The seed has two communities, so the carousel case borrows the template's own tokens.
const HOME_TEMPLATE = readFileSync(
  new URL("../../../../ocg-server/templates/site/home/page.html", import.meta.url),
  "utf8",
);
const [CAROUSEL_LIST_TOKENS, CAROUSEL_PAGE_TOKENS] = [
  ...HOME_TEMPLATE.matchAll(/{% if carousel %}(.*?){% (?:else|endif) %}/g),
].map(([, tokens]) => tokens);

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

        // Verify the events link points to the explore page.
        const linkLayout = viewport.name === "desktop" ? "desktop" : "mobile";
        const eventsLink = getSectionLink(
          page,
          "upcoming in-person events",
          "Explore all events",
          linkLayout,
        );
        await expect(eventsLink).toBeVisible();
        await expect(eventsLink).toHaveAttribute("href", "/explore?entity=events");

        // Verify the groups link points to the explore page.
        const groupsLink = getSectionLink(page, "Latest groups added", "Explore all groups", linkLayout);
        await expect(groupsLink).toBeVisible();
        await expect(groupsLink).toHaveAttribute("href", "/explore?entity=groups");
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

    test("many communities swipe in pages of three with dots that follow the scroll", async ({ page }) => {
      // Rebuild the seeded list as the template renders five communities: pages of three and two.
      await page.evaluate(
        async ({ listTokens, pageTokens }) => {
          const tile = document.querySelector("a[href='/e2e-second-community']");
          const firstPage = tile.parentElement;
          const list = firstPage.parentElement;
          list.classList.remove("phone:grid-cols-1");
          list.classList.add(...listTokens.split(" "));
          firstPage.append(tile.cloneNode(true));
          const secondPage = firstPage.cloneNode(false);
          secondPage.append(tile.cloneNode(true), tile.cloneNode(true));
          list.append(secondPage);
          [...list.children].forEach((item) => item.classList.add(...pageTokens.split(" ")));
          list.insertAdjacentHTML(
            "afterend",
            '<div class="not-phone:hidden" aria-hidden="true" data-snap-dots></div>',
          );
          // The server hashes asset names, so reuse the URL the page already loaded.
          const { src } = document.querySelector("script[src*='/snap-dots']");
          const { syncSnapDots } = await import(src);
          syncSnapDots();
        },
        { listTokens: CAROUSEL_LIST_TOKENS, pageTokens: CAROUSEL_PAGE_TOKENS },
      );

      // Verify the first page stacks its three banners in one column.
      const firstPageBanners = await page.locator("[data-snap-dots]").evaluate((row) =>
        [...row.previousElementSibling.children[0].children].map((tile) => {
          const { height, x, y } = tile.getBoundingClientRect();
          return { height, x, y };
        }),
      );
      expect(firstPageBanners).toHaveLength(3);
      expect(firstPageBanners[1].x).toBe(firstPageBanners[0].x);
      expect(firstPageBanners[2].y).toBeGreaterThan(firstPageBanners[1].y + firstPageBanners[1].height);

      // Verify a dot per page with the first active.
      const dots = page.locator("[data-snap-dots] .snap-dot");
      await expect(dots).toHaveCount(2);
      await expect(dots.nth(0)).toHaveAttribute("data-active");

      // Verify the page itself does not scroll sideways.
      expect(await getPageOverflow(page)).toBeLessThanOrEqual(0);

      // Verify the dots follow the swipe position.
      await page.evaluate(() => {
        const list = document.querySelector("[data-snap-dots]").previousElementSibling;
        list.scrollTo({
          behavior: "instant",
          left: list.children[1].offsetLeft - list.children[0].offsetLeft,
        });
      });
      await expect(dots.nth(1)).toHaveAttribute("data-active");
      await expect(dots.nth(0)).not.toHaveAttribute("data-active");
    });

    test("listing headings offer a sentence case See all", async ({ page }) => {
      // Find the pills in the upcoming and groups headings.
      const eventsLink = page.getByRole("link", { name: "See all upcoming in-person events" });
      const groupsLink = page.getByRole("link", { name: "See all latest groups added" });

      // Verify they sit in their headings and reach Explore.
      await expect(eventsLink).toBeVisible();
      await expect(eventsLink).toHaveAttribute("href", "/explore?entity=events");
      await expect(groupsLink).toBeVisible();
      await expect(groupsLink).toHaveAttribute("href", "/explore?entity=groups");

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

    test("card badges drop below the location when it would be cut short", async ({ page }) => {
      // Load the narrowest phone, where a paid hybrid card has two badges.
      await page.setViewportSize({ height: 640, width: 320 });
      await navigateToSiteHome(page);

      // Find the first location row holding both badges.
      const badges = page.locator(".icon-text + div:has(.custom-badge + .custom-badge)").first();
      const location = page.locator(".icon-text:has(+ div .custom-badge + .custom-badge)").first();
      await expect(badges).toBeVisible();

      // Verify the location keeps its width and the badges take the next line.
      const [locationBox, badgesBox] = await Promise.all([location.boundingBox(), badges.boundingBox()]);
      expect(locationBox.width).toBeGreaterThanOrEqual(96);
      expect(badgesBox.y).toBeGreaterThanOrEqual(locationBox.y + locationBox.height);
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
