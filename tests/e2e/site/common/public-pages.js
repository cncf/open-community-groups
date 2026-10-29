import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_SITE_TITLE,
} from "../../seed.js";

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
    ready: (page) => page.locator(".ocg-docs-root .content"),
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
