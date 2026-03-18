import { test as base, expect } from "@playwright/test";
import type { Browser, BrowserContext, Page } from "@playwright/test";

import {
  TEST_COMMUNITY_IDS,
  TEST_GROUP_IDS,
  TEST_USER_CREDENTIALS,
  logInWithSeededUser,
  selectCommunityContext,
  selectGroupContext,
} from "./utils";

type PreparedPage = {
  page: Page;
  close: () => Promise<void>;
};

type E2eFixtures = {
  adminCommunityPage: Page;
  communityViewerPage: Page;
  organizerGroupPage: Page;
  eventsManagerGroupPage: Page;
  groupViewerPage: Page;
  member1Page: Page;
  member2Page: Page;
  pending1Page: Page;
};

type BrowserStorageState = Awaited<ReturnType<BrowserContext["storageState"]>>;

const storageStateCache = new Map<string, BrowserStorageState>();

/**
 * Returns a cached authenticated storage state for a seeded E2E user.
 */
const getStorageState = async (
  browser: Browser,
  credentials: (typeof TEST_USER_CREDENTIALS)[keyof typeof TEST_USER_CREDENTIALS],
) => {
  const cachedState = storageStateCache.get(credentials.username);

  if (cachedState) {
    return cachedState;
  }

  const context = await browser.newContext();
  const page = await context.newPage();

  await logInWithSeededUser(page, credentials);

  const storageState = await context.storageState();
  storageStateCache.set(credentials.username, storageState);
  await context.close();

  return storageState;
};

/**
 * Creates an authenticated page and applies optional dashboard context setup.
 */
const createPreparedPage = async (
  browser: Browser,
  credentials: (typeof TEST_USER_CREDENTIALS)[keyof typeof TEST_USER_CREDENTIALS],
  preparePage?: (page: Page) => Promise<void>,
): Promise<PreparedPage> => {
  const storageState = await getStorageState(browser, credentials);
  const context = await browser.newContext({ storageState });
  const page = await context.newPage();

  if (preparePage) {
    await preparePage(page);
  }

  return {
    page,
    close: async () => context.close(),
  };
};

/**
 * Builds a reusable page fixture for an authenticated seeded user.
 */
const authenticatedPageFixture = (
  credentials: (typeof TEST_USER_CREDENTIALS)[keyof typeof TEST_USER_CREDENTIALS],
  preparePage?: (page: Page) => Promise<void>,
) =>
  async ({ browser }: { browser: Browser }, use: (page: Page) => Promise<void>) => {
    const preparedPage = await createPreparedPage(browser, credentials, preparePage);

    try {
      await use(preparedPage.page);
    } finally {
      await preparedPage.close();
    }
  };

export const test = base.extend<E2eFixtures>({
  adminCommunityPage: authenticatedPageFixture(TEST_USER_CREDENTIALS.admin1, (page) =>
    selectCommunityContext(page, TEST_COMMUNITY_IDS.community1),
  ),
  communityViewerPage: authenticatedPageFixture(
    TEST_USER_CREDENTIALS.communityViewer1,
    (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.community1),
  ),
  organizerGroupPage: authenticatedPageFixture(TEST_USER_CREDENTIALS.organizer1, (page) =>
    selectGroupContext(
      page,
      TEST_COMMUNITY_IDS.community1,
      TEST_GROUP_IDS.community1.alpha,
    ),
  ),
  eventsManagerGroupPage: authenticatedPageFixture(
    TEST_USER_CREDENTIALS.eventsManager1,
    (page) =>
      selectGroupContext(
        page,
        TEST_COMMUNITY_IDS.community1,
        TEST_GROUP_IDS.community1.alpha,
      ),
  ),
  groupViewerPage: authenticatedPageFixture(TEST_USER_CREDENTIALS.groupViewer1, (page) =>
    selectGroupContext(
      page,
      TEST_COMMUNITY_IDS.community1,
      TEST_GROUP_IDS.community1.alpha,
    ),
  ),
  member1Page: authenticatedPageFixture(TEST_USER_CREDENTIALS.member1),
  member2Page: authenticatedPageFixture(TEST_USER_CREDENTIALS.member2),
  pending1Page: authenticatedPageFixture(TEST_USER_CREDENTIALS.pending1),
});

export { expect };
