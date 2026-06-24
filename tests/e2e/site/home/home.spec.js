import { expect, test } from "@playwright/test";

import {
  E2E_PAYMENTS_ENABLED,
  PUBLIC_HOME_TITLE,
  TEST_ALLIANCE_NAME,
  TEST_ALLIANCE_NAME_2,
  TEST_ALLIANCE_TITLE,
  TEST_ALLIANCE_TITLE_2,
  TEST_EVENT_NAMES,
  getAllianceBanner,
  getSectionLink,
  getStatsContainer,
  getStatValue,
  navigateToSiteHome,
} from "../../utils.js";

// Site home explore links are currently hardcoded to goup in shared templates.
const SITE_HOME_EXPLORE_ALLIANCE_NAME = "goup";

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
        page.getByRole("heading", { level: 1, name: PUBLIC_HOME_TITLE }),
      ).toBeVisible();

      // Verify the jumbotron description and CTA destination.
      await expect(page.locator(".jumbotron-description")).toBeVisible();
      await expect(page.locator(".jumbotron-description")).toContainText(
        "honest introductions",
      );

      // Find the primary Explore events control.
      const ctaLink = page
        .getByRole("link", { name: "Explore events" })
        .first();
      await expect(ctaLink).toBeVisible();
      await expect(ctaLink).toHaveAttribute("href", /\/explore/);
    });

    test("hero explains concrete member benefits", async ({ page }) => {
      // Verify the hero answers what members get from joining GOUP.
      for (const benefit of [
        "Ask for help",
        "Share your work",
        "Meet in real life",
        "Grow together",
      ]) {
        await expect(
          page.getByText(benefit, { exact: true }).first(),
        ).toBeVisible();
      }
    });

    test("audience section explains who GOUP is for", async ({ page }) => {
      // Verify the audience section makes the target community explicit.
      await expect(
        page.getByRole("heading", {
          name: "For people building in public and in community",
        }),
      ).toBeVisible();

      for (const audience of [
        "AI founders",
        "Open-source maintainers",
        "Product builders",
        "Community hosts",
      ]) {
        await expect(
          page.getByText(audience, { exact: true }).first(),
        ).toBeVisible();
      }
    });

    test("home page includes the merged about story", async ({ page }) => {
      // Verify the About positioning now lives on the home page.
      await expect(
        page.getByRole("heading", {
          name: "Growth through useful progress",
        }),
      ).toBeVisible();
      await expect(page.getByText("Why GOUP", { exact: true })).toBeVisible();
      await expect(
        page.getByText("Growth", { exact: true }).first(),
      ).toBeVisible();
      await expect(
        page.getByText("Opportunity", { exact: true }).first(),
      ).toBeVisible();
      await expect(
        page.getByText("Usefulness", { exact: true }).first(),
      ).toBeVisible();
      await expect(
        page.getByText("Progress", { exact: true }).first(),
      ).toBeVisible();
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

    test("alliances section lists alliance cards with correct links", async ({
      page,
    }) => {
      // Verify alliance cards link to their public alliance pages.
      await expect(page.getByText("Alliance", { exact: true })).toBeVisible();

      // Target the first alliance card link.
      const alliance1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_ALLIANCE_TITLE} banner`) });
      await expect(alliance1Link).toHaveAttribute(
        "href",
        `/${TEST_ALLIANCE_NAME}`,
      );

      // Target the second alliance card link.
      const alliance2Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_ALLIANCE_TITLE_2} banner`) });
      await expect(alliance2Link).toHaveAttribute(
        "href",
        `/${TEST_ALLIANCE_NAME_2}`,
      );
    });

    test("upcoming in-person events section renders with title", async ({
      page,
    }) => {
      // Verify the in-person events section heading is present.
      await expect(page.getByText("upcoming in-person").first()).toBeVisible();
    });

    test("upcoming virtual events section renders with title", async ({
      page,
    }) => {
      // Verify the virtual events section heading is present.
      await expect(page.getByText("upcoming virtual").first()).toBeVisible();
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
      await expect(
        page.getByRole("heading", { name: "New chapters and circles" }),
      ).toBeVisible();

      // Target the latest groups explore link.
      const exploreGroupsLinks = page.getByRole("link", {
        name: "Explore all groups",
      });
      await expect(exploreGroupsLinks.first()).toBeVisible();
    });

    test("groups grid renders in the latest groups section", async ({
      page,
    }) => {
      // Verify the latest groups section renders group cards.
      await expect(
        page
          .getByRole("link")
          .filter({ hasText: "Platform Ops Meetup" })
          .first(),
      ).toBeVisible();
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

    test("alliance cards render on desktop with correct links", async ({
      page,
    }) => {
      // Target the first desktop alliance card.
      const alliance1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_ALLIANCE_TITLE} banner`) })
        .first();

      // Verify desktop alliance cards link to public alliance pages.
      await expect(alliance1Link).toHaveAttribute(
        "href",
        `/${TEST_ALLIANCE_NAME}`,
      );

      // Set up alliance2 link.
      const alliance2Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_ALLIANCE_TITLE_2} banner`) })
        .first();
      await expect(alliance2Link).toHaveAttribute(
        "href",
        `/${TEST_ALLIANCE_NAME_2}`,
      );
    });

    test("alliance banners use display name in alt text", async ({ page }) => {
      // Verify desktop alliance banners use display names in alt text.
      await expect(
        getAllianceBanner(page, TEST_ALLIANCE_TITLE, "desktop"),
      ).toBeVisible();

      // Verify the second alliance banner also uses its display name.
      await expect(
        getAllianceBanner(page, TEST_ALLIANCE_TITLE_2, "desktop"),
      ).toBeVisible();
    });

    test("desktop banner renders on large viewports", async ({ page }) => {
      // Target desktop and mobile banner variants for one alliance.
      const desktopBanner = getAllianceBanner(
        page,
        TEST_ALLIANCE_TITLE,
        "desktop",
      );

      // Verify only the desktop banner variant is visible.
      await expect(desktopBanner).toBeVisible();

      // Target the matching mobile banner variant.
      const mobileBanner = getAllianceBanner(
        page,
        TEST_ALLIANCE_TITLE,
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
        "upcoming in-person",
        "Explore all events",
        "desktop",
      );

      // Verify the desktop events link points to the filtered explore page.
      await expect(desktopLink).toBeVisible();
      await expect(desktopLink).toHaveAttribute(
        "href",
        `/explore?alliance[0]=${SITE_HOME_EXPLORE_ALLIANCE_NAME}&entity=events`,
      );
    });

    test("explore all groups desktop link has correct href", async ({
      page,
    }) => {
      // Target the desktop explore link for latest groups.
      const desktopLink = page
        .getByRole("link", { name: "Explore all groups" })
        .first();

      // Verify the desktop groups link points to the filtered explore page.
      await expect(desktopLink).toHaveAttribute(
        "href",
        `/explore?alliance[0]=${SITE_HOME_EXPLORE_ALLIANCE_NAME}&entity=groups`,
      );
    });

    test("explore all groups link visible on desktop", async ({ page }) => {
      // Target the desktop latest-groups explore link.
      const desktopExploreLink = page
        .getByRole("link", { name: "Explore all groups" })
        .first();

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

    test("alliance cards render on mobile with correct links", async ({
      page,
    }) => {
      // Target the mobile banner for the first alliance card.
      const mobileBanner = getAllianceBanner(
        page,
        TEST_ALLIANCE_TITLE,
        "mobile",
      );

      // Verify the mobile alliance card links to its public page.
      await expect(mobileBanner).toBeVisible();

      // Target the mobile alliance card link.
      const alliance1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_ALLIANCE_TITLE} banner`) })
        .first();
      await expect(alliance1Link).toHaveAttribute(
        "href",
        `/${TEST_ALLIANCE_NAME}`,
      );
    });

    test("mobile banner renders on small viewports", async ({ page }) => {
      // Target mobile and desktop banner variants for one alliance.
      const mobileBanner = getAllianceBanner(
        page,
        TEST_ALLIANCE_TITLE,
        "mobile",
      );

      // Verify only the mobile banner variant is visible.
      await expect(mobileBanner).toBeVisible();

      // Target the matching desktop banner variant.
      const desktopBanner = getAllianceBanner(
        page,
        TEST_ALLIANCE_TITLE,
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
        "upcoming in-person",
        "Explore all events",
        "mobile",
      );

      // Verify the mobile events link points to the filtered explore page.
      await expect(mobileLink).toBeVisible();
      await expect(mobileLink).toHaveAttribute(
        "href",
        `/explore?alliance[0]=${SITE_HOME_EXPLORE_ALLIANCE_NAME}&entity=events`,
      );
    });

    test("explore all groups mobile link has correct href", async ({
      page,
    }) => {
      // Target the mobile explore link for latest groups.
      const mobileLink = page
        .getByRole("link", { name: "Explore all groups" })
        .last();

      // Verify the mobile groups link points to the filtered explore page.
      await expect(mobileLink).toHaveAttribute(
        "href",
        `/explore?alliance[0]=${SITE_HOME_EXPLORE_ALLIANCE_NAME}&entity=groups`,
      );
    });

    test("explore all groups link visible on mobile", async ({ page }) => {
      // Target the mobile latest-groups explore link.
      const mobileExploreLink = page
        .getByRole("link", { name: "Explore all groups" })
        .last();

      // Verify the mobile groups link is visible.
      await expect(mobileExploreLink).toBeVisible();
    });
  });
});
