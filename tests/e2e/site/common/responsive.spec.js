import { expect, test } from "../../fixtures.js";

import { waitForPageSettled } from "../../snapshots.js";
import { getPageOverflow, navigateToPath } from "../../utils.js";
import { PUBLIC_PAGES } from "./public-pages.js";

const BREAKPOINTS = [
  { name: "mobile", width: 390 },
  { name: "sm", width: 640 },
  { name: "md", width: 768 },
  { name: "lg", width: 1024 },
  { name: "xl", width: 1280 },
  { name: "2xl", width: 1536 },
];
// Narrow, common and large phones, at their own heights.
const PHONE_SIZES = [
  { height: 568, width: 320 },
  { height: 640, width: 360 },
  { height: 874, width: 402 },
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

  for (const responsivePage of PUBLIC_PAGES) {
    test(`${responsivePage.name} fits every supported breakpoint`, async ({ page }) => {
      await expectResponsiveLayout(page, responsivePage);
    });
  }
});

test.describe("phone sizes", () => {
  for (const publicPage of PUBLIC_PAGES) {
    for (const size of PHONE_SIZES) {
      test(`${publicPage.name} fits ${size.width}px @mobile`, async ({ page }) => {
        // Load the seeded public page at the phone's own size.
        await page.setViewportSize(size);
        await navigateToPath(page, publicPage.path);
        await waitForPublicPage(page, publicPage);

        // Verify the page holds its width.
        await expect.poll(() => getPageOverflow(page)).toBeLessThanOrEqual(0);
        await expect(page.locator("#main-content")).toBeVisible();

        // Verify nothing is cut at the edge by a clipping ancestor.
        expect(await page.evaluate(listElementsPastViewport)).toEqual([]);

        // Verify the header, a pinned heading and the bar leave most of the screen.
        const contentHeight = await page.evaluate(measureContentHeight);
        expect(contentHeight).toBeGreaterThanOrEqual(size.height / 2);
      });
    }
  }
});

test.describe("phone sm flip", () => {
  for (const publicPage of PUBLIC_PAGES) {
    test(`${publicPage.name} keeps its elements across the sm flip @mobile`, async ({ page }) => {
      // Load the seeded public page just below sm.
      await page.setViewportSize({ height: 360, width: 639 });
      await navigateToPath(page, publicPage.path);
      await waitForPublicPage(page, publicPage);
      const belowSm = await waitForStableElements(page);

      // Verify the first sm width holds its width.
      await page.setViewportSize({ height: 360, width: 640 });
      await expect.poll(() => getPageOverflow(page)).toBeLessThanOrEqual(0);

      // Verify sm's flips show and hide nothing on phones.
      expect(await waitForStableElements(page)).toEqual(belowSm);
    });
  }
});

/**
 * Lists rendered text that ends past the viewport outside a scroller, runs in the page.
 * Screen reader only text is clipped to a pixel on purpose, so it is left out.
 * @returns {string[]} Element signatures.
 */
const listElementsPastViewport = () => {
  const viewportWidth = document.documentElement.clientWidth;
  const isScrolled = (element) => {
    for (let node = element.parentElement; node; node = node.parentElement) {
      if (["auto", "scroll"].includes(getComputedStyle(node).overflowX)) {
        return true;
      }
    }
    return false;
  };

  return [...document.querySelectorAll("#main-content *")]
    .filter((element) => {
      const hasText = [...element.childNodes].some(
        (node) => node.nodeType === Node.TEXT_NODE && node.textContent.trim(),
      );
      const { right, width } = element.getBoundingClientRect();
      return (
        hasText &&
        width > 0 &&
        right > viewportWidth + 1 &&
        !element.closest(".sr-only") &&
        !isScrolled(element)
      );
    })
    .map((element) => `${element.tagName.toLowerCase()}.${[...element.classList].join(".")}`);
};

/**
 * Measures the screen left once the header, the tallest strip and the bar are pinned, runs in the page.
 * @returns {number} Height in pixels.
 */
const measureContentHeight = () => {
  const getHeights = (selector) =>
    [...document.querySelectorAll(selector)].map((element) => element.getBoundingClientRect().height);

  return (
    window.innerHeight -
    Math.max(0, ...getHeights("header[role=banner]")) -
    Math.max(0, ...getHeights(".section-strip")) -
    Math.max(0, ...getHeights(".cta-bar"))
  );
};

/**
 * Lists the rendered elements, leaving out drawn content, runs in the page.
 * @returns {string[]} Sorted element signatures.
 */
const listVisibleElements = () =>
  [...document.body.querySelectorAll("*")]
    .filter(
      (element) =>
        element.getClientRects().length > 0 &&
        !element.closest("canvas, svg, .maplibregl-map, [_echarts_instance_]"),
    )
    .map((element) => `${element.tagName.toLowerCase()}#${element.id}.${element.classList.value}`)
    .sort();

/**
 * Waits for a public page to finish hydrating. Docsify fetches its guide outside htmx, so the
 * documentation page also waits for the rendered guide.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {(typeof PUBLIC_PAGES)[number]} publicPage - Page being loaded.
 * @returns {Promise<void>}
 */
const waitForPublicPage = async (page, publicPage) => {
  await expect(publicPage.ready(page)).toBeVisible({ timeout: 15_000 });
  await waitForPageSettled(page);
  if (publicPage.name === "documentation") {
    await expect(page.locator(".markdown-section h1").first()).toBeVisible({ timeout: 15_000 });
  }
};

/**
 * Waits until two reads of the rendered elements match.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<string[]>} Settled element signatures.
 */
const waitForStableElements = async (page) => {
  let elements = [];
  await expect
    .poll(async () => {
      const previous = elements;
      elements = await page.evaluate(listVisibleElements);

      return elements.join() === previous.join();
    })
    .toBe(true);

  return elements;
};
