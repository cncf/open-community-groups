import { expect, test } from "../../fixtures.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_SITE_TITLE,
} from "../../seed.js";
import { getCommunityBanner, navigateToPath } from "../../utils.js";

const GRID_CASES = [
  {
    name: "site communities",
    path: "/",
    ready: (page) => page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE }),
    grid: (page) => page.getByText("Communities", { exact: true }).locator("..").locator("div.grid"),
    widths: [
      { name: "below sm", width: 639, columns: 1 },
      { name: "sm", width: 640, columns: 2 },
      { name: "lg", width: 1024, columns: 3 },
    ],
  },
  {
    name: "site latest groups",
    path: "/",
    ready: (page) => page.getByText("Latest groups added", { exact: true }),
    grid: (page) =>
      page.getByText("Latest groups added", { exact: true }).locator("..").locator("..").locator("div.grid"),
    widths: [
      { name: "below md", width: 767, columns: 1 },
      { name: "md", width: 768, columns: 2 },
    ],
  },
  {
    name: "community latest groups",
    path: `/${TEST_COMMUNITY_NAME}`,
    ready: (page) => page.getByText("About this community", { exact: true }),
    grid: (page) =>
      page
        .getByText("Latest groups added", { exact: true })
        .locator("xpath=../following-sibling::div[1]/div[contains(@class,'grid')]"),
    widths: [
      { name: "below md", width: 767, columns: 1 },
      { name: "md", width: 768, columns: 2 },
    ],
  },
  {
    name: "group upcoming events",
    path: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`,
    ready: (page) => page.getByRole("heading", { level: 1, name: TEST_GROUP_NAME }),
    grid: (page) =>
      page
        .getByText("Upcoming Events", { exact: true })
        .locator("xpath=../following-sibling::div[contains(@class,'grid')]"),
    widths: [
      { name: "below lg", width: 1023, columns: 1 },
      { name: "lg", width: 1024, columns: 2 },
    ],
  },
  {
    name: "event speaker",
    path: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`,
    ready: (page) => page.getByRole("heading", { level: 1, name: TEST_EVENT_NAME }),
    grid: (page) => page.locator(".regular-speakers-grid"),
    widths: [
      { name: "below md", width: 767, columns: 1 },
      { name: "md", width: 768, columns: 2 },
      { name: "lg", width: 1024, columns: 3 },
    ],
  },
];

const MOBILE_WARNING = "This dashboard is not optimized yet for mobile devices";

test.describe("dashboard layout", () => {
  test("keeps the drawer and placeholder aligned at the md breakpoint", async ({ member1Page }) => {
    // Load unsupported user content at the first desktop width.
    await member1Page.setViewportSize({ width: 768, height: 900 });
    await navigateToPath(member1Page, "/dashboard/user?tab=events");
    const main = member1Page.locator("#dashboard-main-content");
    const openMenuButton = member1Page.getByRole("button", {
      name: "Open dashboard menu",
    });
    const warning = member1Page.getByText(MOBILE_WARNING, { exact: true });
    await expect(main).toBeVisible();
    await expect(openMenuButton).toBeHidden();
    await expect(warning).toBeHidden();

    // Cross below md and verify the placeholder always has its drawer trigger.
    await member1Page.setViewportSize({ width: 767, height: 900 });
    await expect(main).toBeHidden();
    await expect(warning).toBeVisible();
    await expect(openMenuButton).toBeVisible();
    await openMobileDashboardDrawer(member1Page);

    // Return to md and verify the static sidebar and content replace mobile state.
    await member1Page.setViewportSize({ width: 768, height: 900 });
    await expect(main).toBeVisible();
    await expect(warning).toBeHidden();
    await expect(openMenuButton).toBeHidden();
  });

  for (const gridCase of GRID_CASES) {
    test(`${gridCase.name} grid changes columns at declared breakpoints`, async ({ page }) => {
      // Load the page at the first asserted breakpoint before measuring the grid.
      await page.setViewportSize({ width: gridCase.widths[0].width, height: 900 });
      await navigateToPath(page, gridCase.path);
      await expect(gridCase.ready(page)).toBeVisible();

      // Verify each breakpoint reports the declared grid column count.
      for (const widthCase of gridCase.widths) {
        await test.step(`${widthCase.name}: ${widthCase.width}px`, async () => {
          await page.setViewportSize({ width: widthCase.width, height: 900 });
          const grid = gridCase.grid(page);
          await expect(grid.first()).toBeVisible();
          expect(await getGridColumnCount(grid.first())).toBe(widthCase.columns);
        });
      }
    });
  }

  test("community cards show a darker inset shadow on hover", async ({ page }) => {
    // Load the public home page and target a seeded community card.
    await navigateToPath(page, "/");
    const communityCard = page
      .getByRole("link")
      .filter({ has: getCommunityBanner(page, TEST_COMMUNITY_TITLE) })
      .first();

    // Verify hovering enables the pseudo-element inset shadow.
    await expect(communityCard).toBeVisible();
    await expect
      .poll(() => communityCard.evaluate((element) => window.getComputedStyle(element, "::after").boxShadow))
      .toBe("none");
    await communityCard.hover();
    await expect
      .poll(() => communityCard.evaluate((element) => window.getComputedStyle(element, "::after").boxShadow))
      .not.toBe("none");
  });
});

/** Returns the computed CSS grid column count for a grid element. */
const getGridColumnCount = (grid) =>
  grid.evaluate((element) => getComputedStyle(element).gridTemplateColumns.split(" ").filter(Boolean).length);

/** Opens the mobile dashboard drawer and returns its visible panel. */
const openMobileDashboardDrawer = async (page) => {
  const openMenuButton = page.getByRole("button", {
    name: "Open dashboard menu",
  });
  await expect(openMenuButton).toBeVisible();
  await openMenuButton.click();

  const drawer = page.locator("#dashboard-menu-drawer");
  await expect(drawer).toBeVisible();

  return drawer;
};
