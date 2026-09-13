import { test as base, expect } from "@playwright/test";

import { TEST_COMMUNITY_IDS, TEST_GROUP_IDS, TEST_USER_CREDENTIALS } from "./seed.js";
import { buildE2eUrl, logInWithSeededUser, selectCommunityContext, selectGroupContext } from "./utils.js";

// Authenticated page fixtures: seeded credentials plus the dashboard context they select.
const AUTHENTICATED_PAGE_FIXTURES = {
  adminCommunityPage: {
    credentials: TEST_USER_CREDENTIALS.admin1,
    preparePage: (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.community1),
  },
  adminEmptyCommunityPage: {
    credentials: TEST_USER_CREDENTIALS.admin1,
    preparePage: (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.empty),
  },
  adminSecondaryCommunityPage: {
    credentials: TEST_USER_CREDENTIALS.admin2,
    preparePage: (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.community2),
  },
  checkInManagerGroupPage: {
    credentials: TEST_USER_CREDENTIALS.checkInManager1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.alpha),
  },
  communityViewerPage: {
    credentials: TEST_USER_CREDENTIALS.communityViewer1,
    preparePage: (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.community1),
  },
  emptyUserPage: { credentials: TEST_USER_CREDENTIALS.empty },
  eventsManagerGroupPage: {
    credentials: TEST_USER_CREDENTIALS.eventsManager1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.alpha),
  },
  groupViewerPage: {
    credentials: TEST_USER_CREDENTIALS.groupViewer1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.alpha),
  },
  groupsManagerPage: { credentials: TEST_USER_CREDENTIALS.groupsManager1 },
  member1Page: { credentials: TEST_USER_CREDENTIALS.member1 },
  member2Page: { credentials: TEST_USER_CREDENTIALS.member2 },
  organizerEmptyGroupPage: {
    credentials: TEST_USER_CREDENTIALS.organizer1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.empty),
  },
  organizerExternalGroupPage: {
    credentials: TEST_USER_CREDENTIALS.organizer1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.externalPayments),
  },
  organizerGroupPage: {
    credentials: TEST_USER_CREDENTIALS.organizer1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.alpha),
  },
  organizerGroupWithoutPaymentsPage: {
    credentials: TEST_USER_CREDENTIALS.organizer2,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community2, TEST_GROUP_IDS.community2.delta),
  },
  pending1Page: { credentials: TEST_USER_CREDENTIALS.pending1 },
  pending2Page: { credentials: TEST_USER_CREDENTIALS.pending2 },
};

// Storage state is cached per fixture name so fixtures sharing a user never share a context.
const storageStateCache = new Map();

/** Builds a reusable page fixture for an authenticated seeded user. */
const authenticatedPageFixture = (fixtureName, { credentials, preparePage }) => {
  return async ({ browser }, use) => {
    const preparedPage = await createPreparedPage(browser, fixtureName, credentials, preparePage);

    try {
      await use(preparedPage.page);
    } finally {
      await preparedPage.close();
    }
  };
};

/** Creates an authenticated page, re-logging in when the cached session is no longer valid. */
const createPreparedPage = async (browser, fixtureName, credentials, preparePage) => {
  let storageState = await getStorageState(browser, fixtureName, credentials);
  let context = await browser.newContext({ storageState });
  let page = await context.newPage();

  if (!(await hasValidSession(page))) {
    storageStateCache.delete(fixtureName);
    await context.close();

    storageState = await getStorageState(browser, fixtureName, credentials);
    context = await browser.newContext({ storageState });
    page = await context.newPage();
  }

  if (preparePage) {
    await preparePage(page);
  }

  return {
    page,
    close: async () => context.close(),
  };
};

/** Returns a cached authenticated storage state for a fixture, logging in on first use. */
const getStorageState = async (browser, fixtureName, credentials) => {
  const cachedState = storageStateCache.get(fixtureName);

  if (cachedState) {
    return cachedState;
  }

  const context = await browser.newContext();
  const page = await context.newPage();

  await logInWithSeededUser(page, credentials);

  const storageState = await context.storageState();
  storageStateCache.set(fixtureName, storageState);
  await context.close();

  return storageState;
};

/**
 * Returns true only when the dashboard answers 200 directly. Redirects are not followed so an expired session
 * (302 to /log-in) is detected instead of being mistaken for a valid one.
 */
const hasValidSession = async (page) => {
  const response = await page.request.get(buildE2eUrl("/dashboard/user"), { maxRedirects: 0 });

  return response.status() === 200;
};

export const test = base.extend(
  Object.fromEntries(
    Object.entries(AUTHENTICATED_PAGE_FIXTURES).map(([fixtureName, definition]) => [
      fixtureName,
      authenticatedPageFixture(fixtureName, definition),
    ]),
  ),
);

export { expect };
