import { expect, test, testAtBothWidths } from "../../fixtures.js";

import { expectNoAxeViolations } from "../../axe.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUG,
  TEST_GROUP_SLUGS,
} from "../../seed.js";
import { expectDarkTheme, navigateToEvent, navigateToGroup, useTheme } from "../../utils.js";
import { openContents } from "../docs/helpers.js";
import { openAccountMenuOnStats, openExploreFilters, openOrganizerProfileOnGroup } from "./helpers.js";
import { loadPublicPage, PUBLIC_PAGES } from "./public-pages.js";

// Group page that shows the community-2 floating advertisement banner.
const AD_BANNER_GROUP_PAGE = {
  name: "group advertisement",
  path: `/${TEST_COMMUNITY_NAME_2}/group/${TEST_GROUP_SLUGS.community2.delta}`,
  ready: (page) => page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.delta }),
};

// Docs overview, whose Contents sheet the phone overlay scan opens.
const DOCS_PAGE = PUBLIC_PAGES.find(({ name }) => name === "documentation");

// Public site guide, deep linked: it renders tables, inline code and a `?>` callout.
const DOCS_GUIDE_PAGE = {
  ...DOCS_PAGE,
  name: "docs guide",
  path: "/docs#/guides/public-site",
  ready: (page) =>
    page.locator(".ocg-docs-root").getByRole("heading", { level: 1, name: "Public Site Guide" }),
};

const MOBILE_SCAN_KEYS = {
  "badge verification": "badge verify mobile",
  documentation: "docs mobile",
};
const MOBILE_SCAN_PAGE_NAMES = new Set([
  "badge credential",
  "badge verification",
  "community",
  "documentation",
  "event",
  "explore events",
  "explore groups",
  "group",
  "home",
  "statistics",
]);

test.describe("public pages axe scan", () => {
  for (const publicPage of PUBLIC_PAGES) {
    test(`${publicPage.name} has no critical or serious axe violations`, async ({ page }) => {
      // Load a seeded public page and let it settle before scanning.
      await loadPublicPage(page, publicPage);

      // Verify the rendered page against the critical/serious baseline.
      await expectNoAxeViolations(page, { scan: publicPage.name });
    });
  }
});

test.describe("public pages mobile axe scan @mobile", () => {
  for (const publicPage of PUBLIC_PAGES.filter(({ name }) => MOBILE_SCAN_PAGE_NAMES.has(name))) {
    test(`${publicPage.name} has no critical or serious axe violations on phones`, async ({ page }) => {
      // Load a seeded public page and let it settle before scanning.
      await loadPublicPage(page, publicPage);

      // Verify the phone layout under a scan key of its own.
      await expectNoAxeViolations(page, {
        scan: MOBILE_SCAN_KEYS[publicPage.name] ?? `${publicPage.name} mobile`,
      });
    });
  }
});

test.describe("account menu axe scan", () => {
  testAtBothWidths(
    "guest account menu has no critical or serious axe violations",
    async ({ isMobile, page }) => {
      // Open the guest menu, the account sheet on phones.
      await openAccountMenuOnStats(page);

      // Verify the whole page with the menu open, including its Theme group.
      await expectNoAxeViolations(page, {
        scan: isMobile ? "account menu guest mobile" : "account menu guest",
      });
    },
  );

  testAtBothWidths(
    "member account menu has no critical or serious axe violations",
    async ({ isMobile, member1Page }) => {
      // Open the member menu, the account sheet on phones.
      await openAccountMenuOnStats(member1Page);

      // Verify the whole page with the menu open, including its Theme group.
      await expectNoAxeViolations(member1Page, {
        scan: isMobile ? "account menu member mobile" : "account menu member",
      });
    },
  );
});

test.describe("public pages dark axe scan", () => {
  for (const publicPage of PUBLIC_PAGES) {
    test(`${publicPage.name} has no critical or serious color violations in dark`, async ({ page }) => {
      // Load a seeded public page in the dark theme.
      await useTheme(page, { stored: "dark" });
      await loadPublicPage(page, publicPage);
      await expectDarkTheme(page);

      // Verify the dark colors under the light key plus " dark".
      await expectNoAxeViolations(page, { colorOnly: true, scan: `${publicPage.name} dark` });
    });
  }

  test("docs guide has no critical or serious color violations in dark", async ({ page }) => {
    // Load the deep-linked public site guide in the dark theme.
    await useTheme(page, { stored: "dark" });
    await loadPublicPage(page, DOCS_GUIDE_PAGE);
    await expectDarkTheme(page);

    // Verify its tables, inline code and callout.
    await expectNoAxeViolations(page, { colorOnly: true, scan: "docs guide dark" });
  });
});

test.describe("public pages mobile dark axe scan @mobile", () => {
  for (const publicPage of PUBLIC_PAGES.filter(({ name }) => MOBILE_SCAN_PAGE_NAMES.has(name))) {
    test(`${publicPage.name} has no critical or serious color violations on phones in dark`, async ({
      page,
    }) => {
      // Load a seeded public page in the dark theme.
      await useTheme(page, { stored: "dark" });
      await loadPublicPage(page, publicPage);
      await expectDarkTheme(page);

      // Verify the dark phone layout under its mobile key plus " dark".
      await expectNoAxeViolations(page, {
        colorOnly: true,
        scan: `${MOBILE_SCAN_KEYS[publicPage.name] ?? `${publicPage.name} mobile`} dark`,
      });
    });
  }
});

test.describe("overlay dark axe scan", () => {
  test("guest account menu has no critical or serious color violations in dark", async ({ page }) => {
    // Open the guest menu in the dark theme.
    await useTheme(page, { stored: "dark" });
    await openAccountMenuOnStats(page);
    await expectDarkTheme(page);

    // Verify the open menu, including its Theme group.
    await expectNoAxeViolations(page, {
      colorOnly: true,
      include: ["#user-dropdown"],
      scan: "account menu dark",
    });
  });

  test("member account menu has no critical or serious color violations in dark", async ({ member1Page }) => {
    // Open the member menu in the dark theme.
    await useTheme(member1Page, { stored: "dark" });
    await openAccountMenuOnStats(member1Page);
    await expectDarkTheme(member1Page);

    // Verify the open menu, including its dashboard links and Theme group.
    await expectNoAxeViolations(member1Page, {
      colorOnly: true,
      include: ["#user-dropdown"],
      scan: "account menu member dark",
    });
  });

  test("member account sheet has no critical or serious color violations in dark @mobile", async ({
    member1Page,
  }) => {
    // Open the member account sheet in the dark theme.
    await useTheme(member1Page, { stored: "dark" });
    await openAccountMenuOnStats(member1Page);
    await expectDarkTheme(member1Page);

    // Verify the open sheet, including its Theme group.
    await expectNoAxeViolations(member1Page, {
      colorOnly: true,
      include: ["#user-dropdown"],
      scan: "account sheet mobile dark",
    });
  });

  test("guest account sheet has no critical or serious color violations in dark @mobile", async ({
    page,
  }) => {
    // Open the guest account sheet in the dark theme.
    await useTheme(page, { stored: "dark" });
    await openAccountMenuOnStats(page);
    await expectDarkTheme(page);

    // Verify the open sheet, including its Theme group and Sign up and Log in pills.
    await expectNoAxeViolations(page, {
      colorOnly: true,
      include: ["#user-dropdown"],
      scan: "account sheet guest mobile dark",
    });
  });

  test("explore filter sheet has no critical or serious color violations in dark @mobile", async ({
    page,
  }) => {
    // Open the explore filter sheet in the dark theme.
    await useTheme(page, { stored: "dark" });
    await openExploreFilters(page);
    await expectDarkTheme(page);

    // Verify the open sheet.
    await expectNoAxeViolations(page, {
      colorOnly: true,
      include: ["#drawer-filters"],
      scan: "explore filters mobile dark",
    });
  });

  test("docs Contents sheet has no critical or serious color violations in dark @mobile", async ({
    page,
  }) => {
    // Open the docs Contents sheet in the dark theme.
    await useTheme(page, { stored: "dark" });
    await loadPublicPage(page, DOCS_PAGE);
    await openContents(page);
    await expectDarkTheme(page);

    // Verify the open sheet and its head.
    await expectNoAxeViolations(page, {
      colorOnly: true,
      include: [".ocg-docs-root .sidebar"],
      scan: "docs mobile contents open dark",
    });
  });

  test("organizer profile dialog has no critical or serious color violations in dark", async ({ page }) => {
    // Open the organizer profile from the group page in the dark theme.
    await useTheme(page, { stored: "dark" });
    await openOrganizerProfileOnGroup(page);
    await expectDarkTheme(page);

    // Verify the open dialog.
    await expectNoAxeViolations(page, {
      colorOnly: true,
      include: ['user-info-modal [role="dialog"]'],
      scan: "user profile dark",
    });
  });
});

test.describe("widget dark axe scan", () => {
  testAtBothWidths(
    "event gallery lightbox has no critical or serious color violations in dark",
    async ({ isMobile, page }) => {
      // Open the event gallery's lightbox from its first tile in the dark theme.
      await useTheme(page, { stored: "dark" });
      await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
      await expectDarkTheme(page);
      await page
        .locator("images-gallery")
        .getByRole("button", { name: `Open Event ${TEST_EVENT_NAME} image 1` })
        .click();
      // Only phones make the lightbox a dialog; opacity-0 is its closed state at every width.
      await expect(page.locator("images-gallery .modal")).not.toHaveClass(/opacity-0/);

      // Verify the open lightbox, whose viewer keeps its light colors.
      await expectNoAxeViolations(page, {
        colorOnly: true,
        include: ["images-gallery .modal"],
        scan: isMobile ? "event gallery mobile dark" : "event gallery dark",
      });
    },
  );

  testAtBothWidths(
    "group sign-in prompt has no critical or serious color violations in dark",
    async ({ isMobile, page }) => {
      // Open the sign-in prompt from the group's join action in the dark theme.
      await useTheme(page, { stored: "dark" });
      await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
      await expectDarkTheme(page);
      await page.locator("#membership-container #signin-btn").click();
      await expect(page.locator(".swal2-popup")).toBeVisible();

      // Keep the timed desktop prompt open while it is scanned; the phone prompt has no timer.
      await page.evaluate(() => globalThis.Swal.stopTimer());

      // Verify the open prompt.
      await expectNoAxeViolations(page, {
        colorOnly: true,
        include: [".swal2-popup"],
        scan: isMobile ? "group sign-in prompt mobile dark" : "group sign-in prompt dark",
      });
    },
  );
});

test.describe("group advertisement dark axe scan", () => {
  test("group page with the floating advertisement has no critical or serious color violations in dark", async ({
    page,
  }) => {
    // Show the banner again by dropping any stored dismissal before page scripts run.
    await page.addInitScript(() => {
      try {
        Object.keys(localStorage)
          .filter((key) => key.startsWith("ocg:ad-banner:hidden"))
          .forEach((key) => localStorage.removeItem(key));
      } catch {
        // Opaque origins such as `about:blank` have no storage to clear.
      }
    });

    // Load the advertised group in the dark theme and wait for the banner to slide in.
    await useTheme(page, { stored: "dark" });
    await loadPublicPage(page, AD_BANNER_GROUP_PAGE);
    await expectDarkTheme(page);
    const advertisementBanner = page.locator('[data-ad-banner="floating"]');
    await expect(advertisementBanner).toBeVisible();
    await expect(advertisementBanner).toHaveClass(/(^|\s)translate-y-0(\s|$)/);

    // Verify the whole page with the banner shown.
    await expectNoAxeViolations(page, { colorOnly: true, scan: "group advertisement dark" });
  });
});
