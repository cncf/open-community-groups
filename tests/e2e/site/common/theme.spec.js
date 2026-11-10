import { fileURLToPath } from "node:url";

import { expect, test, testAtBothWidths } from "../../fixtures.js";

import { TEST_COMMUNITY_LOGO_URL, TEST_SITE_TITLE } from "../../seed.js";
import {
  buildE2eUrl,
  expectFocusIndicator,
  getSectionByHeading,
  navigateToPath,
  pressKeyUntilFocused,
  useTheme,
  waitForHtmxSettle,
} from "../../utils.js";
import { getAttendanceContainer } from "../event/helpers.js";
import { getAccountSheet } from "./helpers.js";
import { loadPublicPage, PUBLIC_PAGES } from "./public-pages.js";

// Canvas the critical style paints before the stylesheet loads: the dark surface, #181514.
const DARK_CANVAS_BACKGROUND = "rgb(24, 21, 20)";
// Dark `raised` token, #201d1b: menus, popovers and sheets.
const DARK_RAISED_BACKGROUND = "rgb(32, 29, 27)";
// Dark `canvas` token, #0b0a09: the page shell behind content cards.
const DARK_SHELL_BACKGROUND = "rgb(11, 10, 9)";
// Dark `surface` token, #181514: the root, content cards, sticky bars and section strips.
const DARK_SURFACE_BACKGROUND = "rgb(24, 21, 20)";
// Seeded event page, with the phone CTA bar, section strips and the contact sheet.
const EVENT_PAGE = PUBLIC_PAGES.find(({ name }) => name === "event");
// Outline of focused links inside the footer ink island, in both themes.
const FOOTER_OUTLINE = "rgb(255, 255, 255)";
// Seeded group page, with the logo plate and the location raster placeholder.
const GROUP_PAGE = PUBLIC_PAGES.find(({ name }) => name === "group");
// Smallest height of a theme choice at every width, in CSS pixels.
const MIN_CHOICE_HEIGHT_PX = 44;
// Page whose shell is the canvas at every width, with one content card.
const NOT_FOUND_PAGE = PUBLIC_PAGES.find(({ name }) => name === "not found");
// Background of a light-island plate, white in both color themes.
const PLATE_BACKGROUND = "rgb(255, 255, 255)";
// Seeded pages with entity logo plates: the logo macro plate in the summary and, further down,
// the Tech Corp sponsor badge plate.
const PLATE_PAGES = [
  { logoPlate: (page) => page.locator("[data-group-logo] .plate"), publicPage: GROUP_PAGE },
  {
    logoPlate: (page) => page.getByRole("region", { name: "Event summary" }).locator(".plate"),
    publicPage: EVENT_PAGE,
  },
];
// Stored choice and OS color scheme pairs the pre-paint script resolves.
const PRE_PAINT_CASES = [
  { name: "stored dark on a light OS", stored: "dark", system: "light", theme: "dark" },
  { name: "stored light on a dark OS", stored: "light", system: "dark", theme: "light" },
  { name: "System on a dark OS", stored: "system", system: "dark", theme: "dark" },
];
// Focus outline in dark: the site's dark primary edge role, emitted by the brand ramp.
const PRIMARY_DARK_EDGE_OUTLINE = "var(--ocg-primary-dark-edge)";
// Opacity of the raster placeholder behind "Location not provided", per color theme.
const RASTER_OPACITY = { dark: "0.1", light: "0.3" };
// Image served for the injected site header logos.
const SITE_LOGO_FILE = fileURLToPath(
  new URL("../../../../ocg-server/static/images/e2e/badges/host.png", import.meta.url),
);
// URLs of the injected site header logos, each served by `routeSiteLogo`.
const SITE_LOGO_URLS = {
  broken: "/e2e-theme/site-logo-broken.png",
  dark: "/e2e-theme/site-logo-dark.png",
  light: "/e2e-theme/site-logo-light.png",
};
// Application stylesheet, held back to reproduce a cold CSS cache.
const STYLESHEET_ROUTE = "**/static/css/styles.*.css";
// Storage key of the color theme choice (see static/js/common/theme.js).
const THEME_STORAGE_KEY = "ocg_theme";
// Computed background while no rule paints one, such as the canvas before the stylesheet loads.
const TRANSPARENT_BACKGROUND = "rgba(0, 0, 0, 0)";

test.describe("color theme", () => {
  testAtBothWidths("System follows the OS color scheme live", async ({ page }) => {
    // Count color theme changes from the first script on, then load the page.
    await recordThemeChanges(page);
    await navigateToPath(page, "/stats");
    await markDocument(page);

    // Verify the light OS renders light without announcing a change.
    await expectTheme(page, "light");
    expect(await readThemeChanges(page)).toEqual([]);

    // Turn the OS dark, then light again.
    await useTheme(page, { system: "dark" });
    await expectTheme(page, "dark");
    await useTheme(page, { system: "light" });
    await expectTheme(page, "light");

    // Verify one change per resolved switch, in the same document.
    expect(await readThemeChanges(page)).toEqual([
      { preference: "system", previousTheme: "light", theme: "dark" },
      { preference: "system", previousTheme: "dark", theme: "light" },
    ]);
    await expectSameDocument(page);
  });

  test("guest menu switches the color theme live @smoke", async ({ page }) => {
    await expectGuestMenuLiveSwitch(page);
  });

  test("guest account sheet switches the color theme live @mobile", async ({ page }) => {
    await expectGuestMenuLiveSwitch(page);
  });

  test("stored color theme applies before the body on reload @smoke", async ({ page }) => {
    await expectNoFlashOnReload(page);
  });

  test("stored color theme applies before the body on reload @mobile", async ({ page }) => {
    await expectNoFlashOnReload(page);
  });

  for (const { name, stored, system, theme } of PRE_PAINT_CASES) {
    testAtBothWidths(`cold stylesheet load paints the canvas for ${name}`, async ({ page }) => {
      // Hold the application stylesheet, as on a cold CSS cache, and start loading the page.
      await useTheme(page, { stored, system });
      const { promise: heldStylesheet, resolve: holdStylesheet } = Promise.withResolvers();
      await page.route(STYLESHEET_ROUTE, holdStylesheet, { times: 1 });
      await page.goto(buildE2eUrl("/stats"), { waitUntil: "commit" });
      const stylesheet = await heldStylesheet;

      try {
        // Verify the canvas while the parser waits for the stylesheet, before <body> exists.
        await page.waitForFunction(() => document.documentElement.hasAttribute("data-theme"), undefined, {
          polling: 100,
        });
        expect(await readCanvas(page)).toEqual({
          background: theme === "dark" ? DARK_CANVAS_BACKGROUND : TRANSPARENT_BACKGROUND,
          bodyParsed: false,
          colorScheme: theme,
        });
      } finally {
        // Release the stylesheet; after a failure the page may already be closing.
        await stylesheet.continue().catch(() => {});
      }
      await page.waitForLoadState("load");
    });
  }

  test("color theme survives boosted navigation and history restore", async ({ isMobile, page }) => {
    // Pick Dark on the home page.
    await navigateToPath(page, "/");
    await markDocument(page);
    const choices = getThemeChoices(page);
    await openAccountMenu(page);
    await choices.dark.click();
    await expectTheme(page, "dark");

    // Follow the boosted Stats link and verify the theme stays without a reload.
    await followStatsLink(page, isMobile);
    await expectSameDocument(page);
    await expectTheme(page, "dark");

    // Pick Light on the stats page, whose menu shows Dark first.
    await openAccountMenu(page);
    await expectCheckedChoice(choices, "dark");
    await choices.light.click();
    await expectTheme(page, "light");
    await closeAccountMenu(page);

    // Go back to the home snapshot, taken while Dark was checked.
    await page.goBack();
    await expect(page).not.toHaveURL(/\/stats$/u);
    await waitForHtmxSettle(page);

    // Verify the restored page shows Light.
    await expectTheme(page, "light");
    await openAccountMenu(page);
    await expectCheckedChoice(choices, "light");
  });

  test("lazily loaded menu opens with the stored choice checked", async ({ page }) => {
    // Seed Dark, then load a page whose menu arrives through /section/user-menu.
    await useTheme(page, { stored: "dark" });
    await navigateToPath(page, "/");
    await expectTheme(page, "dark");

    // Verify the loaded menu shows Dark checked.
    await openAccountMenu(page);
    await expectCheckedChoice(getThemeChoices(page), "dark");
  });

  test("inline member menu switches the color theme live", async ({ member1Page: page }) => {
    // Open the menu rendered inline on the user dashboard.
    await navigateToPath(page, "/dashboard/user");
    await markDocument(page);
    await openAccountMenu(page);
    const choices = getThemeChoices(page);
    await expectCheckedChoice(choices, "system");

    // Pick Dark, then System.
    await choices.dark.click();
    await expectChoiceApplied(page, choices, { preference: "dark", stored: "dark", theme: "dark" });
    await choices.system.click();
    await expectChoiceApplied(page, choices, { preference: "system", stored: null, theme: "light" });
    await expectSameDocument(page);
  });

  test("color theme follows another tab", async ({ context, page }) => {
    // Load the same page in two tabs of one context.
    await navigateToPath(page, "/stats");
    await markDocument(page);
    const otherPage = await context.newPage();
    await navigateToPath(otherPage, "/stats");
    const otherChoices = getThemeChoices(otherPage);

    // Pick Dark in the other tab and verify the first follows without a reload.
    await openAccountMenu(otherPage);
    await otherChoices.dark.click();
    await expectTheme(page, "dark");
    await openAccountMenu(page);
    await expectCheckedChoice(getThemeChoices(page), "dark");
    await closeAccountMenu(page);

    // Pick System in the other tab and verify the first follows its light OS.
    await otherChoices.system.click();
    await expectTheme(page, "light");
    await openAccountMenu(page);
    await expectCheckedChoice(getThemeChoices(page), "system");
    await expectSameDocument(page);
  });

  testAtBothWidths(
    "blocked storage still applies the color theme to the document",
    async ({ isMobile, page }) => {
      // Make every localStorage access throw, and turn the OS dark.
      await blockLocalStorage(page);
      await useTheme(page, { system: "dark" });

      // Verify the page renders by the OS.
      await navigateToPath(page, "/");
      await markDocument(page);
      await expectTheme(page, "dark");

      // Pick Light; it applies although it cannot be stored.
      const choices = getThemeChoices(page);
      await openAccountMenu(page);
      await choices.light.click();
      await expectTheme(page, "light");
      await expectCheckedChoice(choices, "light");

      // Follow the boosted Stats link and verify the choice survives.
      await followStatsLink(page, isMobile);
      await expectSameDocument(page);
      await expectTheme(page, "light");
      await openAccountMenu(page);
      await expectCheckedChoice(choices, "light");

      // On phones, verify Desktop version does not reload into a mode it could not store.
      if (isMobile) {
        const desktopVersionItem = getAccountSheet(page).userMenu.getByRole("menuitem", {
          name: "Desktop version",
        });
        await expectNoNavigation(page, () => desktopVersionItem.click());
        await expectSameDocument(page);
        expect(await page.evaluate(() => document.documentElement.hasAttribute("data-viewport-mode"))).toBe(
          false,
        );
      }
    },
  );

  test("color theme is re-read after a back/forward cache restore @smoke", async ({
    context,
    page,
  }, testInfo) => {
    // Record whether the page comes back from the back/forward cache.
    await page.addInitScript(() => {
      window.ocgPageShows = [];
      window.addEventListener("pageshow", (event) => window.ocgPageShows.push(event.persisted));
    });

    // Load a page, then leave it with a full navigation.
    await navigateToPath(page, "/stats");
    await expectTheme(page, "light");
    await navigateToPath(page, "/");

    // Pick Dark in a second tab of the same context.
    const otherPage = await context.newPage();
    await navigateToPath(otherPage, "/stats");
    await openAccountMenu(otherPage);
    await getThemeChoices(otherPage).dark.click();
    await expectTheme(otherPage, "dark");

    // Go back to the first page and verify the theme and the checked choice.
    await page.goBack();
    await expect(page).toHaveURL(/\/stats$/u);
    await expectTheme(page, "dark");
    await openAccountMenu(page);
    await expectCheckedChoice(getThemeChoices(page), "dark");

    // Note whether the engine restored the page; the test passes either way.
    const restored = await page.evaluate(() => window.ocgPageShows.includes(true));
    testInfo.annotations.push({
      type: "bfcache",
      description: restored
        ? "pageshow.persisted: restored from the back/forward cache"
        : "pageshow.persisted never true: the engine reloaded the page",
    });
  });
});

test.describe("dark palette", () => {
  testAtBothWidths("stored dark paints the pilot surfaces", async ({ isMobile, page }) => {
    // Load the not-found page in stored dark.
    await useTheme(page, { stored: "dark" });
    await loadPublicPage(page, NOT_FOUND_PAGE);
    await expectTheme(page, "dark");

    // Verify the root, the shell and the content card.
    await expect(page.locator("html")).toHaveCSS("background-color", DARK_SURFACE_BACKGROUND);
    await expect(getShell(page)).toHaveCSS("background-color", DARK_SHELL_BACKGROUND);
    await expect(NOT_FOUND_PAGE.ready(page).locator("xpath=../..")).toHaveCSS(
      "background-color",
      DARK_SURFACE_BACKGROUND,
    );

    if (isMobile) {
      // Verify the sticky header and the open account sheet.
      await expect(page.locator("#header")).toHaveCSS("background-color", DARK_SURFACE_BACKGROUND);
      await openAccountMenu(page);
      await expect(getAccountSheet(page).userMenu.locator(".sheet-panel")).toHaveCSS(
        "background-color",
        DARK_RAISED_BACKGROUND,
      );

      // Load the event page and verify the CTA bar and a section strip.
      await loadPublicPage(page, EVENT_PAGE);
      await expect(getAttendanceContainer(page)).toHaveCSS("background-color", DARK_SURFACE_BACKGROUND);
      await expect(page.locator(".section-strip:visible").first()).toHaveCSS(
        "background-color",
        DARK_SURFACE_BACKGROUND,
      );

      // Open the contact sheet and verify its panel is raised.
      await page.locator("#open-contact-modal").click();
      const contactPanel = page.locator("#contact-modal .sheet-panel");
      await expect(contactPanel).toBeVisible();
      await expect(contactPanel).toHaveCSS("background-color", DARK_RAISED_BACKGROUND);
    }
  });

  test("light islands keep their light colors in stored dark", async ({ page }) => {
    // Fail the group logo, so the broken-image handler puts its stone icon in the logo plate.
    await page.route(`**${TEST_COMMUNITY_LOGO_URL}`, (route) => route.abort());

    // Read the island colors in light, then in stored dark.
    const light = await readIslandColors(page);
    await useTheme(page, { stored: "dark" });
    const dark = await readIslandColors(page);
    await expectTheme(page, "dark");

    // Verify the page turned dark around islands that kept their light colors.
    expect(dark.root).toBe(DARK_SURFACE_BACKGROUND);
    expect(dark.islands).toEqual(light.islands);
  });

  test("print renders stored dark with the light colors", async ({ page }) => {
    // Read the light colors on screen.
    await loadPublicPage(page, NOT_FOUND_PAGE);
    const light = await readPrintColors(page);
    expect(light.colorScheme).toBe("light");

    // Load the page in stored dark for print.
    await useTheme(page, { stored: "dark" });
    await page.emulateMedia({ media: "print" });
    await loadPublicPage(page, NOT_FOUND_PAGE);

    // Verify the dark theme is resolved but print computes the light values.
    expect(await page.locator("html").getAttribute("data-theme")).toBe("dark");
    expect(await readPrintColors(page)).toEqual(light);
  });

  test("JavaScript disabled follows a dark OS through the stylesheet", async ({ browser, browserHealth }) => {
    // Open a context without JavaScript on a dark OS.
    const context = await browser.newContext({ colorScheme: "dark", javaScriptEnabled: false });
    browserHealth.track(context);

    try {
      // Load the not-found page; without JavaScript htmx never loads, so wait for the load event.
      const page = await context.newPage();
      await page.goto(buildE2eUrl(NOT_FOUND_PAGE.path), { waitUntil: "load" });
      await expect(NOT_FOUND_PAGE.ready(page)).toBeVisible();

      // Verify no script resolved the theme and the prefers-color-scheme fallback paints dark.
      expect(await page.locator("html").getAttribute("data-theme")).toBeNull();
      await expect(page.locator("html")).toHaveCSS("background-color", DARK_SURFACE_BACKGROUND);
      await expect(getShell(page)).toHaveCSS("background-color", DARK_SHELL_BACKGROUND);
      await expect(NOT_FOUND_PAGE.ready(page).locator("xpath=../..")).toHaveCSS(
        "background-color",
        DARK_SURFACE_BACKGROUND,
      );
    } finally {
      await context.close();
    }
  });

  test("keyboard focus draws the dark primary edge and keeps the footer outline white", async ({ page }) => {
    // Load the home page in stored dark.
    await useTheme(page, { stored: "dark" });
    await navigateToPath(page, "/");
    await expectTheme(page, "dark");
    const darkEdge = await page
      .locator("html")
      .evaluate((element) => getComputedStyle(element).getPropertyValue("--ocg-primary-dark-edge").trim());
    expect(darkEdge).not.toBe("");

    // Start from Explore all groups and Tab to the first group card.
    const section = getSectionByHeading(page, "Latest groups added");
    const groupCard = section.locator('a[href*="/group/"]').first();
    await section.getByRole("link", { name: "Explore all groups" }).filter({ visible: true }).focus();
    await expectFocusIndicator(groupCard, () => pressKeyUntilFocused(page, groupCard), {
      outlineColor: PRIMARY_DARK_EDGE_OUTLINE,
    });

    // Walk back from the powered-by link to the GitHub link in the footer.
    const footer = page.getByRole("contentinfo", { name: "Site footer" });
    const githubLink = footer.getByRole("link", { exact: true, name: "GitHub" });
    await footer.getByRole("link", { name: "CNCF Open Community Groups" }).focus();
    await expectFocusIndicator(githubLink, () => pressKeyUntilFocused(page, githubLink, "Shift+Tab"), {
      outlineColor: FOOTER_OUTLINE,
    });
  });

  test("raster placeholder dims further in dark", async ({ page }) => {
    // Load the group page, whose location card shows the raster placeholder, in light.
    const placeholder = page.locator('[data-group-summary-card="location"] .raster-placeholder');
    await loadPublicPage(page, GROUP_PAGE);
    await expect(placeholder).toHaveCSS("opacity", RASTER_OPACITY.light);

    // Load it again in stored dark.
    await useTheme(page, { stored: "dark" });
    await loadPublicPage(page, GROUP_PAGE);
    await expectTheme(page, "dark");
    await expect(placeholder).toHaveCSS("opacity", RASTER_OPACITY.dark);
  });
});

test.describe("logo plates", () => {
  test("site header shows one logo per theme and fetches the dark logo only in dark", async ({ page }) => {
    // Serve both logos, counting the dark logo requests, and load a page in light.
    await routeSiteLogo(page, SITE_LOGO_URLS.light);
    const countDarkRequests = await routeSiteLogo(page, SITE_LOGO_URLS.dark);
    await navigateToPath(page, "/explore");
    await expectTheme(page, "light");

    // Inject the light and dark pair the site header renders for both URLs.
    await injectSiteLogos(page, [
      buildSiteLogo("light", SITE_LOGO_URLS.light),
      buildSiteLogo("dark", SITE_LOGO_URLS.dark),
    ]);
    const darkLogo = getSiteLogo(page, "dark");
    const lightLogo = getSiteLogo(page, "light");

    // Verify light shows only the loaded light logo and never requests the dark one.
    await expect(getVisibleSiteLogos(page)).toHaveCount(1);
    await expect(lightLogo).toBeVisible();
    await expect(darkLogo).toBeHidden();
    await expectImageLoaded(lightLogo.locator("img"));
    expect(countDarkRequests()).toBe(0);

    // Pick Dark from the account menu.
    await pickTheme(page, "dark");

    // Verify dark loads and shows only the dark logo, with no broken-image placeholder.
    await expect(darkLogo).toBeVisible();
    await expect(lightLogo).toBeHidden();
    await expect(getVisibleSiteLogos(page)).toHaveCount(1);
    await expectImageLoaded(darkLogo.locator("img"));
    expect(countDarkRequests()).toBeGreaterThan(0);
    await expect(page.locator("#header [data-ocg-broken-image-icon]")).toHaveCount(0);
  });

  test("site header shows the light logo again after a broken dark logo", async ({ page }) => {
    // Serve the light logo, fail the dark one, and load a page in stored dark.
    await routeSiteLogo(page, SITE_LOGO_URLS.light);
    await routeSiteLogo(page, SITE_LOGO_URLS.broken, { broken: true });
    await useTheme(page, { stored: "dark" });
    await navigateToPath(page, "/explore");
    await expectTheme(page, "dark");

    // Inject the light and dark pair, with the failing dark URL.
    await injectSiteLogos(page, [
      buildSiteLogo("light", SITE_LOGO_URLS.light),
      buildSiteLogo("dark", SITE_LOGO_URLS.broken),
    ]);
    const lightLogo = getSiteLogo(page, "light");
    const placeholder = getSiteLogo(page, "dark").locator("[data-ocg-broken-image-icon] .icon-broken-image");

    // Verify dark shows the broken-image placeholder inside the dark slot.
    await expect(placeholder).toBeVisible();
    await expect(lightLogo).toBeHidden();

    // Pick Light from the account menu.
    await pickTheme(page, "light");

    // Verify the placeholder hides with its slot and the loaded light logo shows.
    await expect(placeholder).toBeHidden();
    await expect(lightLogo).toBeVisible();
    await expect(getVisibleSiteLogos(page)).toHaveCount(1);
    await expectImageLoaded(lightLogo.locator("img"));
  });

  test("plated site header logo paints its plate and edge only in dark", async ({ page }) => {
    // Serve the light logo and load a page in light.
    await routeSiteLogo(page, SITE_LOGO_URLS.light);
    await navigateToPath(page, "/explore");
    await expectTheme(page, "light");

    // Inject the plated wrapper the site header renders for a light URL alone.
    await injectSiteLogos(page, [buildSiteLogo("plated", SITE_LOGO_URLS.light)]);
    const platedLogo = getSiteLogo(page, "plated");

    // Verify light paints no plate behind the logo.
    await expect(platedLogo).toBeVisible();
    await expect(platedLogo).toHaveCSS("background-color", TRANSPARENT_BACKGROUND);
    await expect(platedLogo).toHaveCSS("box-shadow", "none");

    // Pick Dark from the account menu.
    await pickTheme(page, "dark");

    // Verify dark paints the white plate with the dark plate edge.
    const darkEdge = await readDarkPlateEdge(page);
    await expect(platedLogo).toHaveCSS("background-color", PLATE_BACKGROUND);
    await expect.poll(() => readStyle(platedLogo, "box-shadow")).toContain(darkEdge);
  });

  test("entity logo plates stay white and draw the dark edge in stored dark", async ({ page }) => {
    for (const { logoPlate, publicPage } of PLATE_PAGES) {
      await test.step(publicPage.name, async () => {
        // Load the page in stored light.
        await useTheme(page, { stored: "light" });
        await loadPublicPage(page, publicPage);
        await expectTheme(page, "light");
        const sponsorPlate = getSponsorPlate(page);

        // Verify neither plate draws a shadow and the logo plate outline is light stone-300.
        const lightStone300 = await readColor(page, "var(--ocg-light-stone-300)");
        await expect(logoPlate(page)).toHaveCSS("outline-color", lightStone300);
        await expect(logoPlate(page)).toHaveCSS("box-shadow", "none");
        await expect(sponsorPlate).toHaveCSS("box-shadow", "none");

        // Load it again in stored dark.
        await useTheme(page, { stored: "dark" });
        await loadPublicPage(page, publicPage);
        await expectTheme(page, "dark");
        const darkEdge = await readDarkPlateEdge(page);

        // Verify both plates stay white and draw the dark plate edge.
        await expect(logoPlate(page)).toHaveCSS("background-color", PLATE_BACKGROUND);
        await expect(sponsorPlate).toHaveCSS("background-color", PLATE_BACKGROUND);
        await expect(logoPlate(page)).toHaveCSS("outline-color", darkEdge);
        await expect.poll(() => readStyle(sponsorPlate, "box-shadow")).toContain(darkEdge);
      });
    }
  });
});

/**
 * Makes every `window.localStorage` access throw from the first script on, as when the browser or
 * a policy blocks storage.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>}
 */
const blockLocalStorage = (page) =>
  page.addInitScript(() => {
    Object.defineProperty(window, "localStorage", {
      configurable: true,
      get() {
        throw new DOMException("localStorage is blocked", "SecurityError");
      },
    });
  });

/**
 * Builds the markup `common/header.html` renders for one site header logo variant: a wrapper
 * with the logo image, eager except for the lazy dark image.
 * @param {"dark"|"light"|"plated"} variant - Logo variant, the `data-site-logo` value.
 * @param {string} src - Image URL.
 * @returns {string} Wrapper markup.
 */
const buildSiteLogo = (variant, src) => {
  const wrapperClass = variant === "plated" ? "relative plate" : "relative";
  const loading = variant === "dark" ? ' loading="lazy"' : "";
  return (
    `<span class="${wrapperClass}" data-site-logo="${variant}">` +
    '<img class="w-auto max-w-44 sm:max-w-52 h-10 sm:h-[42px] z-1" height="42" width="auto" ' +
    `data-ocg-broken-image-bg-class="bg-transparent" src="${src}" alt="${TEST_SITE_TITLE} logo"${loading}>` +
    "</span>"
  );
};

/**
 * Closes the account menu with Escape.
 * @param {import("@playwright/test").Page} page - Page with the menu open.
 * @returns {Promise<void>}
 */
const closeAccountMenu = async (page) => {
  await page.keyboard.press("Escape");
  await expect(getAccountSheet(page).userMenu).toBeHidden();
};

/**
 * Verifies that only the choice matching a preference is checked.
 * @param {Record<string, import("@playwright/test").Locator>} choices - Theme choices.
 * @param {"light"|"dark"|"system"} preference - Expected preference.
 * @returns {Promise<void>}
 */
const expectCheckedChoice = async (choices, preference) => {
  for (const [choice, locator] of Object.entries(choices)) {
    await expect(locator).toHaveAttribute("aria-checked", String(choice === preference));
  }
};

/**
 * Verifies a picked choice: the resolved theme, the stored key, the checked choice, and the menu
 * or account sheet still open.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {Record<string, import("@playwright/test").Locator>} choices - Theme choices.
 * @param {{ preference: string, stored: string|null, theme: string }} expected - Expected state;
 *   `stored` is null when the key is absent.
 * @returns {Promise<void>}
 */
const expectChoiceApplied = async (page, choices, { preference, stored, theme }) => {
  await expectTheme(page, theme);
  expect(await readStoredTheme(page)).toBe(stored);
  await expectCheckedChoice(choices, preference);
  await expect(getAccountSheet(page).userMenu).toBeVisible();
};

/**
 * Switches the color theme from the guest menu, the account sheet on phones, with the pointer
 * and the keyboard.
 * @param {import("@playwright/test").Page} page - Guest page.
 * @returns {Promise<void>}
 */
const expectGuestMenuLiveSwitch = async (page) => {
  // Open the guest menu.
  await navigateToPath(page, "/stats");
  await markDocument(page);
  const choices = getThemeChoices(page);
  await openAccountMenu(page);

  // Verify System starts checked and every choice is a full-size target.
  await expectCheckedChoice(choices, "system");
  for (const choice of Object.values(choices)) {
    expect((await choice.boundingBox()).height).toBeGreaterThanOrEqual(MIN_CHOICE_HEIGHT_PX);
  }

  // Pick Dark, then Light; the menu stays open.
  await choices.dark.click();
  await expectChoiceApplied(page, choices, { preference: "dark", stored: "dark", theme: "dark" });
  await choices.light.click();
  await expectChoiceApplied(page, choices, { preference: "light", stored: "light", theme: "light" });

  // Verify each choice is its own Tab stop and activates with Enter and with Space.
  await choices.light.focus();
  await page.keyboard.press("Tab");
  await expect(choices.dark).toBeFocused();
  await page.keyboard.press("Enter");
  await expectChoiceApplied(page, choices, { preference: "dark", stored: "dark", theme: "dark" });
  await page.keyboard.press("Tab");
  await expect(choices.system).toBeFocused();
  await page.keyboard.press("Shift+Tab");
  await page.keyboard.press("Shift+Tab");
  await expect(choices.light).toBeFocused();
  await page.keyboard.press("Space");
  await expectChoiceApplied(page, choices, { preference: "light", stored: "light", theme: "light" });

  // Turn the OS dark: the explicit Light choice ignores it.
  await useTheme(page, { system: "dark" });
  await expectTheme(page, "light");

  // Pick System; the key goes and the OS decides.
  await choices.system.click();
  await expectChoiceApplied(page, choices, { preference: "system", stored: null, theme: "dark" });
  await expectSameDocument(page);
};

/**
 * Verifies an image finished loading a real picture.
 * @param {import("@playwright/test").Locator} image - Image element.
 * @returns {Promise<void>}
 */
const expectImageLoaded = async (image) => {
  await expect
    .poll(() => image.evaluate((element) => element.complete && element.naturalWidth > 0))
    .toBe(true);
};

/**
 * Verifies the color theme the parser sees when it inserts `<body>`, on a load and a reload, for
 * every pre-paint case.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>}
 */
const expectNoFlashOnReload = async (page) => {
  await recordBodyInsertion(page);

  for (const { name, stored, system, theme } of PRE_PAINT_CASES) {
    await test.step(name, async () => {
      // Seed the case, then load the page.
      await useTheme(page, { stored, system });
      await navigateToPath(page, "/stats");
      expect(await readBodyInsertion(page)).toEqual({ colorScheme: theme, theme });

      // Reload it.
      await page.reload({ waitUntil: "domcontentloaded" });
      expect(await readBodyInsertion(page)).toEqual({ colorScheme: theme, theme });
    });
  }
};

/**
 * Runs an action and verifies the main frame starts no navigation because of it.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {() => Promise<unknown>} action - Action that must not navigate.
 * @returns {Promise<void>}
 */
const expectNoNavigation = async (page, action) => {
  const navigations = [];
  const recordNavigation = (request) => {
    if (request.isNavigationRequest() && request.frame() === page.mainFrame()) {
      navigations.push(request.url());
    }
  };

  page.on("request", recordNavigation);
  try {
    await action();
    // A server round trip outlasts the start of any reload the action scheduled.
    await page.evaluate(async () => (await fetch("/health-check")).status);
  } finally {
    page.off("request", recordNavigation);
  }
  expect(navigations).toEqual([]);
};

/**
 * Verifies the page still shows the document `markDocument` marked, so nothing reloaded it.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>}
 */
const expectSameDocument = async (page) => {
  expect(await page.evaluate(() => window.ocgThemeSpecDocument)).toBe(true);
};

/**
 * Verifies the resolved color theme on `<html>`: `data-theme` and the inline `color-scheme`.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {"light"|"dark"} theme - Expected color theme.
 * @returns {Promise<void>}
 */
const expectTheme = async (page, theme) => {
  await expect.poll(() => readTheme(page)).toEqual({ colorScheme: theme, theme });
};

/**
 * Follows the boosted Stats link: the Main navigation link on desktop, the account sheet row on
 * phones, where the sheet is already open.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {boolean} isMobile - Whether the page runs on the phone project.
 * @returns {Promise<void>}
 */
const followStatsLink = async (page, isMobile) => {
  if (isMobile) {
    await getAccountSheet(page).userMenu.getByRole("menuitem", { name: "Stats" }).click();
  } else {
    await closeAccountMenu(page);
    await page
      .getByRole("navigation", { name: "Main navigation" })
      .getByRole("link", { name: "Stats" })
      .click();
  }
  await expect(page).toHaveURL(/\/stats$/u);
  await waitForHtmxSettle(page);
};

/**
 * Finds the page shell, the outermost wrapper that paints the canvas behind the header and
 * content.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {import("@playwright/test").Locator} Page shell.
 */
const getShell = (page) => page.locator("body > div:has(#header)");

/**
 * Finds a site header logo wrapper by variant.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {"dark"|"light"|"plated"} variant - Logo variant, the `data-site-logo` value.
 * @returns {import("@playwright/test").Locator} Logo wrapper.
 */
const getSiteLogo = (page, variant) => page.locator(`#header [data-site-logo="${variant}"]`);

/**
 * Finds the sponsor badge plate of the seeded Tech Corp sponsor.
 * @param {import("@playwright/test").Page} page - Group or event page.
 * @returns {import("@playwright/test").Locator} Sponsor badge plate.
 */
const getSponsorPlate = (page) =>
  page.locator(".plate-ring").filter({ has: page.getByRole("img", { exact: true, name: "Tech Corp logo" }) });

/**
 * Finds the theme choices of the account menu.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {{ dark: import("@playwright/test").Locator, light: import("@playwright/test").Locator,
 *   system: import("@playwright/test").Locator }} Choices by preference.
 */
const getThemeChoices = (page) => {
  const group = getAccountSheet(page).userMenu.getByRole("group", { name: "Theme" });
  return {
    dark: group.getByRole("menuitemradio", { exact: true, name: "Dark" }),
    light: group.getByRole("menuitemradio", { exact: true, name: "Light" }),
    system: group.getByRole("menuitemradio", { exact: true, name: "System" }),
  };
};

/**
 * Finds the site header logo wrappers the current theme shows.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {import("@playwright/test").Locator} Visible logo wrappers.
 */
const getVisibleSiteLogos = (page) => page.locator("#header [data-site-logo]").filter({ visible: true });

/**
 * Replaces the content of the site header logo container, the first child of the homepage logo
 * link, with injected logo markup, as when the site row has logo URLs. The seed has none, and
 * tests never mutate the shared site row.
 * @param {import("@playwright/test").Page} page - Page under test, below `/`.
 * @param {string[]} logos - Wrapper markup from `buildSiteLogo`.
 * @returns {Promise<void>}
 */
const injectSiteLogos = (page, logos) =>
  page
    .locator("#header")
    .getByRole("link", { exact: true, name: "Go to homepage" })
    .evaluate((link, markup) => {
      link.firstElementChild.innerHTML = markup;
    }, logos.join(""));

/**
 * Marks the current document, so `expectSameDocument` can tell it was not reloaded.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>}
 */
const markDocument = (page) =>
  page.evaluate(() => {
    window.ocgThemeSpecDocument = true;
  });

/**
 * Opens the account menu, the account sheet on phones. Waits for the real trigger, so a lazily
 * loaded menu has arrived first.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>}
 */
const openAccountMenu = async (page) => {
  const { userButton, userMenu } = getAccountSheet(page);
  await userButton.click();
  await expect(userMenu).toBeVisible();
};

/**
 * Picks a color theme from the account menu, waits for it to apply and closes the menu.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {"dark"|"light"} theme - Explicit choice to pick.
 * @returns {Promise<void>}
 */
const pickTheme = async (page, theme) => {
  await openAccountMenu(page);
  await getThemeChoices(page)[theme].click();
  await expectTheme(page, theme);
  await closeAccountMenu(page);
};

/**
 * Reads what `recordBodyInsertion` captured on the current document.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<{ colorScheme: string, theme: string|null }|undefined>} Captured state.
 */
const readBodyInsertion = (page) => page.evaluate(() => window.ocgBodyInsertion);

/**
 * Reads the canvas state while the stylesheet is held.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<{ background: string, bodyParsed: boolean, colorScheme: string }>} Canvas state.
 */
const readCanvas = (page) =>
  page.evaluate(() => {
    const style = getComputedStyle(document.documentElement);
    return {
      background: style.backgroundColor,
      bodyParsed: document.body !== null,
      colorScheme: style.colorScheme,
    };
  });

/**
 * Resolves a CSS color value on a probe outside every plate, as the browser computes it.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {string} value - Color value, such as `var(--color-plate-edge)`.
 * @returns {Promise<string>} Computed color.
 */
const readColor = (page, value) =>
  page.evaluate((cssValue) => {
    const probe = document.createElement("span");
    probe.style.color = cssValue;
    document.body.append(probe);
    const color = getComputedStyle(probe).color;
    probe.remove();
    return color;
  }, value);

/**
 * Reads the dark `plate-edge` color, after verifying it differs from its light value, so a
 * missing dark override cannot pass for it.
 * @param {import("@playwright/test").Page} page - Page in dark.
 * @returns {Promise<string>} Computed dark plate edge.
 */
const readDarkPlateEdge = async (page) => {
  const darkEdge = await readColor(page, "var(--color-plate-edge)");
  expect(darkEdge).not.toBe(await readColor(page, "var(--ocg-light-stone-300)"));
  return darkEdge;
};

/**
 * Loads the group page, waits for the broken-image icon in its logo plate, and reads the root
 * background and the colors of the light islands: the icon inside the logo plate and the
 * footer, an ink island, with its stone-shaded copy.
 * @param {import("@playwright/test").Page} page - Page whose group logo request fails.
 * @returns {Promise<{ islands: object, root: string }>} Island colors and root background.
 */
const readIslandColors = async (page) => {
  await loadPublicPage(page, GROUP_PAGE);
  const icon = page.locator("[data-group-logo] [data-ocg-broken-image-icon] .icon-broken-image");
  await expect(icon).toBeVisible();
  const footer = page.getByRole("contentinfo", { name: "Site footer" });
  const readColors = (locator) =>
    locator.evaluate((element) => {
      const style = getComputedStyle(element);
      return { background: style.backgroundColor, color: style.color };
    });

  return {
    islands: {
      copy: await readColors(footer.locator("p", { hasText: "Powered by" })),
      footer: await readColors(footer),
      icon: await icon.evaluate((element) => getComputedStyle(element).backgroundColor),
    },
    root: await page.locator("html").evaluate((element) => getComputedStyle(element).backgroundColor),
  };
};

/**
 * Reads the colors print must keep light: the root color scheme, the shell background and the
 * body text.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<{ bodyColor: string, colorScheme: string, shellBackground: string }>} Colors.
 */
const readPrintColors = async (page) => ({
  bodyColor: await page.locator("body").evaluate((element) => getComputedStyle(element).color),
  colorScheme: await page.locator("html").evaluate((element) => getComputedStyle(element).colorScheme),
  shellBackground: await getShell(page).evaluate((element) => getComputedStyle(element).backgroundColor),
});

/**
 * Reads the stored color theme choice.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<string|null>} Stored value, or null when the key is absent.
 */
const readStoredTheme = (page) => page.evaluate((key) => window.localStorage.getItem(key), THEME_STORAGE_KEY);

/**
 * Reads one computed style property of an element.
 * @param {import("@playwright/test").Locator} locator - Element.
 * @param {string} property - CSS property name.
 * @returns {Promise<string>} Computed value.
 */
const readStyle = (locator, property) =>
  locator.evaluate((element, name) => getComputedStyle(element).getPropertyValue(name), property);

/**
 * Reads the resolved color theme from `<html>`.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<{ colorScheme: string, theme: string|undefined }>} Inline color scheme and
 *   `data-theme`.
 */
const readTheme = (page) =>
  page.evaluate(() => ({
    colorScheme: document.documentElement.style.colorScheme,
    theme: document.documentElement.dataset.theme,
  }));

/**
 * Reads the `ocg:themechange` details `recordThemeChanges` collected.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<object[]>} Event details in dispatch order.
 */
const readThemeChanges = (page) => page.evaluate(() => window.ocgThemeChanges);

/**
 * Records `data-theme` and the computed `color-scheme` of `<html>` when the parser inserts
 * `<body>`, on every document of the page.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>}
 */
const recordBodyInsertion = (page) =>
  page.addInitScript(() => {
    // `documentElement` may not exist yet, so the whole document is observed.
    const observer = new MutationObserver(() => {
      if (!document.body) {
        return;
      }
      const root = document.documentElement;
      window.ocgBodyInsertion = {
        colorScheme: getComputedStyle(root).colorScheme,
        theme: root.getAttribute("data-theme"),
      };
      observer.disconnect();
    });
    observer.observe(document, { childList: true, subtree: true });
  });

/**
 * Collects the detail of every `ocg:themechange` event, on every document of the page.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>}
 */
const recordThemeChanges = (page) =>
  page.addInitScript(() => {
    window.ocgThemeChanges = [];
    document.addEventListener("ocg:themechange", (event) => window.ocgThemeChanges.push(event.detail));
  });

/**
 * Serves a site header logo URL with a fixture image, or a 404 response when broken, and counts
 * its requests.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {string} url - Logo URL path.
 * @param {{ broken?: boolean }} [options] - Whether the URL fails.
 * @returns {Promise<() => number>} Reads the number of requests so far.
 */
const routeSiteLogo = async (page, url, { broken = false } = {}) => {
  let requests = 0;
  await page.route(`**${url}`, (route) => {
    requests += 1;
    return broken ? route.fulfill({ status: 404 }) : route.fulfill({ path: SITE_LOGO_FILE });
  });
  return () => requests;
};
