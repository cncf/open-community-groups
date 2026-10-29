import { expect, test } from "../../fixtures.js";

import { navigateToPath } from "../../utils.js";
import { PUBLIC_PAGES } from "./public-pages.js";

const BREAKPOINTS = [
  { name: "mobile", width: 390 },
  { name: "sm", width: 640 },
  { name: "md", width: 768 },
  { name: "lg", width: 1024 },
  { name: "xl", width: 1280 },
  { name: "2xl", width: 1536 },
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
