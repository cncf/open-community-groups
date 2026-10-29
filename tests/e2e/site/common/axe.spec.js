import { expect, test } from "../../fixtures.js";

import { expectNoAxeViolations } from "../../axe.js";
import { navigateToPath, routeEmptyBasemap, waitForHtmxSettle } from "../../utils.js";
import { PUBLIC_PAGES } from "./public-pages.js";

const BASEMAP_ATTRIBUTION_NAME = "OpenStreetMap";

test.describe("public pages axe scan", () => {
  for (const publicPage of PUBLIC_PAGES) {
    test(`${publicPage.name} has no critical or serious axe violations`, async ({ page }) => {
      // Serve an offline basemap whose attribution link renders in every map preview.
      await routeEmptyBasemap(page, {
        attribution: `<a href="https://www.openstreetmap.org/copyright">${BASEMAP_ATTRIBUTION_NAME}</a>`,
      });

      // Load a seeded public page and let HTMX finish any swaps before scanning.
      await navigateToPath(page, publicPage.path);
      await expect(publicPage.ready(page)).toBeVisible({ timeout: 15_000 });
      await waitForHtmxSettle(page);

      // Wait for the map previews' attribution links, so the scan covers them.
      for (const mapPreview of await page.locator("[data-map-modal]").all()) {
        await expect(mapPreview.getByRole("link", { name: BASEMAP_ATTRIBUTION_NAME })).toBeVisible();
      }

      // Verify the rendered page against the critical/serious baseline.
      await expectNoAxeViolations(page, { scan: publicPage.name });
    });
  }
});
