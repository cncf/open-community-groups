import { expect, test } from "../../fixtures.js";

import { TEST_COMMUNITY_NAME, TEST_SITE_TITLE } from "../../seed.js";
import { navigateToPath, navigateToSiteHome } from "../../utils.js";

// Computed styles of the bar while it shows on the top edge of the viewport.
const VISIBLE_BAR = { height: "2px", opacity: "1", position: "fixed", top: "0px" };

test.describe("page loading bar", () => {
  test("shows on the top edge while a boosted link loads @mobile", async ({ page }) => {
    // Hold the community page so the bar outlasts its delay.
    await navigateToSiteHome(page);
    const banner = page.getByRole("main").locator(`a[href="/${TEST_COMMUNITY_NAME}"]`).first();
    const releaseResponse = await holdResponses(page, (url) => url.pathname === `/${TEST_COMMUNITY_NAME}`);
    await page.evaluate(() => {
      window.keptDocument = true;
    });

    // Verify the bar appears once the banner is tapped.
    await banner.tap();
    await expect.poll(() => readLoadingBar(page)).toEqual(VISIBLE_BAR);

    // Verify the page arrives in the same document and the bar clears.
    releaseResponse();
    await expect(page).toHaveURL(new RegExp(`/${TEST_COMMUNITY_NAME}$`, "u"));
    expect(await page.evaluate(() => window.keptDocument)).toBe(true);
    await expect.poll(async () => (await readLoadingBar(page)).opacity).toBe("0");
  });

  test("shows while the header title link loads @mobile", async ({ page }) => {
    // Hold the home page behind the phone title link.
    await navigateToPath(page, "/stats");
    const header = page.locator("#header");
    const titleLink = header.getByRole("link", { name: `Go to ${TEST_SITE_TITLE} homepage` });
    const releaseResponse = await holdResponses(page, (url) => url.pathname === "/");

    // Verify the bar appears once the title is tapped.
    await titleLink.tap();
    await expect.poll(() => readLoadingBar(page)).toEqual(VISIBLE_BAR);

    // Verify it clears once the home page arrives.
    releaseResponse();
    await expect(page).toHaveURL(/\/$/u);
    await expect.poll(async () => (await readLoadingBar(page)).opacity).toBe("0");
  });

  test("shows while a link replaces the document @mobile", async ({ page }) => {
    // Hold the sign-up page behind a link the browser follows itself.
    await navigateToPath(page, "/log-in");
    const signUpLink = page.getByRole("main").getByRole("link", { name: "Sign up" });
    const releaseResponse = await holdResponses(page, (url) => url.pathname === "/sign-up");
    const { barShown } = await watchLoadingBarOnTap(page);

    // Verify the bar appears once the link is tapped, without waiting for the held page.
    await signUpLink.tap({ noWaitAfter: true });
    expect(await barShown).toEqual(VISIBLE_BAR);

    // Verify the new document starts without the bar.
    releaseResponse();
    await expect(page).toHaveURL(/\/sign-up$/u);
    await expect.poll(async () => (await readLoadingBar(page)).opacity).toBe("0");
  });

  test("stands in for the dashboard spinner on phones @mobile", async ({ member1Page }) => {
    // Hold the check-in tab behind the dashboard menu.
    await navigateToPath(member1Page, "/dashboard/user?tab=invitations");
    const releaseResponse = await holdResponses(
      member1Page,
      (url) => url.pathname === "/dashboard/user" && url.searchParams.get("tab") === "check-in",
    );
    await member1Page.getByRole("button", { name: "Open dashboard menu" }).click();
    const checkInLink = member1Page
      .getByRole("navigation", { name: "Dashboard navigation" })
      .getByRole("link", { name: "Check-In" });

    // Verify the bar appears once the menu item is tapped.
    await checkInLink.tap();
    await expect.poll(() => readLoadingBar(member1Page)).toEqual(VISIBLE_BAR);

    // Verify it clears once the tab arrives.
    releaseResponse();
    await expect(member1Page).toHaveURL(/tab=check-in/u);
    await expect.poll(async () => (await readLoadingBar(member1Page)).opacity).toBe("0");
  });

  test("covers touch screens below lg and leaves wider ones to the nav links @mobile", async ({ page }) => {
    // Hold the community page on a touch screen wider than a phone.
    await page.setViewportSize({ width: 900, height: 700 });
    await navigateToSiteHome(page);
    const banner = page.getByRole("main").locator(`a[href="/${TEST_COMMUNITY_NAME}"]`).first();
    const releaseResponse = await holdResponses(page, (url) => url.pathname === `/${TEST_COMMUNITY_NAME}`);

    // Verify the bar appears once the banner is tapped.
    await banner.tap();
    await expect.poll(() => readLoadingBar(page)).toEqual(VISIBLE_BAR);
    releaseResponse();
    await expect(page).toHaveURL(new RegExp(`/${TEST_COMMUNITY_NAME}$`, "u"));

    // Verify no bar is drawn from lg, where the header shows its nav links.
    await page.setViewportSize({ width: 1024, height: 700 });
    await expect.poll(async () => (await readLoadingBar(page)).position).toBe("static");
  });
});

/**
 * Holds the responses of matching requests until the returned function is called.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {(url: URL) => boolean} matchesUrl - Selects the requests to hold.
 * @returns {Promise<() => void>} Releases the held responses.
 */
const holdResponses = async (page, matchesUrl) => {
  let releaseResponses;
  const responsesHeld = new Promise((resolve) => {
    releaseResponses = resolve;
  });
  await page.route(matchesUrl, async (route) => {
    await responsesHeld;
    await route.continue();
  });

  return releaseResponses;
};

/**
 * Reads the page loading bar drawn on the root's ::after.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<{ height: string, opacity: string, position: string, top: string }>} Its
 * computed styles.
 */
const readLoadingBar = (page) =>
  page.evaluate(() => {
    const { height, opacity, position, top } = getComputedStyle(document.documentElement, "::after");
    return { height, opacity, position, top };
  });

/**
 * Watches for the bar to show after the next tap. The page reports it itself, because
 * Playwright cannot evaluate in a document while the one replacing it loads.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<{ barShown: Promise<object> }>} Promise of the bar's computed styles.
 */
const watchLoadingBarOnTap = async (page) => {
  let reportBar;
  const barShown = new Promise((resolve) => {
    reportBar = resolve;
  });
  await page.exposeFunction("reportLoadingBar", reportBar);
  await page.evaluate(() => {
    const reportWhenShown = () => {
      const { height, opacity, position, top } = getComputedStyle(document.documentElement, "::after");
      if (opacity === "1") {
        window.reportLoadingBar({ height, opacity, position, top });
      } else {
        requestAnimationFrame(reportWhenShown);
      }
    };
    window.addEventListener("click", reportWhenShown, { once: true });
  });

  return { barShown };
};
