import { expect } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_SITE_TITLE,
} from "../../seed.js";
import { waitForPageSettled } from "../../snapshots.js";
import { navigateToPath, routeEmptyBasemap } from "../../utils.js";

// Name of the offline basemap's attribution link, rendered in every map preview.
const BASEMAP_ATTRIBUTION_NAME = "OpenStreetMap";
const BASEMAP_ATTRIBUTION = `<a href="https://www.openstreetmap.org/copyright">${BASEMAP_ATTRIBUTION_NAME}</a>`;

// Badge pages replace the header and footer blocks with the badge header
// (`badges/verify.html`, `badges/credential.html`).
const BADGE_LANDMARKS = { mainNavigation: 0, siteFooter: 0 };

// `common/base.html` skips the site footer on the docs, login, sign-up and 404 pages.
const NO_FOOTER_LANDMARKS = { siteFooter: 0 };

// Docsify (vendor markup loaded by `site/docs/page.html`) renders its own `<main>`.
// Known duplicate-main defect, not intended structure; fixing it means changing the
// vendor markup from `static/js/site/docs/shell.js`.
const DOCS_LANDMARKS = { ...NO_FOOTER_LANDMARKS, main: 2 };

/**
 * Seeded public pages shared by the structural accessibility and responsive specs.
 * `landmarks` overrides the expected count (1 by default) of a shared shell landmark.
 * @type {{
 *   landmarks?: { main?: number, mainNavigation?: number, siteFooter?: number },
 *   name: string,
 *   path: string,
 *   ready: (page: import("@playwright/test").Page) => import("@playwright/test").Locator,
 * }[]}
 */
export const PUBLIC_PAGES = [
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
    landmarks: DOCS_LANDMARKS,
    name: "documentation",
    path: "/docs",
    // Docsify fetches and renders the guide outside htmx, so wait for its first heading.
    ready: (page) => page.locator(".markdown-section h1").first(),
  },
  {
    landmarks: BADGE_LANDMARKS,
    name: "badge verification",
    path: "/badges/verify",
    ready: (page) => page.getByRole("heading", { name: "Verify an OCG badge" }),
  },
  {
    landmarks: BADGE_LANDMARKS,
    name: "badge credential",
    path: "/badges/credentials/dadadada-dada-dada-dada-dadadadada02",
    ready: (page) => page.getByRole("heading", { name: "Host" }),
  },
  {
    landmarks: NO_FOOTER_LANDMARKS,
    name: "login",
    path: "/log-in",
    ready: (page) => page.getByRole("heading", { name: "Log In" }),
  },
  {
    landmarks: NO_FOOTER_LANDMARKS,
    name: "sign-up",
    path: "/sign-up",
    ready: (page) => page.getByRole("heading", { name: "Sign Up" }),
  },
  {
    landmarks: NO_FOOTER_LANDMARKS,
    name: "not found",
    path: "/missing-public-page",
    ready: (page) => page.getByRole("heading", { name: "We could not find that page" }),
  },
];

/**
 * Loads a seeded public page and waits until it is final: ready, settled (htmx swaps and
 * attendance controls) and, where a map preview renders, showing its basemap attribution.
 * Serves an offline basemap first, so map previews never reach the tile server.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {(typeof PUBLIC_PAGES)[number]} publicPage - Page to load.
 * @returns {Promise<void>}
 */
export const loadPublicPage = async (page, publicPage) => {
  await routeEmptyBasemap(page, { attribution: BASEMAP_ATTRIBUTION });
  await navigateToPath(page, publicPage.path);
  await expect(publicPage.ready(page)).toBeVisible({ timeout: 15_000 });
  await waitForPageSettled(page);

  // Only rows with a mapped location render map previews; wait for their attribution links.
  for (const mapPreview of await page.locator("[data-map-modal]").all()) {
    await expect(mapPreview.getByRole("link", { name: BASEMAP_ATTRIBUTION_NAME })).toBeVisible();
  }
};
