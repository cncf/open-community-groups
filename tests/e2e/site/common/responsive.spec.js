import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_OPEN_CHECK_IN_EVENT,
  TEST_SITE_TITLE,
  navigateToPath,
} from "../../utils.js";

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
    name: "event check-in",
    // The check-in route requires a signed-in user, so it uses an auth fixture.
    authenticated: true,
    path: `/${TEST_COMMUNITY_NAME}/check-in/${TEST_OPEN_CHECK_IN_EVENT.id}`,
    ready: (page) => page.getByRole("heading", {
      name: TEST_OPEN_CHECK_IN_EVENT.name,
    }),
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

// Return the number of computed CSS grid columns for one visible section.
const getGridColumnCount = (grid) =>
  grid.evaluate((element) =>
    getComputedStyle(element).gridTemplateColumns.split(" ").filter(Boolean).length,
  );

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

  test("card grids change columns at their declared breakpoints", async ({ page }) => {
    // Verify the site community cards change at the sm breakpoint.
    await navigateToPath(page, "/");
    const communityGrid = page
      .getByText("Communities", { exact: true })
      .locator("..")
      .locator(".grid");
    await page.setViewportSize({ width: 639, height: 900 });
    expect(await getGridColumnCount(communityGrid)).toBe(1);
    await page.setViewportSize({ width: 640, height: 900 });
    expect(await getGridColumnCount(communityGrid)).toBe(2);

    // Verify community group cards change at the md breakpoint.
    await navigateToPath(page, `/${TEST_COMMUNITY_NAME}`);
    const communityGroupsGrid = page
      .getByText("Latest groups added", { exact: true })
      .locator("xpath=../following-sibling::div[1]/div[contains(@class,'grid')]");
    await page.setViewportSize({ width: 767, height: 900 });
    expect(await getGridColumnCount(communityGroupsGrid)).toBe(1);
    await page.setViewportSize({ width: 768, height: 900 });
    expect(await getGridColumnCount(communityGroupsGrid)).toBe(2);

    // Verify group event cards change at the lg breakpoint.
    await navigateToPath(page, `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`);
    const groupEventsGrid = page
      .getByText("Upcoming Events", { exact: true })
      .locator("xpath=../following-sibling::div[contains(@class,'grid')]");
    await page.setViewportSize({ width: 1023, height: 900 });
    expect(await getGridColumnCount(groupEventsGrid)).toBe(1);
    await page.setViewportSize({ width: 1024, height: 900 });
    expect(await getGridColumnCount(groupEventsGrid)).toBe(2);

    // Verify event speaker cards change at both md and lg breakpoints.
    await navigateToPath(
      page,
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`,
    );
    const speakersGrid = page.locator(".regular-speakers-grid");
    await page.setViewportSize({ width: 767, height: 900 });
    expect(await getGridColumnCount(speakersGrid)).toBe(1);
    await page.setViewportSize({ width: 768, height: 900 });
    expect(await getGridColumnCount(speakersGrid)).toBe(2);
    await page.setViewportSize({ width: 1024, height: 900 });
    expect(await getGridColumnCount(speakersGrid)).toBe(3);
  });
});
