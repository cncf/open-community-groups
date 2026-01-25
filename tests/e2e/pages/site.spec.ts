/**
 * E2E tests for the site home template.
 */

import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_COMMUNITY_TITLE,
  TEST_COMMUNITY_TITLE_2,
  TEST_EVENT_NAMES,
  TEST_SITE_TITLE,
  navigateToSiteHome,
} from "../utils";

test.describe("site home page", () => {
  test.describe("default viewport", () => {
    test.beforeEach(async ({ page }) => {
      await navigateToSiteHome(page);
    });

    /** Jumbotron section. */
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

    /** Stats strip. */
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

    /** Community cards. */
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

    /** Upcoming events. */
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

    /** Latest groups. */
    test("latest groups section renders heading and explore link", async ({
      page,
    }) => {
      await expect(page.getByText("Latest groups added")).toBeVisible();

      const exploreGroupsLinks = page.getByRole("link", {
        name: "Explore all groups",
      });
      await expect(exploreGroupsLinks.first()).toBeVisible();
    });

    /** Groups grid layout. */
    test("groups grid has correct responsive hiding classes", async ({
      page,
    }) => {
      const groupsGrid = page.locator(
        "div.grid.grid-cols-1.gap-6.md\\:gap-8.md\\:grid-cols-2",
      );
      await expect(groupsGrid.first()).toBeVisible();
    });
  });

  test.describe("desktop viewport", () => {
    test.beforeEach(async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      await navigateToSiteHome(page);
    });

    test("stats strip displays non-empty numeric values", async ({ page }) => {
      const desktopStats = page
        .locator("div.hidden.lg\\:flex")
        .filter({ has: page.getByText("Groups", { exact: true }) })
        .first();
      const statLabels = ["Groups", "Members", "Events", "Attendees"];

      for (const label of statLabels) {
        const labelElement = desktopStats.getByText(label, { exact: true });
        const statBlock = labelElement.locator("..");
        const valueElement = statBlock.locator(".lg\\:text-4xl");
        await expect(valueElement).toBeVisible();
        const text = await valueElement.textContent();
        expect(text?.trim()).toMatch(/^\d[\d,]*$/);
      }
    });

    test("stats strip shows desktop layout at lg breakpoint", async ({
      page,
    }) => {
      const desktopStats = page
        .locator("div.hidden.lg\\:flex")
        .filter({ has: page.getByText("Groups", { exact: true }) })
        .first();
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
      const desktopBannerContainer = page.locator("div.hidden.sm\\:block");
      await expect(
        desktopBannerContainer
          .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE} banner`) })
          .first(),
      ).toBeVisible();
      await expect(
        desktopBannerContainer
          .filter({ has: page.getByAltText(`${TEST_COMMUNITY_TITLE_2} banner`) })
          .first(),
      ).toBeVisible();
    });

    test("desktop banner renders on large viewports", async ({ page }) => {
      const desktopBanner = page.locator("div.hidden.sm\\:block").first();
      await expect(desktopBanner).toBeVisible();

      const mobileBanner = page
        .locator("div.aspect-\\[61\\/12\\].sm\\:hidden")
        .first();
      await expect(mobileBanner).toBeHidden();
    });

    test("explore all events link visible on desktop with correct href", async ({
      page,
    }) => {
      const inPersonSection = page
        .getByText("upcoming in-person events", { exact: true })
        .locator("..")
        .locator("..");
      const desktopLink = inPersonSection
        .locator("div.hidden.md\\:flex")
        .getByRole("link", { name: "Explore all events" });
      await expect(desktopLink).toBeVisible();
      await expect(desktopLink).toHaveAttribute(
        "href",
        "/explore?community[0]=cncf&entity=events",
      );
    });

    test("explore all groups desktop link has correct href", async ({ page }) => {
      const groupsSection = page
        .getByText("Latest groups added", { exact: true })
        .locator("..")
        .locator("..");
      const desktopLink = groupsSection
        .locator("div.hidden.md\\:flex")
        .getByRole("link", { name: "Explore all groups" });
      await expect(desktopLink).toHaveAttribute(
        "href",
        "/explore?community[0]=cncf&entity=groups",
      );
    });

    test("explore all groups link visible on desktop", async ({ page }) => {
      const desktopExploreLink = page
        .locator("div.hidden.md\\:flex")
        .getByRole("link", { name: "Explore all groups" });
      await expect(desktopExploreLink).toBeVisible();
    });
  });

  test.describe("mobile viewport", () => {
    test.beforeEach(async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await navigateToSiteHome(page);
    });

    test("stats strip shows mobile layout below lg breakpoint", async ({
      page,
    }) => {
      const mobileStats = page.locator("div.grid.lg\\:hidden").first();
      await expect(mobileStats).toBeVisible();
    });

    test("community cards render on mobile with correct links", async ({
      page,
    }) => {
      const mobileBanner = page.locator("div.sm\\:hidden").first();
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
      const mobileBanner = page
        .locator("div.aspect-\\[61\\/12\\].sm\\:hidden")
        .first();
      await expect(mobileBanner).toBeVisible();

      const desktopBanner = page.locator("div.hidden.sm\\:block").first();
      await expect(desktopBanner).toBeHidden();
    });

    test("explore all events link visible on mobile with correct href", async ({
      page,
    }) => {
      const inPersonSection = page
        .getByText("upcoming in-person events", { exact: true })
        .locator("..")
        .locator("..");
      const mobileLink = inPersonSection
        .locator("div.md\\:hidden")
        .getByRole("link", { name: "Explore all events" });
      await expect(mobileLink).toBeVisible();
      await expect(mobileLink).toHaveAttribute(
        "href",
        "/explore?community[0]=cncf&entity=events",
      );
    });

    test("explore all groups mobile link has correct href", async ({ page }) => {
      const groupsSection = page
        .getByText("Latest groups added", { exact: true })
        .locator("..")
        .locator("..");
      const mobileLink = groupsSection
        .locator("div.md\\:hidden")
        .getByRole("link", { name: "Explore all groups" });
      await expect(mobileLink).toHaveAttribute(
        "href",
        "/explore?community[0]=cncf&entity=groups",
      );
    });

    test("explore all groups link visible on mobile", async ({ page }) => {
      const mobileExploreLink = page
        .locator("div.md\\:hidden")
        .getByRole("link", { name: "Explore all groups" });
      await expect(mobileExploreLink).toBeVisible();
    });
  });
});
