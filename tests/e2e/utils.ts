import { randomUUID } from "node:crypto";
import type { Page } from "@playwright/test";

export const TEST_COMMUNITY_NAME =
  process.env.OCG_E2E_COMMUNITY_NAME || "e2e-test-community";
export const TEST_GROUP_SLUG = process.env.OCG_E2E_GROUP_SLUG || "test-group";
export const TEST_EVENT_SLUG = process.env.OCG_E2E_EVENT_SLUG || "test-event";
export const TEST_GROUP_NAME = "E2E Test Group";
export const TEST_EVENT_NAME = "E2E Test Event";
export const TEST_SEARCH_QUERY = "Test";
export const TEST_SITE_TITLE = "E2E Test Site";
export const TEST_COMMUNITY_TITLE = "E2E Test Community";
const BASE_URL = process.env.OCG_E2E_BASE_URL || "http://localhost:9000";

const buildUrl = (path: string) => new URL(path, BASE_URL).toString();

/**
 * Builds a fully-qualified URL.
 */
export const buildE2eUrl = (path: string) => buildUrl(path);

export type AuthUser = {
  name: string;
  email: string;
  username: string;
  password: string;
};

/**
 * Builds unique credentials for sign-up and login flows.
 */
export const buildAuthUser = (): AuthUser => {
  const suffix = randomUUID().replace(/-/g, "").slice(0, 8);
  const username = `e2e${suffix}`;

  return {
    name: `E2E User ${suffix}`,
    email: `${username}@example.com`,
    username,
    password: "Password123!",
  };
};

/**
 * Navigates to the site home page.
 */
export const navigateToSiteHome = async (page: Page) => {
  await page.goto(buildUrl("/"));
};

/**
 * Navigates to the site explore page.
 */
export const navigateToSiteExplore = async (page: Page) => {
  await page.goto(buildUrl("/explore"));
};

/**
 * Navigates to a community home page.
 */
export const navigateToCommunityHome = async (
  page: Page,
  communityName: string
) => {
  await page.goto(buildUrl(`/${communityName}`));
};

/**
 * Navigates to a specific group page within a community.
 */
export const navigateToGroup = async (
  page: Page,
  communityName: string,
  groupSlug: string
) => {
  await page.goto(buildUrl(`/${communityName}/group/${groupSlug}`));
};

/**
 * Navigates to a specific event page within a community.
 */
export const navigateToEvent = async (
  page: Page,
  communityName: string,
  groupSlug: string,
  eventSlug: string
) => {
  await page.goto(
    buildUrl(`/${communityName}/group/${groupSlug}/event/${eventSlug}`)
  );
};

/**
 * Navigates to a specific path.
 */
export const navigateToPath = async (page: Page, path: string) => {
  await page.goto(buildUrl(path));
};
