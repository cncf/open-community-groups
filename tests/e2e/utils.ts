import type { Page } from "@playwright/test";

export const TEST_COMMUNITY_HOST =
  process.env.OCG_E2E_HOST || "test-community.localhost";
export const TEST_GROUP_SLUG = process.env.OCG_E2E_GROUP_SLUG || "test-group";
export const TEST_EVENT_SLUG = process.env.OCG_E2E_EVENT_SLUG || "test-event";
export const TEST_GROUP_NAME = "E2E Test Group";
export const TEST_EVENT_NAME = "E2E Test Event";
export const TEST_SEARCH_QUERY = "E2E";
export const TEST_COMMUNITY_TITLE = "E2E Test Community";

/**
 * Sets the Host header to route requests to a specific community.
 */
export const setHostHeader = async (page: Page, host: string) => {
  await page.setExtraHTTPHeaders({ Host: host });
};

/**
 * Navigates to the community home page.
 */
export const navigateToHome = async (page: Page) => {
  await page.goto("/");
};

/**
 * Navigates to the explore page.
 */
export const navigateToExplore = async (page: Page) => {
  await page.goto("/explore");
};

/**
 * Navigates to a specific group page.
 */
export const navigateToGroup = async (page: Page, groupSlug: string) => {
  await page.goto(`/group/${groupSlug}`);
};

/**
 * Navigates to a specific event page.
 */
export const navigateToEvent = async (
  page: Page,
  groupSlug: string,
  eventSlug: string
) => {
  await page.goto(`/group/${groupSlug}/event/${eventSlug}`);
};
