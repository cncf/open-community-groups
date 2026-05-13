import { randomUUID } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { expect } from "@playwright/test";
import type { Locator, Page, TestInfo } from "@playwright/test";

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
export const TEST_GROUP_NAME = "Platform Ops Meetup";
export const TEST_EVENT_NAME = "Upcoming In-Person Event";
export const TEST_SEARCH_QUERY = "Test";
export const TEST_SITE_TITLE = "E2E Test Site";
export const TEST_COMMUNITY_TITLE = "Platform Engineering Community";
export const TEST_COMMUNITY_TITLE_2 = "Developer Experience Community";

/** Community details for assertions. */
export const TEST_COMMUNITY_DESCRIPTION =
  "Platform engineering community used for end-to-end coverage.";
export const TEST_COMMUNITY_BANNER_URL =
  "/static/images/e2e/community-primary-banner.svg";
export const TEST_COMMUNITY_BANNER_MOBILE_URL =
  "/static/images/e2e/community-primary-banner-mobile.svg";

/** Group names organized by community. */
export const TEST_GROUP_NAMES = {
  alpha: "Platform Ops Meetup",
  beta: "Inactive Local Chapter",
  gamma: "Observability Guild",
} as const;

/** Event names organized by group. */
export const TEST_EVENT_NAMES = {
  alpha: [
    "Upcoming In-Person Event",
    "Upcoming Virtual Event",
    "Upcoming Hybrid Event",
  ],
  beta: [
    "Canceled In-Person Event",
    "Secondary Virtual Event",
    "Secondary Hybrid Event",
  ],
  gamma: [
    "Observability In-Person Event",
    "Observability Virtual Event",
    "Observability Hybrid Event",
  ],
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

/** Event ids organized by seeded coverage area. */
export const TEST_EVENT_IDS = {
  alpha: {
    one: "55555555-5555-5555-5555-555555555501",
    two: "55555555-5555-5555-5555-555555555502",
    cfsSummit: "55555555-5555-5555-5555-555555555519",
    waitlistLab: "55555555-5555-5555-5555-555555555521",
  },
} as const;

/** Payment-specific event ids used by the future Playwright payment suite. */
export const TEST_PAYMENT_EVENT_IDS = {
  draft: "55555555-5555-5555-5555-555555555522",
  refunds: "55555555-5555-5555-5555-555555555523",
} as const;

/** Payment-specific event names used by the future Playwright payment suite. */
export const TEST_PAYMENT_EVENT_NAMES = {
  draft: "Ticketed Draft Event",
  refunds: "Ticketed Refund Review Event",
} as const;

/** Payment-specific event slugs used by the future Playwright payment suite. */
export const TEST_PAYMENT_EVENT_SLUGS = {
  draft: "alpha-payments-draft",
  refunds: "alpha-payments-refunds",
} as const;

/** Seeded Stripe recipient stored on the alpha group for payment-ready coverage. */
export const TEST_PAYMENT_GROUP_RECIPIENT = "acct_e2e_alpha";
export const E2E_PAYMENTS_ENABLED =
  (process.env.OCG_E2E_PAYMENTS_ENABLED || "").trim().toLowerCase() === "true";
export const E2E_MEETINGS_ENABLED =
  (process.env.OCG_E2E_MEETINGS_ENABLED || "").trim().toLowerCase() === "true";

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

/** Pre-seeded user ids for state resets and dashboard assertions. */
export const TEST_USER_IDS = {
  communityGroupsManager1: "77777777-7777-7777-7777-777777777709",
  member2: "77777777-7777-7777-7777-777777777706",
  pending1: "77777777-7777-7777-7777-777777777707",
  pending2: "77777777-7777-7777-7777-777777777708",
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
const BASE_URL = process.env.OCG_E2E_BASE_URL || "http://127.0.0.1:9001";

const buildUrl = (path: string) => new URL(path, BASE_URL).toString();

/** Waits for the page to finish the visual work needed before snapshotting. */
const waitForVisualReady = async (page: Page) => {
  await page.waitForLoadState("networkidle");
  await page.evaluate(async () => {
    await document.fonts.ready;
    await new Promise<void>((resolve) => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => resolve());
      });
    });
  });
};

/**
 * Waits for image elements inside the snapshot target to settle.
 */
const waitForVisualImages = async (region: Locator) => {
  await region.locator("img").evaluateAll(async (elements) => {
    await Promise.all(
      elements.map(async (element) => {
        const imageElement = element as HTMLImageElement;
        const settlePromise =
          typeof imageElement.decode === "function"
            ? imageElement.decode().catch(() => undefined)
            : imageElement.complete
              ? Promise.resolve()
              : new Promise<void>((resolve) => {
                  imageElement.addEventListener("load", () => resolve(), { once: true });
                  imageElement.addEventListener("error", () => resolve(), { once: true });
                });

        await Promise.race([
          settlePromise,
          new Promise<void>((resolve) => {
            window.setTimeout(resolve, 1500);
          }),
        ]);
      }),
    );
  });
};

/**
 * Reads the dimensions from a PNG snapshot header.
 */
const getPngDimensions = (filePath: string) => {
  if (!existsSync(filePath)) {
    return null;
  }

  const imageBuffer = readFileSync(filePath);

  if (imageBuffer.length < 24 || imageBuffer.toString("ascii", 1, 4) !== "PNG") {
    return null;
  }

  return {
    width: imageBuffer.readUInt32BE(16),
    height: imageBuffer.readUInt32BE(20),
  };
};

/**
 * Checks whether a region is close enough to a snapshot for clipped capture.
 */
const hasTinySnapshotDimensionDrift = (
  regionBox: { width: number; height: number },
  snapshotDimensions: { width: number; height: number },
) =>
  Math.abs(snapshotDimensions.width - Math.round(regionBox.width)) <= 2 &&
  Math.abs(snapshotDimensions.height - Math.round(regionBox.height)) <= 2;

const getClippedScreenshotBox = async (
  page: Page,
  regionBox: { x: number; y: number },
  snapshotDimensions: { width: number; height: number },
) => {
  const viewportSize = page.viewportSize();
  const documentSize = await page.evaluate(() => ({
    height: Math.max(
      document.body.scrollHeight,
      document.documentElement.scrollHeight,
    ),
    width: Math.max(document.body.scrollWidth, document.documentElement.scrollWidth),
  }));
  const maxX = Math.max(
    0,
    Math.min(viewportSize?.width ?? documentSize.width, documentSize.width) -
      snapshotDimensions.width,
  );
  const maxY = Math.max(
    0,
    Math.min(viewportSize?.height ?? documentSize.height, documentSize.height) -
      snapshotDimensions.height,
  );

  return {
    x: Math.min(Math.max(0, regionBox.x), maxX),
    y: Math.min(Math.max(0, regionBox.y), maxY),
    width: snapshotDimensions.width,
    height: snapshotDimensions.height,
  };
};

/**
 * Builds a fully-qualified URL.
 */
export const buildE2eUrl = (path: string) => buildUrl(path);

/**
 * Selects a site or community stats container.
 */
export const getStatsContainer = (
  page: Page,
  pageKind: "site" | "community",
  viewport: "desktop" | "mobile",
) => {
  const selector =
    viewport === "desktop" ? "div.hidden.lg\\:flex" : "div.grid.lg\\:hidden";

  return page
    .locator(selector)
    .filter({ has: page.getByText("Groups", { exact: true }) })
    .first();
};

/**
 * Selects a stat value within a stats container.
 */
export const getStatValue = (statsContainer: Locator, statLabel: string) => {
  const labelElement = statsContainer.getByText(statLabel, { exact: true });
  const statBlock = labelElement.locator("..");

  return statBlock.locator(".lg\\:text-4xl");
};

/**
 * Selects a section container from its visible heading.
 */
export const getSectionByHeading = (page: Page, heading: string) =>
  page.getByText(heading, { exact: true }).locator("..").locator("..");

/**
 * Selects a responsive link within a heading-based section.
 */
export const getSectionLink = (
  page: Page,
  heading: string,
  linkName: string,
  viewport: "desktop" | "mobile",
) => {
  const section = getSectionByHeading(page, heading);

  return viewport === "desktop"
    ? section.locator("div.hidden.md\\:flex").getByRole("link", { name: linkName })
    : section.locator("div.md\\:hidden").getByRole("link", { name: linkName });
};

/**
 * Selects a community banner variant on the site home page.
 */
export const getCommunityBanner = (
  page: Page,
  displayName: string,
  viewport: "desktop" | "mobile",
) => {
  const selector =
    viewport === "desktop"
      ? "div.hidden.sm\\:block"
      : "div.aspect-\\[61\\/12\\].sm\\:hidden";

  return page
    .locator(selector)
    .filter({ has: page.getByAltText(`${displayName} banner`) })
    .first();
};

/**
 * Selects the public attendance controls container.
 */
export const getAttendanceContainer = (page: Page) =>
  page.locator("[data-attendance-container]").first();

/**
 * Selects the public attend button.
 */
export const getAttendButton = (page: Page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="attend-btn"]');

/**
 * Selects the public leave button.
 */
export const getLeaveButton = (page: Page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="leave-btn"]');

/**
 * Waits until public attendance controls resolve to a stable state.
 */
export const waitForAttendanceState = async (page: Page) => {
  await Promise.race([
    getAttendButton(page).waitFor({ state: "visible" }),
    getLeaveButton(page).waitFor({ state: "visible" }),
  ]);
};

/**
 * Selects an event detail card from its heading.
 */
export const getEventInfoSection = (page: Page, heading: string) =>
  page.getByText(heading, { exact: true }).locator("..").locator("..");

/**
 * Selects the event about section.
 */
export const getEventAboutSection = (page: Page) =>
  page.getByText("About this event", { exact: true }).locator("..");

/**
 * Selects the event logo in the page intro.
 */
export const getEventLogo = (page: Page) =>
  getIntroSection(page).locator("img").first();

/**
 * Selects the stable intro section used by community, group, and event pages.
 */
export const getIntroSection = (page: Page) =>
  page
    .getByRole("heading", { level: 1 })
    .locator("xpath=ancestor::div[parent::div[contains(@class,'gap-y-6')]][1]");

/**
 * Selects the community about block without including the following sections.
 */
export const getCommunityAboutSection = (page: Page) =>
  page.locator(".community-description").locator("..");

/**
 * Selects the stable home jumbotron content without outer container padding.
 */
export const getHomeJumbotronContent = (page: Page) =>
  page
    .getByRole("heading", { level: 1 })
    .locator("xpath=ancestor::div[contains(@class,'text-center')][1]");

/**
 * Selects the explore search row above the results list.
 */
export const getExploreSearchRow = (page: Page, searchPlaceholder: string) =>
  page
    .getByPlaceholder(searchPlaceholder)
    .locator("xpath=ancestor::div[contains(@class,'items-center')][1]");

/**
 * Selects the explore controls row above the results list.
 */
export const getExploreControlsRow = (page: Page) =>
  page
    .locator("#results")
    .locator("xpath=ancestor::div[contains(@class,'justify-between')][1]");

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
 * Waits for a page to settle before taking a visual snapshot.
 */
export const expectPageScreenshot = async (
  page: Page,
  screenshotName: string,
  screenshotOptions: {
    mask?: Locator[];
    maxDiffPixels?: number;
    maxDiffPixelRatio?: number;
  } = {},
) => {
  await waitForVisualReady(page);
  await waitForVisualImages(page.locator("body"));

  await expect(page).toHaveScreenshot(screenshotName, {
    animations: "disabled",
    caret: "hide",
    fullPage: true,
    ...screenshotOptions,
  });
};

/**
 * Waits for a stable region and snapshots only that locator.
 */
export const expectRegionScreenshot = async (
  page: Page,
  region: Locator,
  screenshotName: string,
  screenshotOptions: {
    mask?: Locator[];
    maxDiffPixels?: number;
    maxDiffPixelRatio?: number;
    testInfo?: TestInfo;
    useClippedPageScreenshot?: boolean;
  } = {},
) => {
  const {
    mask,
    maxDiffPixels,
    maxDiffPixelRatio,
    testInfo,
    useClippedPageScreenshot = false,
  } = screenshotOptions;
  const clippedPageScreenshotDiffRatio =
    process.env.CI === "true" && useClippedPageScreenshot ? 0.08 : undefined;
  const snapshotDiffOptions = {
    ...(maxDiffPixels === undefined ? {} : { maxDiffPixels }),
    ...((maxDiffPixelRatio ?? clippedPageScreenshotDiffRatio) === undefined
      ? {}
      : { maxDiffPixelRatio: maxDiffPixelRatio ?? clippedPageScreenshotDiffRatio }),
  };

  await waitForVisualReady(page);
  await expect(region).toBeVisible();
  await region.scrollIntoViewIfNeeded();
  await waitForVisualImages(region);

  if (testInfo) {
    const snapshotDimensions = getPngDimensions(testInfo.snapshotPath(screenshotName));
    const regionBox = await region.boundingBox();
    const shouldUseClippedPageScreenshot =
      useClippedPageScreenshot ||
      (snapshotDimensions &&
        regionBox &&
        hasTinySnapshotDimensionDrift(regionBox, snapshotDimensions));

    if (shouldUseClippedPageScreenshot && snapshotDimensions && regionBox) {
      const clip = await getClippedScreenshotBox(page, regionBox, snapshotDimensions);

      await expect(page).toHaveScreenshot(screenshotName, {
        animations: "disabled",
        caret: "hide",
        mask,
        clip,
        scale: "css",
        ...snapshotDiffOptions,
      });

      return;
    }
  }

  await expect(region).toHaveScreenshot(screenshotName, {
    animations: "disabled",
    caret: "hide",
    mask,
    ...snapshotDiffOptions,
  });
};

/**
 * Chooses a timezone from the custom timezone selector.
 */
export const selectTimezone = async (page: Page, timezone: string) => {
  const timezoneSelector = page.locator('timezone-selector[name="timezone"]');
  await timezoneSelector.locator("#timezone-selector-button").click();

  const searchInput = timezoneSelector.locator("#timezone-search-input");
  await expect(searchInput).toBeVisible();
  await searchInput.fill(timezone);

  const option = timezoneSelector.getByRole("option", { name: timezone, exact: true });
  await expect(option).toBeVisible();
  await option.click();

  await expect(
    timezoneSelector.locator('input[name="timezone"]'),
  ).toHaveValue(timezone);
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
