import { randomUUID } from "node:crypto";
import { expect } from "@playwright/test";
import type { Page } from "@playwright/test";

export const TEST_COMMUNITY_NAME =
  process.env.OCG_E2E_COMMUNITY_NAME || "e2e-test-community";
export const TEST_COMMUNITY_NAME_2 = "e2e-second-community";
export const TEST_COMMUNITY_IDS = {
  community1: "11111111-1111-1111-1111-111111111111",
  community2: "11111111-1111-1111-1111-111111111112",
} as const;
export const TEST_GROUP_SLUG =
  process.env.OCG_E2E_GROUP_SLUG || "test-group-alpha";
export const TEST_EVENT_SLUG =
  process.env.OCG_E2E_EVENT_SLUG || "alpha-event-1";
export const TEST_GROUP_NAME = "E2E Test Group Alpha";
export const TEST_EVENT_NAME = "Alpha Event One";
export const TEST_SEARCH_QUERY = "Test";
export const TEST_SITE_TITLE = "E2E Test Site";
export const TEST_COMMUNITY_TITLE = "E2E Test Community";
export const TEST_COMMUNITY_TITLE_2 = "E2E Second Community";

/** Community details for assertions. */
export const TEST_COMMUNITY_DESCRIPTION = "E2E test community description";
export const TEST_COMMUNITY_BANNER_URL = "https://example.com/banner.png";
export const TEST_COMMUNITY_BANNER_MOBILE_URL =
  "https://example.com/banner-mobile.png";

/** Group names organized by community. */
export const TEST_GROUP_NAMES = {
  alpha: "E2E Test Group Alpha",
  beta: "E2E Test Group Beta",
  gamma: "E2E Test Group Gamma",
} as const;

/** Event names organized by group. */
export const TEST_EVENT_NAMES = {
  alpha: ["Alpha Event One", "Alpha Event Two", "Alpha Event Three"],
  beta: ["Beta Event One", "Beta Event Two", "Beta Event Three"],
  gamma: ["Gamma Event One", "Gamma Event Two", "Gamma Event Three"],
} as const;

/** Group slugs organized by community. */
export const TEST_GROUP_SLUGS = {
  community1: {
    alpha: "test-group-alpha",
    beta: "test-group-beta",
    gamma: "test-group-gamma",
  },
  community2: {
    delta: "second-group-delta",
    epsilon: "second-group-epsilon",
    zeta: "second-group-zeta",
  },
} as const;

/** Group ids organized by community. */
export const TEST_GROUP_IDS = {
  community1: {
    alpha: "44444444-4444-4444-4444-444444444441",
    beta: "44444444-4444-4444-4444-444444444442",
    gamma: "44444444-4444-4444-4444-444444444443",
  },
  community2: {
    delta: "44444444-4444-4444-4444-444444444444",
    epsilon: "44444444-4444-4444-4444-444444444445",
    zeta: "44444444-4444-4444-4444-444444444446",
  },
} as const;

/** Event slugs organized by group. */
export const TEST_EVENT_SLUGS = {
  alpha: ["alpha-event-1", "alpha-event-2", "alpha-event-3"],
  beta: ["beta-event-1", "beta-event-2", "beta-event-3"],
  gamma: ["gamma-event-1", "gamma-event-2", "gamma-event-3"],
  delta: ["delta-event-1", "delta-event-2", "delta-event-3"],
  epsilon: ["epsilon-event-1", "epsilon-event-2", "epsilon-event-3"],
  zeta: ["zeta-event-1", "zeta-event-2", "zeta-event-3"],
  alphaDashboard: ["alpha-cfs-summit", "alpha-past-roundup"],
} as const;

/** Pre-seeded user credentials for e2e tests. */
export const TEST_USER_CREDENTIALS = {
  admin1: { username: "e2e-admin-1", password: "Password123!" },
  admin2: { username: "e2e-admin-2", password: "Password123!" },
  organizer1: { username: "e2e-organizer-1", password: "Password123!" },
  organizer2: { username: "e2e-organizer-2", password: "Password123!" },
  member1: { username: "e2e-member-1", password: "Password123!" },
  member2: { username: "e2e-member-2", password: "Password123!" },
  pending1: { username: "e2e-pending-1", password: "Password123!" },
  pending2: { username: "e2e-pending-2", password: "Password123!" },
  groupsManager1: {
    username: "e2e-groups-manager-1",
    password: "Password123!",
  },
  communityViewer1: {
    username: "e2e-community-viewer-1",
    password: "Password123!",
  },
  eventsManager1: {
    username: "e2e-events-manager-1",
    password: "Password123!",
  },
  groupViewer1: {
    username: "e2e-group-viewer-1",
    password: "Password123!",
  },
} as const;
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
  communityName: string,
) => {
  await page.goto(buildUrl(`/${communityName}`));
};

/**
 * Navigates to a specific group page within a community.
 */
export const navigateToGroup = async (
  page: Page,
  communityName: string,
  groupSlug: string,
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
  eventSlug: string,
) => {
  await page.goto(
    buildUrl(`/${communityName}/group/${groupSlug}/event/${eventSlug}`),
  );
};

/**
 * Navigates to a specific path.
 */
export const navigateToPath = async (page: Page, path: string) => {
  await page.goto(buildUrl(path));
};

/**
 * Logs in with one of the pre-seeded e2e users.
 */
export const logInWithSeededUser = async (
  page: Page,
  credentials: (typeof TEST_USER_CREDENTIALS)[keyof typeof TEST_USER_CREDENTIALS],
) => {
  await navigateToPath(page, "/log-in");

  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  await page.getByLabel("Username").fill(credentials.username);
  await page
    .getByRole("textbox", { name: "Password required" })
    .fill(credentials.password);

  await Promise.all([
    page.waitForURL((url) => !url.pathname.includes("/log-in")),
    page.getByRole("button", { name: "Sign In" }).click(),
  ]);
};

/**
 * Selects a community dashboard context for the logged-in user.
 */
export const selectCommunityContext = async (
  page: Page,
  communityId: string,
) => {
  const response = await page.request.put(
    buildUrl(`/dashboard/community/${communityId}/select`),
  );

  expect(response.ok()).toBeTruthy();
};

/**
 * Selects a group dashboard context for the logged-in user.
 */
export const selectGroupContext = async (
  page: Page,
  communityId: string,
  groupId: string,
) => {
  const communityResponse = await page.request.put(
    buildUrl(`/dashboard/group/community/${communityId}/select`),
  );
  expect(communityResponse.ok()).toBeTruthy();

  const groupResponse = await page.request.put(
    buildUrl(`/dashboard/group/${groupId}/select`),
  );
  expect(groupResponse.ok()).toBeTruthy();
};
