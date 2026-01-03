import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_BANNER_MOBILE_URL,
  TEST_COMMUNITY_BANNER_URL,
  TEST_COMMUNITY_DESCRIPTION,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_NAMES,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  getSectionLink,
  getStatsContainer,
  getStatValue,
  navigateToCommunityHome,
} from "../../utils";

test.describe("community home page", () => {
  test.describe("default viewport", () => {
    test.beforeEach(async ({ page }) => {
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("about section renders with heading and CTA link", async ({ page }) => {
      await expect(page.getByText("About this community")).toBeVisible();

      const ctaLink = page.getByRole("link", {
        name: "Explore community groups and events",
      });
      await expect(ctaLink).toBeVisible();
      await expect(ctaLink).toHaveAttribute("href", /\/explore/);
    });

    test("about section renders with seeded description", async ({ page }) => {
      await expect(
        page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
      ).toBeVisible();
    });

    test("CTA link includes community filter parameter", async ({ page }) => {
      const ctaLink = page.getByRole("link", {
        name: "Explore community groups and events",
      });
      await expect(ctaLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${TEST_COMMUNITY_NAME}`,
      );
    });

    test("breadcrumb navigation displays community name", async ({ page }) => {
      const breadcrumb = page.locator("breadcrumb-nav");
      await expect(breadcrumb).toBeVisible();
    });

    test("breadcrumb has correct banner and items attributes", async ({
      page,
    }) => {
      const breadcrumb = page.locator("breadcrumb-nav");
      await expect(breadcrumb).toHaveAttribute(
        "banner-url",
        TEST_COMMUNITY_BANNER_URL,
      );
      await expect(breadcrumb).toHaveAttribute(
        "banner-mobile-url",
        TEST_COMMUNITY_BANNER_MOBILE_URL,
      );

      const itemsAttr = await breadcrumb.getAttribute("items");
      expect(itemsAttr).toContain(TEST_COMMUNITY_TITLE);
    });

    test("stats strip displays all stat labels", async ({ page }) => {
      const statLabels = ["Groups", "Members", "Events", "Attendees"];
      for (const label of statLabels) {
        await expect(
          page.getByText(label, { exact: true }).first(),
        ).toBeVisible();
      }
    });

    test("upcoming in-person events section renders with title", async ({
      page,
    }) => {
      await expect(page.getByText("upcoming in-person events")).toBeVisible();
    });

    test("upcoming virtual events section renders with title", async ({ page }) => {
      await expect(page.getByText("upcoming virtual events")).toBeVisible();
    });

    test("upcoming in-person events shows published event titles", async ({
      page,
    }) => {
      await expect(page.getByText(TEST_EVENT_NAMES.alpha[0])).toBeVisible();
      await expect(page.getByText(TEST_EVENT_NAMES.gamma[0])).toBeVisible();
    });

    test("upcoming virtual events shows seeded event titles", async ({ page }) => {
      await expect(page.getByText(TEST_EVENT_NAMES.alpha[1])).toBeVisible();
      await expect(page.getByText(TEST_EVENT_NAMES.beta[1])).toBeVisible();
      await expect(page.getByText(TEST_EVENT_NAMES.gamma[1])).toBeVisible();
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

    test("latest groups section contains seeded groups with correct links", async ({
      page,
    }) => {
      const groupsSection = page
        .getByText("Latest groups added", { exact: true })
        .locator("..")
        .locator("..");

      const groupData = [
        { name: TEST_GROUP_NAMES.alpha, slug: TEST_GROUP_SLUGS.community1.alpha },
        { name: TEST_GROUP_NAMES.beta, slug: TEST_GROUP_SLUGS.community1.beta },
        { name: TEST_GROUP_NAMES.gamma, slug: TEST_GROUP_SLUGS.community1.gamma },
      ];

      for (const { name, slug } of groupData) {
        const groupCard = groupsSection
          .locator(`a[href*="/${TEST_COMMUNITY_NAME}/group/${slug}"]`)
          .filter({ hasText: name });
        await expect(groupCard).toBeVisible();
        await expect(groupCard).toHaveAttribute(
          "href",
          new RegExp(`/${TEST_COMMUNITY_NAME}/group/${slug}`),
        );
      }
    });
  });

  test.describe("desktop viewport", () => {
    test.beforeEach(async ({ page }) => {
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("stats strip displays non-empty numeric values", async ({ page }) => {
      const desktopStats = getStatsContainer(page, "community", "desktop");
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
      const desktopStats = getStatsContainer(page, "community", "desktop");
      await expect(desktopStats).toBeVisible();
    });

    test("explore all events links have correct href on desktop", async ({
      page,
    }) => {
      const inPersonLink = getSectionLink(
        page,
        "upcoming in-person events",
        "Explore all events",
        "desktop",
      );
      await expect(inPersonLink).toHaveAttribute(
        "href",
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
      );

      const virtualLink = getSectionLink(
        page,
        "upcoming virtual events",
        "Explore all events",
        "desktop",
      );
      await expect(virtualLink).toHaveAttribute(
        "href",
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
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
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("stats strip shows mobile layout below lg breakpoint", async ({
      page,
    }) => {
      const mobileStats = getStatsContainer(page, "community", "mobile");
      await expect(mobileStats).toBeVisible();
    });

    test("explore all events links have correct href on mobile", async ({
      page,
    }) => {
      const inPersonLink = getSectionLink(
        page,
        "upcoming in-person events",
        "Explore all events",
        "mobile",
      );
      await expect(inPersonLink).toHaveAttribute(
        "href",
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
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
