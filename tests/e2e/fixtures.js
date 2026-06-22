import { test as base, expect } from "@playwright/test";

import {
  buildE2eUrl,
  TEST_ALLIANCE_IDS,
  TEST_GROUP_IDS,
  TEST_USER_CREDENTIALS,
  logInWithSeededUser,
  selectAllianceContext,
  selectGroupContext,
} from "./utils.js";

const storageStateCache = new Map();

/** Returns true when the cached storage state still has an authenticated session. */
const hasValidSession = async (page) => {
  const response = await page.request.get(buildE2eUrl("/dashboard/user"));

  return response.ok();
};

/** Returns a cached authenticated storage state for a seeded E2E user. */
const getStorageState = async (browser, credentials) => {
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

/** Creates an authenticated page and applies optional dashboard context setup. */
const createPreparedPage = async (browser, credentials, preparePage) => {
  let storageState = await getStorageState(browser, credentials);
  let context = await browser.newContext({ storageState });
  let page = await context.newPage();

  if (!(await hasValidSession(page))) {
    storageStateCache.delete(credentials.username);
    await context.close();

    storageState = await getStorageState(browser, credentials);
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

/** Builds a reusable page fixture for an authenticated seeded user. */
const authenticatedPageFixture =
  (credentials, preparePage) =>
  async ({ browser }, use) => {
    const preparedPage = await createPreparedPage(
      browser,
      credentials,
      preparePage,
    );

    try {
      await use(preparedPage.page);
    } finally {
      await preparedPage.close();
    }
  };

export const test = base.extend({
  adminAlliancePage: authenticatedPageFixture(
    TEST_USER_CREDENTIALS.admin1,
    (page) => selectAllianceContext(page, TEST_ALLIANCE_IDS.alliance1),
  ),
  allianceViewerPage: authenticatedPageFixture(
    TEST_USER_CREDENTIALS.allianceViewer1,
    (page) => selectAllianceContext(page, TEST_ALLIANCE_IDS.alliance1),
  ),
  organizerGroupPage: authenticatedPageFixture(
    TEST_USER_CREDENTIALS.organizer1,
    (page) =>
      selectGroupContext(
        page,
        TEST_ALLIANCE_IDS.alliance1,
        TEST_GROUP_IDS.alliance1.alpha,
      ),
  ),
  organizerGroupWithoutPaymentsPage: authenticatedPageFixture(
    TEST_USER_CREDENTIALS.organizer2,
    (page) =>
      selectGroupContext(
        page,
        TEST_ALLIANCE_IDS.alliance2,
        TEST_GROUP_IDS.alliance2.delta,
      ),
  ),
  eventsManagerGroupPage: authenticatedPageFixture(
    TEST_USER_CREDENTIALS.eventsManager1,
    (page) =>
      selectGroupContext(
        page,
        TEST_ALLIANCE_IDS.alliance1,
        TEST_GROUP_IDS.alliance1.alpha,
      ),
  ),
  groupViewerPage: authenticatedPageFixture(
    TEST_USER_CREDENTIALS.groupViewer1,
    (page) =>
      selectGroupContext(
        page,
        TEST_ALLIANCE_IDS.alliance1,
        TEST_GROUP_IDS.alliance1.alpha,
      ),
  ),
  member1Page: authenticatedPageFixture(TEST_USER_CREDENTIALS.member1),
  member2Page: authenticatedPageFixture(TEST_USER_CREDENTIALS.member2),
  pending1Page: authenticatedPageFixture(TEST_USER_CREDENTIALS.pending1),
  pending2Page: authenticatedPageFixture(TEST_USER_CREDENTIALS.pending2),
});

export { expect };
