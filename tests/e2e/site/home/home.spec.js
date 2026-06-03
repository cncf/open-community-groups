import { expect, test } from "@playwright/test";

import {
  E2E_PAYMENTS_ENABLED,
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

// Site home explore links are currently hardcoded to cncf in shared templates.
const SITE_HOME_EXPLORE_COMMUNITY_NAME = "cncf";

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

    test("ticketed seeded event cards show price badges", async ({ page }) => {
      // Skip price badge assertions when payments are disabled.
      test.skip(
        !E2E_PAYMENTS_ENABLED,
        "Payments are disabled in this environment.",
      );

      // Target ticketed in-person and virtual event cards.
      const inPersonCard = page
        .getByRole("link")
        .filter({ hasText: TEST_EVENT_NAMES.gamma[0] })
        .first();
      const virtualCard = page
        .getByRole("link")
        .filter({ hasText: TEST_EVENT_NAMES.beta[1] })
        .first();

      // Verify ticketed event cards show their starting prices.
      await expect(inPersonCard).toContainText("From USD 20.00");
      await expect(virtualCard).toContainText("From USD 15.00");
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
      // Verify desktop community banners use display names in alt text.
      await expect(
        getCommunityBanner(page, TEST_COMMUNITY_TITLE, "desktop"),
      ).toBeVisible();

      // Verify the second community banner also uses its display name.
      await expect(
        getCommunityBanner(page, TEST_COMMUNITY_TITLE_2, "desktop"),
      ).toBeVisible();
    });

    test("desktop banner renders on large viewports", async ({ page }) => {
      // Target desktop and mobile banner variants for one community.
      const desktopBanner = getCommunityBanner(
        page,
        TEST_COMMUNITY_TITLE,
        "desktop",
      );

      // Verify only the desktop banner variant is visible.
      await expect(desktopBanner).toBeVisible();

      // Target the matching mobile banner variant.
      const mobileBanner = getCommunityBanner(
        page,
        TEST_COMMUNITY_TITLE,
        "mobile",
      );
      await expect(mobileBanner).toBeHidden();
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
      const mobileBanner = getCommunityBanner(
        page,
        TEST_COMMUNITY_TITLE,
        "mobile",
      );

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

    test("mobile banner renders on small viewports", async ({ page }) => {
      // Target mobile and desktop banner variants for one community.
      const mobileBanner = getCommunityBanner(
        page,
        TEST_COMMUNITY_TITLE,
        "mobile",
      );

      // Verify only the mobile banner variant is visible.
      await expect(mobileBanner).toBeVisible();

      // Target the matching desktop banner variant.
      const desktopBanner = getCommunityBanner(
        page,
        TEST_COMMUNITY_TITLE,
        "desktop",
      );
      await expect(desktopBanner).toBeHidden();
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
