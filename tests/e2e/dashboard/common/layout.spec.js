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

// One entry per dashboard scope; `title` is the menu shell title the header content aligns with.
const DASHBOARD_CHROME_CASES = [
  { fixture: "member1Page", name: "user", path: "/dashboard/user?tab=events", title: "User Dashboard" },
  {
    fixture: "organizerGroupPage",
    name: "group",
    path: "/dashboard/group?tab=members",
    title: "Group Dashboard",
  },
  {
    fixture: "adminCommunityPage",
    name: "community",
    path: "/dashboard/community?tab=groups",
    title: "Community Dashboard",
  },
];

// Sidebar width and content padding, in px, at the edges of the lg and xl bands.
const DASHBOARD_CHROME_WIDTHS = [
  { padding: 24, sidebar: 225, width: 1023 },
  { padding: 24, sidebar: 225, width: 1024 },
  { padding: 24, sidebar: 225, width: 1279 },
  { padding: 48, sidebar: 225, width: 1280 },
  { padding: 48, sidebar: 225, width: 1535 },
  { padding: 48, sidebar: 300, width: 1536 },
];

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
  test("keeps the drawer and placeholder aligned at the md breakpoint on touch screens @mobile", async ({
    member1Page,
  }) => {
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

  test("keeps the md layout below md with a mouse and scrolls horizontally", async ({ member1Page }) => {
    // Load user content at md before narrowing the mouse-driven window.
    await member1Page.setViewportSize({ width: 768, height: 900 });
    await navigateToPath(member1Page, "/dashboard/user?tab=events");
    const main = member1Page.locator("#dashboard-main-content");
    const header = member1Page.locator("#dashboard-header");
    const sidebar = member1Page.locator("aside#dashboard-menu-drawer");
    await expect(main).toBeVisible();
    expect((await getDocumentWidths(member1Page)).overflow).toBe(0);

    // Verify narrow windows keep the static sidebar and content instead of the notice.
    for (const width of [767, 600]) {
      await test.step(`${width}px`, async () => {
        await member1Page.setViewportSize({ width, height: 500 });
        await expect(main).toBeVisible();
        await expect(member1Page.getByText(MOBILE_WARNING, { exact: true })).toBeHidden();
        await expect(member1Page.getByRole("button", { name: "Open dashboard menu" })).toBeHidden();
        await expect.poll(() => getBoundingRectValue(sidebar, "width")).toBeCloseTo(225, 0);
        await expectReachableSidebar(member1Page);

        // Verify the whole page keeps the md width and the header scrolls with the content.
        const { clientWidth, overflow, scrollbarWidth } = await getDocumentWidths(member1Page);
        expect(overflow).toBe(768 - scrollbarWidth - clientWidth);
        await member1Page.evaluate(() =>
          window.scrollTo({
            left: document.documentElement.scrollWidth,
            top: document.documentElement.scrollHeight,
          }),
        );
        await expect.poll(() => getBoundingRectValue(main, "right")).toBeLessThanOrEqual(clientWidth);
        await expect.poll(() => getBoundingRectValue(header, "right")).toBeCloseTo(clientWidth, 0);
        expect(await getBoundingRectValue(header, "left")).toBeCloseTo(-overflow, 0);
        expect(await getBoundingRectValue(sidebar, "left")).toBeCloseTo(-overflow, 0);

        // Verify the header and sidebar still stick to the top after scrolling down.
        expect(await getBoundingRectValue(header, "top")).toBe(0);
        expect(await getBoundingRectValue(sidebar, "top")).toBe(0);
        await member1Page.evaluate(() => window.scrollTo({ left: 0, top: 0 }));
      });
    }

    // Verify a page loaded directly in a narrow window starts with the same layout.
    await test.step("600px on load", async () => {
      await member1Page.setViewportSize({ width: 600, height: 500 });
      await navigateToPath(member1Page, "/dashboard/user?tab=events");
      await expect(main).toBeVisible();
      await expect(member1Page.getByText(MOBILE_WARNING, { exact: true })).toBeHidden();
      await expect(member1Page.getByRole("button", { name: "Open dashboard menu" })).toBeHidden();
      await expect.poll(() => getBoundingRectValue(sidebar, "width")).toBeCloseTo(225, 0);
      expect(await getBoundingRectValue(sidebar, "left")).toBe(0);
      await expectReachableSidebar(member1Page);
      const { clientWidth, overflow, scrollbarWidth } = await getDocumentWidths(member1Page);
      expect(overflow).toBe(768 - scrollbarWidth - clientWidth);
    });
  });

  for (const chromeCase of DASHBOARD_CHROME_CASES) {
    test(`${chromeCase.name} dashboard sizes the sidebar, header and content padding per breakpoint`, async ({
      pageAs,
    }) => {
      // Load the dashboard at the widest md width before measuring its chrome.
      const page = await pageAs(chromeCase.fixture);
      await page.setViewportSize({ width: DASHBOARD_CHROME_WIDTHS[0].width, height: 900 });
      await navigateToPath(page, chromeCase.path);
      const sidebar = page.locator("aside#dashboard-menu-drawer");
      const menuTitle = sidebar.getByText(chromeCase.title, { exact: true });
      const headerContent = page.locator("#dashboard-header #header");
      const contentShell = page.locator("#dashboard-main-content > :first-child");
      await expect(menuTitle).toBeVisible();
      await expect(headerContent).toBeVisible();

      // Verify the sidebar width, header alignment and content padding at each width.
      for (const { padding, sidebar: sidebarWidth, width } of DASHBOARD_CHROME_WIDTHS) {
        await test.step(`${width}px`, async () => {
          await page.setViewportSize({ width, height: 900 });
          await expect
            .poll(async () => Math.abs((await getBoundingRectValue(sidebar, "width")) - sidebarWidth))
            .toBeLessThanOrEqual(1);
          const headerLeft = await getBoundingRectValue(headerContent, "left");
          const titleLeft = await getBoundingRectValue(menuTitle, "left");
          expect(Math.abs(headerLeft - titleLeft)).toBeLessThanOrEqual(0.5);
          await expect(contentShell).toHaveCSS("padding-left", `${padding}px`);
        });
      }
    });
  }

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

  test("community settings gallery shows 3 columns at md and 4 from lg", async ({ adminCommunityPage }) => {
    // Load community settings at the narrowest md viewport.
    await adminCommunityPage.setViewportSize({ width: 768, height: 900 });
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=settings");
    const galleryGrid = adminCommunityPage
      .locator('gallery-field[field-name="photos_urls"] div.grid')
      .first();
    await expect(galleryGrid).toBeVisible();

    // Verify each breakpoint reports the declared gallery column count.
    for (const { columns, name, width } of [
      { columns: 3, name: "md", width: 768 },
      { columns: 3, name: "md widest", width: 1023 },
      { columns: 4, name: "lg", width: 1024 },
      { columns: 4, name: "xl", width: 1280 },
    ]) {
      await test.step(`${name}: ${width}px`, async () => {
        await adminCommunityPage.setViewportSize({ width, height: 900 });
        await expect.poll(() => getGridColumnCount(galleryGrid)).toBe(columns);
      });
    }
  });

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

/**
 * Asserts the static dashboard sidebar is exposed to assistive technologies and keyboard focus.
 * @param {import("@playwright/test").Page} page - Dashboard page to inspect.
 * @returns {Promise<void>}
 */
const expectReachableSidebar = async (page) => {
  const navigation = page.getByRole("navigation", { name: "Dashboard navigation" });
  await expect(navigation).toBeVisible();
  await expect(navigation).not.toHaveAttribute("inert");
  const firstLink = navigation.getByRole("link").first();
  await firstLink.focus();
  await expect(firstLink).toBeFocused();
};

/**
 * Returns one edge or size of an element's bounding client rect.
 * @param {import("@playwright/test").Locator} locator - Element to measure.
 * @param {"left"|"right"|"top"|"width"} property - Bounding rect property to read.
 * @returns {Promise<number>} Measured value in CSS pixels.
 */
const getBoundingRectValue = (locator, property) =>
  locator.evaluate((element, key) => element.getBoundingClientRect()[key], property);

/**
 * Returns the document client width, its horizontal overflow, and the classic scrollbar width.
 * @param {import("@playwright/test").Page} page - Page to measure.
 * @returns {Promise<{clientWidth: number, overflow: number, scrollbarWidth: number}>} Widths in CSS pixels.
 */
const getDocumentWidths = (page) =>
  page.evaluate(() => {
    const root = document.documentElement;
    return {
      clientWidth: root.clientWidth,
      overflow: root.scrollWidth - root.clientWidth,
      scrollbarWidth: window.innerWidth - root.clientWidth,
    };
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
