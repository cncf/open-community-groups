import { test } from "../../fixtures.js";

import { expectNoAxeViolations } from "../../axe.js";
import { loadPublicPage, PUBLIC_PAGES } from "./public-pages.js";

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
