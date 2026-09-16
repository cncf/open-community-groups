import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_SITE_TITLE,
} from "../../seed.js";
import { navigateToPath } from "../../utils.js";

const BREAKPOINTS = [
  { name: "mobile", width: 390 },
  { name: "sm", width: 640 },
  { name: "md", width: 768 },
  { name: "lg", width: 1024 },
  { name: "xl", width: 1280 },
  { name: "2xl", width: 1536 },
];

const RESPONSIVE_PAGES = [
  {
    name: "home",
    path: "/",
    ready: (page) => page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
  },
  {
    name: "community",
    path: `/${TEST_COMMUNITY_NAME}`,
    ready: (page) => page.getByText("About this community", { exact: true }),
  },
  {
    name: "group",
    path: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`,
    ready: (page) => page.getByRole("heading", { level: 1, name: TEST_GROUP_NAME }),
  },
  {
    name: "event",
    path: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`,
    ready: (page) => page.getByRole("heading", { level: 1, name: TEST_EVENT_NAME }),
  },
  {
    name: "explore events",
    path: `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    ready: (page) => page.getByPlaceholder("Search events"),
  },
  {
    name: "explore groups",
    path: `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    ready: (page) => page.getByPlaceholder("Search groups"),
  },
  {
    name: "statistics",
    path: "/stats",
    ready: (page) => page.getByText("Global growth trends across all communities."),
  },
  {
    name: "documentation",
    path: "/docs",
    ready: (page) => page.locator(".ocg-docs-root .content"),
  },
  {
    name: "badge verification",
    path: "/badges/verify",
    ready: (page) => page.getByRole("heading", { name: "Verify an OCG badge" }),
  },
  {
    name: "badge credential",
    path: "/badges/credentials/dadadada-dada-dada-dada-dadadadada02",
    ready: (page) => page.getByRole("heading", { name: "Host" }),
  },
  {
    name: "login",
    path: "/log-in",
    ready: (page) => page.getByRole("heading", { name: "Log In" }),
  },
  {
    name: "sign-up",
    path: "/sign-up",
    ready: (page) => page.getByRole("heading", { name: "Sign Up" }),
  },
  {
    name: "not found",
    path: "/responsive-missing-page",
    ready: (page) => page.getByRole("heading", { name: "We could not find that page" }),
  },
];

test.describe("public responsive layouts", () => {
  // Verify the ready state and layout bounds at every supported breakpoint.
  const expectResponsiveLayout = async (page, responsivePage) => {
    // Load the representative page at the narrowest supported breakpoint.
    await page.setViewportSize({ width: BREAKPOINTS[0].width, height: 900 });
    await navigateToPath(page, responsivePage.path);
    await expect(responsivePage.ready(page)).toBeVisible({ timeout: 15_000 });

    for (const breakpoint of BREAKPOINTS) {
      await test.step(`${breakpoint.name}: ${breakpoint.width}px`, async () => {
        await page.setViewportSize({ width: breakpoint.width, height: 900 });
        await expect(responsivePage.ready(page)).toBeVisible();

        const layoutBounds = await page.evaluate(() => ({
          clientWidth: document.documentElement.clientWidth,
          mainVisible: document.querySelector("#main-content")?.getClientRects().length > 0,
          scrollWidth: document.documentElement.scrollWidth,
        }));

        expect(layoutBounds.mainVisible).toBe(true);
        expect(layoutBounds.scrollWidth).toBeLessThanOrEqual(layoutBounds.clientWidth + 2);
      });
    }
  };

  for (const responsivePage of RESPONSIVE_PAGES.filter((entry) => !entry.authenticated)) {
    test(`${responsivePage.name} fits every supported breakpoint`, async ({ page }) => {
      await expectResponsiveLayout(page, responsivePage);
    });
  }

  for (const responsivePage of RESPONSIVE_PAGES.filter((entry) => entry.authenticated)) {
    test(`${responsivePage.name} fits every supported breakpoint`, async ({ member1Page }) => {
      await expectResponsiveLayout(member1Page, responsivePage);
    });
  }
});
