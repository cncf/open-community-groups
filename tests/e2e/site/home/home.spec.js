import { expect, test } from "@playwright/test";

import {
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_BANNER_MOBILE_URL,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_COMMUNITY_TITLE,
  TEST_COMMUNITY_TITLE_2,
  TEST_EVENT_NAMES,
  TEST_SITE_TITLE,
  getCommunityBanner,
  getSectionLink,
  getStatsContainer,
  getStatValue,
  navigateToSiteHome,
} from "../../utils.js";

const COMMUNITY_CARD_MAX_WIDTH = 385;
// Site home explore links are currently hardcoded to cncf in shared templates.
const SITE_HOME_EXPLORE_COMMUNITY_NAME = "cncf";

const getCommunitiesGrid = (page) =>
  page
    .getByText("Communities", { exact: true })
    .locator("..")
    .locator("div.grid");

const getCommunityCard = (page, displayName) =>
  page
    .getByRole("link")
    .filter({ has: getCommunityBanner(page, displayName) })
    .first();

test.describe("site home page", () => {
  test.describe("default viewport", () => {
    test.beforeEach(async ({ page }) => {
      // Load the public home page before each default viewport assertion.
      await navigateToSiteHome(page);
    });

    test("jumbotron renders with title, description, and CTA link", async ({
      page,
    }) => {
      // Verify the jumbotron exposes the primary explore CTA.
      await expect(
        page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
      ).toBeVisible();

      // Verify the jumbotron description and CTA destination.
      await expect(page.locator(".jumbotron-description")).toBeVisible();

      // Find the Explore groups and events control.
      const ctaLink = page.getByRole("link", {
        name: "Explore groups and events",
      });
      await expect(ctaLink).toBeVisible();
      await expect(ctaLink).toHaveAttribute("href", /\/explore/);
    });

    test("stats strip displays all stat labels with values", async ({
      page,
    }) => {
      // Assert each site stat label in the default stats strip.
      const statLabels = ["Groups", "Members", "Events", "Attendees"];
      for (const label of statLabels) {
        // Verify the current stat label is visible.
        await expect(
          page.getByText(label, { exact: true }).first(),
        ).toBeVisible();
      }
    });

    test("communities section lists community cards with correct links", async ({
      page,
    }) => {
      // Verify community cards link to their public community pages.
      await expect(page.getByText("Communities")).toBeVisible();

      // Target the first community card link.
      const community1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE} banner`) });
      await expect(community1Link).toHaveAttribute(
        "href",
        `/${TEST_COMMUNITY_NAME}`,
      );

      // Target the second community card link.
      const community2Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE_2} banner`) });
      await expect(community2Link).toHaveAttribute(
        "href",
        `/${TEST_COMMUNITY_NAME_2}`,
      );
    });

    test("upcoming in-person events section renders with title", async ({
      page,
    }) => {
      // Verify the in-person events section heading is present.
      await expect(page.getByText("upcoming in-person events")).toBeVisible();
    });

    test("upcoming virtual events section renders with title", async ({
      page,
    }) => {
      // Verify the virtual events section heading is present.
      await expect(page.getByText("upcoming virtual events")).toBeVisible();
    });

    test("upcoming in-person events shows seeded event cards", async ({
      page,
    }) => {
      // Verify the in-person events section shows a published event.
      await expect(
        page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true }),
      ).toBeVisible();
    });

    test("upcoming virtual events shows seeded event cards", async ({
      page,
    }) => {
      // Verify the virtual events section shows a published event.
      await expect(
        page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true }),
      ).toBeVisible();
    });

    test("paid seeded event cards show price badges", async ({ page }) => {
      // Skip price badge assertions when payments are disabled.
      test.skip(
        !E2E_PAYMENTS_ENABLED,
        "Payments are disabled in this environment.",
      );

      // Target paid in-person and virtual event cards.
      const inPersonCard = page
        .getByRole("link")
        .filter({ hasText: TEST_EVENT_NAMES.gamma[0] })
        .first();
      const virtualCard = page
        .getByRole("link")
        .filter({ hasText: TEST_EVENT_NAMES.beta[1] })
        .first();

      // Verify paid event cards show their starting prices.
      await expect(inPersonCard).toContainText(/From (?:US)?\$20\.00/);
      await expect(virtualCard).toContainText(/From (?:US)?\$15\.00/);
    });

    test("latest groups section renders heading and explore link", async ({
      page,
    }) => {
      // Verify the latest groups section exposes its explore link.
      await expect(page.getByText("Latest groups added")).toBeVisible();

      // Target the latest groups explore link.
      const exploreGroupsLinks = page.getByRole("link", {
        name: "Explore all groups",
      });
      await expect(exploreGroupsLinks.first()).toBeVisible();
    });

    test("groups grid renders in the latest groups section", async ({
      page,
    }) => {
      // Locate the latest groups grid on the public home page.
      const groupsGrid = page
        .getByText("Latest groups added", { exact: true })
        .locator("..")
        .locator("..")
        .locator("div.grid");

      // Verify the latest groups grid is visible.
      await expect(groupsGrid.first()).toBeVisible();
    });
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
        await expect(
          desktopStats.getByText(label, { exact: true }),
        ).toBeVisible();
        await expect(valueElement).toBeVisible();
        const text = await valueElement.textContent();
        expect(text?.trim()).toMatch(/^\d[\d,]*$/);
      }
    });

    test("stats strip shows desktop layout at lg breakpoint", async ({
      page,
    }) => {
      // Verify the desktop stats strip is visible at the large breakpoint.
      const desktopStats = getStatsContainer(page, "site", "desktop");
      await expect(desktopStats).toBeVisible();
    });

    test("community cards render on desktop with correct links", async ({
      page,
    }) => {
      // Target the first desktop community card.
      const community1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE} banner`) })
        .first();

      // Verify desktop community cards link to public community pages.
      await expect(community1Link).toHaveAttribute(
        "href",
        `/${TEST_COMMUNITY_NAME}`,
      );

      // Set up community2 link.
      const community2Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE_2} banner`) })
        .first();
      await expect(community2Link).toHaveAttribute(
        "href",
        `/${TEST_COMMUNITY_NAME_2}`,
      );
    });

    test("community banners use display name in alt text", async ({ page }) => {
      // Verify community banners use display names in alt text.
      await expect(
        getCommunityBanner(page, TEST_COMMUNITY_TITLE),
      ).toBeVisible();

      // Verify the second community banner also uses its display name.
      await expect(
        getCommunityBanner(page, TEST_COMMUNITY_TITLE_2),
      ).toBeVisible();
    });

    test("community cards show a darker inset shadow without resizing", async ({
      page,
    }) => {
      // Target the first community card and record its resting dimensions.
      const communityCard = page
        .getByRole("link")
        .filter({ has: getCommunityBanner(page, TEST_COMMUNITY_TITLE) })
        .first();
      const communityBanner = getCommunityBanner(page, TEST_COMMUNITY_TITLE);

      // Keep the card in view so hovering does not scroll and shift bounding boxes.
      await communityCard.scrollIntoViewIfNeeded();
      const restingBannerBox = await communityBanner.boundingBox();
      const restingCardBox = await communityCard.boundingBox();
      expect(restingBannerBox).not.toBeNull();
      expect(restingCardBox).not.toBeNull();
      await expect(communityCard).toHaveCSS("border-top-width", "1px");
      await expect(communityCard).toHaveCSS("box-shadow", "none");

      // Verify the overlay inset renders without changing element bounds.
      await communityCard.hover();
      await expect(communityCard).toHaveCSS("border-top-width", "1px");
      await expect(communityCard).toHaveCSS("box-shadow", "none");
      await expect
        .poll(() =>
          communityCard.evaluate(
            (element) => window.getComputedStyle(element, "::after").boxShadow,
          ),
        )
        .not.toBe("none");
      const hoveredBannerBox = await communityBanner.boundingBox();
      const hoveredCardBox = await communityCard.boundingBox();
      expect(hoveredBannerBox).toEqual(restingBannerBox);
      expect(hoveredCardBox).toEqual(restingCardBox);
    });

    test("community cards preserve their desktop size and gap", async ({
      page,
    }) => {
      // Target both community cards in the desktop grid, ordered by display name.
      const platformBanner = getCommunityBanner(page, TEST_COMMUNITY_TITLE);
      const firstCard = getCommunityCard(page, TEST_COMMUNITY_TITLE_2);
      const secondCard = getCommunityCard(page, TEST_COMMUNITY_TITLE);
      const communitiesGrid = getCommunitiesGrid(page);

      // Verify the mobile banner asset is used at the desktop viewport.
      await expect(platformBanner).toHaveAttribute(
        "src",
        TEST_COMMUNITY_BANNER_MOBILE_URL,
      );

      // Verify the desktop grid reserves three columns for community cards.
      const gridColumnCount = await communitiesGrid.evaluate(
        (element) =>
          window.getComputedStyle(element).gridTemplateColumns.split(" ")
            .length,
      );
      expect(gridColumnCount).toBe(3);

      // Verify both cards preserve their maximum width and desktop gap.
      const firstCardBox = await firstCard.boundingBox();
      const secondCardBox = await secondCard.boundingBox();
      const communitiesGridBox = await communitiesGrid.boundingBox();
      expect(firstCardBox).not.toBeNull();
      expect(secondCardBox).not.toBeNull();
      expect(communitiesGridBox).not.toBeNull();
      expect(firstCardBox.width).toBeLessThanOrEqual(COMMUNITY_CARD_MAX_WIDTH);
      expect(secondCardBox.width).toBeLessThanOrEqual(COMMUNITY_CARD_MAX_WIDTH);
      expect(firstCardBox.x).toBe(communitiesGridBox.x);
      expect(secondCardBox.y).toBe(firstCardBox.y);
      expect(secondCardBox.x - (firstCardBox.x + firstCardBox.width)).toBe(32);
    });

    test("explore all events link visible on desktop with correct href", async ({
      page,
    }) => {
      // Target the desktop explore link for in-person events.
      const desktopLink = getSectionLink(
        page,
        "upcoming in-person events",
        "Explore all events",
        "desktop",
      );

      // Verify the desktop events link points to the filtered explore page.
      await expect(desktopLink).toBeVisible();
      await expect(desktopLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=events`,
      );
    });

    test("explore all groups desktop link has correct href", async ({
      page,
    }) => {
      // Target the desktop explore link for latest groups.
      const desktopLink = getSectionLink(
        page,
        "Latest groups added",
        "Explore all groups",
        "desktop",
      );

      // Verify the desktop groups link points to the filtered explore page.
      await expect(desktopLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=groups`,
      );
    });

    test("explore all groups link visible on desktop", async ({ page }) => {
      // Target the desktop latest-groups explore link.
      const desktopExploreLink = getSectionLink(
        page,
        "Latest groups added",
        "Explore all groups",
        "desktop",
      );

      // Verify the desktop groups link is visible.
      await expect(desktopExploreLink).toBeVisible();
    });
  });

  test.describe("tablet viewport", () => {
    test.beforeEach(async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await navigateToSiteHome(page);
    });

    test("community cards preserve their tablet size and gap", async ({
      page,
    }) => {
      // Target both community cards in the tablet grid, ordered by display name.
      const firstCard = getCommunityCard(page, TEST_COMMUNITY_TITLE_2);
      const secondCard = getCommunityCard(page, TEST_COMMUNITY_TITLE);
      const communitiesGrid = getCommunitiesGrid(page);

      // Verify both cards preserve their maximum width and tablet gap.
      const firstCardBox = await firstCard.boundingBox();
      const secondCardBox = await secondCard.boundingBox();
      const communitiesGridBox = await communitiesGrid.boundingBox();
      expect(firstCardBox).not.toBeNull();
      expect(secondCardBox).not.toBeNull();
      expect(communitiesGridBox).not.toBeNull();
      expect(firstCardBox.width).toBeLessThanOrEqual(COMMUNITY_CARD_MAX_WIDTH);
      expect(secondCardBox.width).toBeLessThanOrEqual(COMMUNITY_CARD_MAX_WIDTH);
      expect(firstCardBox.x).toBe(communitiesGridBox.x);
      expect(secondCardBox.y).toBe(firstCardBox.y);
      expect(secondCardBox.x - (firstCardBox.x + firstCardBox.width)).toBe(32);
    });
  });

  test.describe("mobile viewport @mobile", () => {
    test.beforeEach(async ({ page }) => {
      // Load the public home page before each mobile assertion.
      await navigateToSiteHome(page);
    });

    test("stats strip shows mobile layout below lg breakpoint", async ({
      page,
    }) => {
      // Verify the mobile stats strip is visible below the large breakpoint.
      const mobileStats = getStatsContainer(page, "site", "mobile");
      await expect(mobileStats).toBeVisible();
    });

    test("community cards render on mobile with correct links", async ({
      page,
    }) => {
      // Target the mobile banner for the first community card.
      const mobileBanner = getCommunityBanner(page, TEST_COMMUNITY_TITLE);

      // Verify the mobile community card links to its public page.
      await expect(mobileBanner).toBeVisible();

      // Target the mobile community card link.
      const community1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE} banner`) })
        .first();
      await expect(community1Link).toHaveAttribute(
        "href",
        `/${TEST_COMMUNITY_NAME}`,
      );
    });

    test("community cards preserve their mobile size and gap", async ({
      page,
    }) => {
      // Target both community cards in the mobile grid, ordered by display name.
      const firstCard = getCommunityCard(page, TEST_COMMUNITY_TITLE_2);
      const secondCard = getCommunityCard(page, TEST_COMMUNITY_TITLE);
      const communitiesGrid = getCommunitiesGrid(page);

      // Verify both cards preserve their maximum width and mobile gap.
      const firstCardBox = await firstCard.boundingBox();
      const secondCardBox = await secondCard.boundingBox();
      const communitiesGridBox = await communitiesGrid.boundingBox();
      expect(firstCardBox).not.toBeNull();
      expect(secondCardBox).not.toBeNull();
      expect(communitiesGridBox).not.toBeNull();
      expect(firstCardBox.width).toBeLessThanOrEqual(COMMUNITY_CARD_MAX_WIDTH);
      expect(secondCardBox.width).toBeLessThanOrEqual(COMMUNITY_CARD_MAX_WIDTH);
      expect(firstCardBox.x).toBe(communitiesGridBox.x);
      expect(secondCardBox.x).toBe(firstCardBox.x);
      expect(secondCardBox.y - (firstCardBox.y + firstCardBox.height)).toBe(24);
    });

    test("explore all events link visible on mobile with correct href", async ({
      page,
    }) => {
      // Target the mobile explore link for in-person events.
      const mobileLink = getSectionLink(
        page,
        "upcoming in-person events",
        "Explore all events",
        "mobile",
      );

      // Verify the mobile events link points to the filtered explore page.
      await expect(mobileLink).toBeVisible();
      await expect(mobileLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=events`,
      );
    });

    test("explore all groups mobile link has correct href", async ({
      page,
    }) => {
      // Target the mobile explore link for latest groups.
      const mobileLink = getSectionLink(
        page,
        "Latest groups added",
        "Explore all groups",
        "mobile",
      );

      // Verify the mobile groups link points to the filtered explore page.
      await expect(mobileLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=groups`,
      );
    });

    test("explore all groups link visible on mobile", async ({ page }) => {
      // Target the mobile latest-groups explore link.
      const mobileExploreLink = getSectionLink(
        page,
        "Latest groups added",
        "Explore all groups",
        "mobile",
      );

      // Verify the mobile groups link is visible.
      await expect(mobileExploreLink).toBeVisible();
    });
  });
});
