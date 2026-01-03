import type { Page } from "@playwright/test";

export const TEST_COMMUNITY_HOST =
  process.env.OCG_E2E_HOST || "test-community.localhost";
export const TEST_GROUP_SLUG = process.env.OCG_E2E_GROUP_SLUG || "test-group";
export const TEST_EVENT_SLUG = process.env.OCG_E2E_EVENT_SLUG || "test-event";
export const TEST_GROUP_NAME = "E2E Test Group";
export const TEST_EVENT_NAME = "E2E Test Event";
export const TEST_SEARCH_QUERY = "Test";
export const TEST_COMMUNITY_TITLE = "E2E Test Community";
const BASE_URL = process.env.OCG_E2E_BASE_URL || "http://localhost:9000";
const SHOULD_USE_HOST_HEADER = process.env.OCG_E2E_USE_HOST_HEADER === "true";

const buildBaseUrl = () => {
  const url = new URL(BASE_URL);
  if (["localhost", "127.0.0.1"].includes(url.hostname)) {
    url.hostname = TEST_COMMUNITY_HOST;
  }
  return url.toString().replace(/\/$/, "");
};

const EFFECTIVE_BASE_URL = buildBaseUrl();

const buildUrl = (path: string) => new URL(path, EFFECTIVE_BASE_URL).toString();

/**
 * Sets the Host header to route requests to a specific community.
 */
export const setHostHeader = async (page: Page, host: string) => {
  if (!SHOULD_USE_HOST_HEADER) {
    return;
  }
  await page.setExtraHTTPHeaders({ Host: host });
};

/**
 * Navigates to the community home page.
 */
export const navigateToHome = async (page: Page) => {
  await page.goto(buildUrl("/"));
};

/**
 * Navigates to the explore page.
 */
export const navigateToExplore = async (page: Page) => {
  await page.goto(buildUrl("/explore"));
};

/**
 * Navigates to a specific group page.
 */
export const navigateToGroup = async (page: Page, groupSlug: string) => {
  await page.goto(buildUrl(`/group/${groupSlug}`));
};

/**
 * Navigates to a specific event page.
 */
export const navigateToEvent = async (
  page: Page,
  groupSlug: string,
  eventSlug: string
) => {
  await page.goto(buildUrl(`/group/${groupSlug}/event/${eventSlug}`));
};

/**
 * Navigates to a specific path using the effective base URL.
 */
export const navigateToPath = async (page: Page, path: string) => {
  await page.goto(buildUrl(path));
};
