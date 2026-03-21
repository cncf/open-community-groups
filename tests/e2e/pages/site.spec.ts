import { expect, test } from "@playwright/test";

import {
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
} from "../utils";

// Site home explore links are currently hardcoded to cncf in shared templates.
const SITE_HOME_EXPLORE_COMMUNITY_NAME = "cncf";

test.describe("site home page", () => {
  test.describe("default viewport", () => {
    test.beforeEach(async ({ page }) => {
      await navigateToSiteHome(page);
    });

    test("jumbotron renders with title, description, and CTA link", async ({
      page,
    }) => {
      await expect(
        page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
      ).toBeVisible();
      await expect(page.locator(".jumbotron-description")).toBeVisible();

      const ctaLink = page.getByRole("link", {
        name: "Explore groups and events",
      });
      await expect(ctaLink).toBeVisible();
      await expect(ctaLink).toHaveAttribute("href", /\/explore/);
    });

    test("stats strip displays all stat labels with values", async ({
      page,
    }) => {
      const statLabels = ["Groups", "Members", "Events", "Attendees"];
      for (const label of statLabels) {
        await expect(
          page.getByText(label, { exact: true }).first(),
        ).toBeVisible();
      }
    });

    test("communities section lists community cards with correct links", async ({
      page,
    }) => {
      await expect(page.getByText("Communities")).toBeVisible();

      const community1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE} banner`) });
      await expect(community1Link).toHaveAttribute(
        "href",
        `/${TEST_COMMUNITY_NAME}`,
      );

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
      await expect(page.getByText("upcoming in-person events")).toBeVisible();
    });

    test("upcoming virtual events section renders with title", async ({
      page,
    }) => {
      await expect(page.getByText("upcoming virtual events")).toBeVisible();
    });

    test("upcoming in-person events shows seeded event cards", async ({
      page,
    }) => {
      await expect(page.getByText(TEST_EVENT_NAMES.alpha[0])).toBeVisible();
    });

    test("upcoming virtual events shows seeded event cards", async ({ page }) => {
      await expect(page.getByText(TEST_EVENT_NAMES.alpha[1])).toBeVisible();
    });

    test("latest groups section renders heading and explore link", async ({
      page,
    }) => {
      await expect(page.getByText("Latest groups added")).toBeVisible();

      const exploreGroupsLinks = page.getByRole("link", {
        name: "Explore all groups",
      });
      await expect(exploreGroupsLinks.first()).toBeVisible();
    });

    test("groups grid renders in the latest groups section", async ({
      page,
    }) => {
      const groupsGrid = page
        .getByText("Latest groups added", { exact: true })
        .locator("..")
        .locator("..")
        .locator("div.grid");
      await expect(groupsGrid.first()).toBeVisible();
    });
  });

  test.describe("desktop viewport", () => {
    test.beforeEach(async ({ page }) => {
      await navigateToSiteHome(page);
    });

    test("stats strip displays non-empty numeric values", async ({ page }) => {
      const desktopStats = getStatsContainer(page, "site", "desktop");
      const statLabels = ["Groups", "Members", "Events", "Attendees"];

      for (const label of statLabels) {
        const valueElement = getStatValue(desktopStats, label);
        await expect(desktopStats.getByText(label, { exact: true })).toBeVisible();
        await expect(valueElement).toBeVisible();
        const text = await valueElement.textContent();
        expect(text?.trim()).toMatch(/^\d[\d,]*$/);
      }
    });

    test("stats strip shows desktop layout at lg breakpoint", async ({
      page,
    }) => {
      const desktopStats = getStatsContainer(page, "site", "desktop");
      await expect(desktopStats).toBeVisible();
    });

    test("community cards render on desktop with correct links", async ({
      page,
    }) => {
      const community1Link = page
        .getByRole("link")
        .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE} banner`) })
        .first();
      await expect(community1Link).toHaveAttribute(
        "href",
        `/${TEST_COMMUNITY_NAME}`,
      );

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
      await expect(
        getCommunityBanner(page, TEST_COMMUNITY_TITLE, "desktop"),
      ).toBeVisible();
      await expect(
        getCommunityBanner(page, TEST_COMMUNITY_TITLE_2, "desktop"),
      ).toBeVisible();
    });

    test("desktop banner renders on large viewports", async ({ page }) => {
      const desktopBanner = getCommunityBanner(page, TEST_COMMUNITY_TITLE, "desktop");
      await expect(desktopBanner).toBeVisible();

      const mobileBanner = getCommunityBanner(page, TEST_COMMUNITY_TITLE, "mobile");
      await expect(mobileBanner).toBeHidden();
    });

    test("explore all events link visible on desktop with correct href", async ({
      page,
    }) => {
      const desktopLink = getSectionLink(
        page,
        "upcoming in-person events",
        "Explore all events",
        "desktop",
      );
      await expect(desktopLink).toBeVisible();
      await expect(desktopLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=events`,
      );
    });

    test("explore all groups desktop link has correct href", async ({ page }) => {
      const desktopLink = getSectionLink(
        page,
        "Latest groups added",
        "Explore all groups",
        "desktop",
      );
      await expect(desktopLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=groups`,
      );
    });

    test("explore all groups link visible on desktop", async ({ page }) => {
      const desktopExploreLink = getSectionLink(
        page,
        "Latest groups added",
        "Explore all groups",
        "desktop",
      );
      await expect(desktopExploreLink).toBeVisible();
    });
  });

  test.describe("mobile viewport @mobile", () => {
    test.beforeEach(async ({ page }) => {
      await navigateToSiteHome(page);
    });

    test("stats strip shows mobile layout below lg breakpoint", async ({
      page,
    }) => {
      const mobileStats = getStatsContainer(page, "site", "mobile");
      await expect(mobileStats).toBeVisible();
    });

    test("community cards render on mobile with correct links", async ({
      page,
    }) => {
      const mobileBanner = getCommunityBanner(page, TEST_COMMUNITY_TITLE, "mobile");
      await expect(mobileBanner).toBeVisible();

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
      const mobileBanner = getCommunityBanner(page, TEST_COMMUNITY_TITLE, "mobile");
      await expect(mobileBanner).toBeVisible();

      const desktopBanner = getCommunityBanner(page, TEST_COMMUNITY_TITLE, "desktop");
      await expect(desktopBanner).toBeHidden();
    });

    test("explore all events link visible on mobile with correct href", async ({
      page,
    }) => {
      const mobileLink = getSectionLink(
        page,
        "upcoming in-person events",
        "Explore all events",
        "mobile",
      );
      await expect(mobileLink).toBeVisible();
      await expect(mobileLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=events`,
      );
    });

    test("explore all groups mobile link has correct href", async ({ page }) => {
      const mobileLink = getSectionLink(
        page,
        "Latest groups added",
        "Explore all groups",
        "mobile",
      );
      await expect(mobileLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${SITE_HOME_EXPLORE_COMMUNITY_NAME}&entity=groups`,
      );
    });

    test("explore all groups link visible on mobile", async ({ page }) => {
      const mobileExploreLink = getSectionLink(
        page,
        "Latest groups added",
        "Explore all groups",
        "mobile",
      );
      await expect(mobileExploreLink).toBeVisible();
    });
  });
});
