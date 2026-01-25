/**
 * E2E tests for the community home template.
 */

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
  navigateToCommunityHome,
} from "../utils";

test.describe("community home page", () => {
  test.describe("default viewport", () => {
    test.beforeEach(async ({ page }) => {
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    // About section tests
    test("about section renders with heading and CTA link", async ({ page }) => {
      await expect(page.getByText("About this community")).toBeVisible();

      const ctaLink = page.getByRole("link", {
        name: "Explore community groups and events",
      });
      await expect(ctaLink).toBeVisible();
      await expect(ctaLink).toHaveAttribute("href", /\/explore/);
    });

    test("about section renders with seeded description", async ({ page }) => {
      const descriptionDiv = page.locator(".jumbotron-description");
      await expect(descriptionDiv).toBeVisible();
      await expect(descriptionDiv).toContainText(TEST_COMMUNITY_DESCRIPTION);
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

    // Breadcrumb tests
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

    // Stats strip tests
    test("stats strip displays all stat labels", async ({ page }) => {
      const statLabels = ["Groups", "Members", "Events", "Attendees"];
      for (const label of statLabels) {
        await expect(
          page.getByText(label, { exact: true }).first(),
        ).toBeVisible();
      }
    });

    // Upcoming events section tests
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

    // Latest groups section tests
    test("latest groups section renders heading and explore link", async ({
      page,
    }) => {
      await expect(page.getByText("Latest groups added")).toBeVisible();

      const exploreGroupsLinks = page.getByRole("link", {
        name: "Explore all groups",
      });
      await expect(exploreGroupsLinks.first()).toBeVisible();
    });

    // Verifies all seeded groups appear with correct links to their detail pages
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
        const groupCard = groupsSection.getByRole("link", { name });
        await expect(groupCard).toBeVisible();
        await expect(groupCard).toHaveAttribute(
          "href",
          `/${TEST_COMMUNITY_NAME}/group/${slug}`,
        );
      }
    });
  });

  test.describe("desktop viewport", () => {
    test.beforeEach(async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    // Verifies each stat displays a valid numeric value (digits with optional commas)
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

    test("explore all events links have correct href on desktop", async ({
      page,
    }) => {
      const inPersonSection = page
        .getByText("upcoming in-person events", { exact: true })
        .locator("..")
        .locator("..");
      const inPersonLink = inPersonSection
        .locator("div.hidden.md\\:flex")
        .getByRole("link", { name: "Explore all events" });
      await expect(inPersonLink).toHaveAttribute(
        "href",
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
      );

      const virtualSection = page
        .getByText("upcoming virtual events", { exact: true })
        .locator("..")
        .locator("..");
      const virtualLink = virtualSection
        .locator("div.hidden.md\\:flex")
        .getByRole("link", { name: "Explore all events" });
      await expect(virtualLink).toHaveAttribute(
        "href",
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
      );
    });

    // Verifies desktop explore groups link is visible at md breakpoint
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
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("stats strip shows mobile layout below lg breakpoint", async ({
      page,
    }) => {
      const mobileStats = page.locator("div.grid.lg\\:hidden").first();
      await expect(mobileStats).toBeVisible();
    });

    // Verifies mobile explore link has correct href scoped to in-person section
    test("explore all events links have correct href on mobile", async ({
      page,
    }) => {
      const inPersonSection = page
        .getByText("upcoming in-person events", { exact: true })
        .locator("..")
        .locator("..");
      const inPersonLink = inPersonSection
        .locator("div.md\\:hidden")
        .getByRole("link", { name: "Explore all events" });
      await expect(inPersonLink).toHaveAttribute(
        "href",
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
      );
    });

    // Verifies mobile explore groups link is visible below md breakpoint
    test("explore all groups link visible on mobile", async ({ page }) => {
      const mobileExploreLink = page
        .locator("div.md\\:hidden")
        .getByRole("link", { name: "Explore all groups" });
      await expect(mobileExploreLink).toBeVisible();
    });
  });
});
