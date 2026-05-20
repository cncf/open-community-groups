import { expect, test } from "@playwright/test";

import {
  E2E_PAYMENTS_ENABLED,
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
} from "../../utils.js";

test.describe("community home page", () => {
  test.describe("default viewport", () => {
    test.beforeEach(async ({ page }) => {
      // Load the community home page before each default viewport assertion.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("about section renders with heading and CTA link", async ({
      page,
    }) => {
      // Verify the about section exposes its community explore CTA.
      await expect(page.getByText("About this community")).toBeVisible();

      // Target the community explore CTA link.
      const ctaLink = page.getByRole("link", {
        name: "Explore community groups and events",
      });
      await expect(ctaLink).toBeVisible();
      await expect(ctaLink).toHaveAttribute("href", /\/explore/);
    });

    test("about section renders with seeded description", async ({ page }) => {
      // Verify the about section includes the seeded community description.
      await expect(
        page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true }),
      ).toBeVisible();
    });

    test("CTA link includes community filter parameter", async ({ page }) => {
      // Target the community explore CTA link.
      const ctaLink = page.getByRole("link", {
        name: "Explore community groups and events",
      });

      // Verify the CTA keeps the current community filter.
      await expect(ctaLink).toHaveAttribute(
        "href",
        `/explore?community[0]=${TEST_COMMUNITY_NAME}`,
      );
    });

    test("breadcrumb navigation displays community name", async ({ page }) => {
      // Verify the community breadcrumb renders in the page header.
      const breadcrumb = page.locator("breadcrumb-nav");
      await expect(breadcrumb).toBeVisible();
    });

    test("breadcrumb has correct banner and items attributes", async ({
      page,
    }) => {
      // Target the community breadcrumb data attributes.
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

      // Verify breadcrumb metadata includes the community title.
      expect(itemsAttr).toContain(TEST_COMMUNITY_TITLE);
    });

    test("stats strip displays all stat labels", async ({ page }) => {
      // Check each community stat label in the default stats strip.
      const statLabels = ["Groups", "Members", "Events", "Attendees"];
      for (const label of statLabels) {
        // Verify the current stat label is visible.
        await expect(
          page.getByText(label, { exact: true }).first(),
        ).toBeVisible();
      }
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

    test("upcoming in-person events shows published event titles", async ({
      page,
    }) => {
      // Verify the in-person events section shows published events.
      await expect(
        page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true }),
      ).toBeVisible();
      await expect(
        page.getByText(TEST_EVENT_NAMES.gamma[0], { exact: true }),
      ).toBeVisible();
    });

    test("upcoming virtual events shows seeded event titles", async ({
      page,
    }) => {
      // Verify the virtual events section shows published events.
      await expect(
        page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true }),
      ).toBeVisible();
      await expect(
        page.getByText(TEST_EVENT_NAMES.beta[1], { exact: true }),
      ).toBeVisible();
      await expect(
        page.getByText(TEST_EVENT_NAMES.gamma[1], { exact: true }),
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

      // Target the latest groups explore links.
      const exploreGroupsLinks = page.getByRole("link", {
        name: "Explore all groups",
      });
      await expect(exploreGroupsLinks.first()).toBeVisible();
    });

    test("latest groups section contains seeded groups with correct links", async ({
      page,
    }) => {
      // Locate the latest groups section before checking card links.
      const groupsSection = page
        .getByText("Latest groups added", { exact: true })
        .locator("..")
        .locator("..");

      // Define each expected group card and public slug.
      const groupData = [
        {
          name: TEST_GROUP_NAMES.alpha,
          slug: TEST_GROUP_SLUGS.community1.alpha,
        },
        { name: TEST_GROUP_NAMES.beta, slug: TEST_GROUP_SLUGS.community1.beta },
        {
          name: TEST_GROUP_NAMES.gamma,
          slug: TEST_GROUP_SLUGS.community1.gamma,
        },
      ];

      for (const { name, slug } of groupData) {
        // Target the current group card inside the latest groups section.
        const groupCard = groupsSection
          .locator(`a[href*="/${TEST_COMMUNITY_NAME}/group/${slug}"]`)
          .filter({ hasText: name });

        // Verify the current group card links to its public group page.
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
      // Load the community home page before each desktop assertion.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("stats strip displays non-empty numeric values", async ({ page }) => {
      // Target the desktop community stats strip.
      const desktopStats = getStatsContainer(page, "community", "desktop");
      const statLabels = ["Groups", "Members", "Events", "Attendees"];

      for (const label of statLabels) {
        // Target the current desktop stat value.
        const valueElement = getStatValue(desktopStats, label);

        // Verify the current desktop stat has a numeric value.
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
      const desktopStats = getStatsContainer(page, "community", "desktop");
      await expect(desktopStats).toBeVisible();
    });

    test("explore all events links have correct href on desktop", async ({
      page,
    }) => {
      // Target the desktop explore link for in-person events.
      const inPersonLink = getSectionLink(
        page,
        "upcoming in-person events",
        "Explore all events",
        "desktop",
      );

      // Verify the desktop in-person link keeps the community filter.
      await expect(inPersonLink).toHaveAttribute(
        "href",
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
      );

      // Target the desktop explore link for virtual events.
      const virtualLink = getSectionLink(
        page,
        "upcoming virtual events",
        "Explore all events",
        "desktop",
      );

      // Verify the desktop virtual link keeps the community filter.
      await expect(virtualLink).toHaveAttribute(
        "href",
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
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
      // Load the community home page before each mobile assertion.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("stats strip shows mobile layout below lg breakpoint", async ({
      page,
    }) => {
      // Verify the mobile stats strip is visible below the large breakpoint.
      const mobileStats = getStatsContainer(page, "community", "mobile");
      await expect(mobileStats).toBeVisible();
    });

    test("explore all events links have correct href on mobile", async ({
      page,
    }) => {
      // Target the mobile explore link for in-person events.
      const inPersonLink = getSectionLink(
        page,
        "upcoming in-person events",
        "Explore all events",
        "mobile",
      );

      // Verify the mobile events link keeps the community filter.
      await expect(inPersonLink).toHaveAttribute(
        "href",
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
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
